"""
Spike Bridge Server
Local FastAPI server bridging Swift UI to Cactus on-device inference.
Run: uvicorn server:app --host 127.0.0.1 --port 8420
"""

import sys, os, json, tempfile, threading, subprocess, wave

# Resolve all paths relative to the repo root so generate_hybrid finds its models
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
os.chdir(REPO_ROOT)

sys.path.insert(0, os.path.join(REPO_ROOT, "cactus/python/src"))

from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
from cactus import cactus_init, cactus_destroy
import cactus as _cactus_mod
import ctypes

sys.path.insert(0, REPO_ROOT)
from main import generate_hybrid

WHISPER_PATH = os.path.join(REPO_ROOT, "cactus/weights/whisper-small")

whisper_model = None
whisper_lock = threading.Lock()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global whisper_model
    whisper_model = cactus_init(WHISPER_PATH)
    yield
    if whisper_model is not None:
        cactus_destroy(whisper_model)
        whisper_model = None


app = FastAPI(lifespan=lifespan)

TOOLS = [
    {
        "name": "open_app",
        "description": "Open or switch to a macOS application by name",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Application name (e.g. Safari, Slack, Notes, Terminal, Finder)"}
            },
            "required": ["name"],
        },
    },
    {
        "name": "keyboard_shortcut",
        "description": "Press a keyboard shortcut in the current application",
        "parameters": {
            "type": "object",
            "properties": {
                "keys": {"type": "string", "description": "The keyboard shortcut to press (e.g. Cmd+T, Cmd+S, Cmd+Z, Cmd+W, Cmd+Shift+N, Cmd+Q)"}
            },
            "required": ["keys"],
        },
    },
    {
        "name": "type_text",
        "description": "Type text into the currently focused text field or application",
        "parameters": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "The text to type"}
            },
            "required": ["text"],
        },
    },
    {
        "name": "click_element",
        "description": "Click a button or UI element by its label in the current application",
        "parameters": {
            "type": "object",
            "properties": {
                "label": {"type": "string", "description": "The visible label or title of the button or element to click"}
            },
            "required": ["label"],
        },
    },
    {
        "name": "read_screen",
        "description": "Read aloud or return the visible text content of the current application window",
        "parameters": {
            "type": "object",
            "properties": {
                "app": {"type": "string", "description": "Application name to read from. Use 'frontmost' for the currently active app."}
            },
            "required": ["app"],
        },
    },
]


@app.post("/transcribe_and_act")
def transcribe_and_act(audio: UploadFile = File(...)):
    import time

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        content = audio.file.read()
        tmp.write(content)
        tmp_path = tmp.name

    af_path = tmp_path.replace(".wav", "") + "_af.wav"

    try:
        t0 = time.time()

        # Convert uploaded audio to guaranteed 16kHz mono PCM WAV
        subprocess.run(
            ["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@16000", tmp_path, af_path],
            check=True, capture_output=True,
        )

        # Re-write with clean 44-byte header (afconvert pads to 4096 which confuses cactus)
        clean_path = tmp_path.replace(".wav", "") + "_clean.wav"
        with wave.open(af_path, "rb") as rf:
            pcm = rf.readframes(rf.getnframes())
        with wave.open(clean_path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(16000)
            wf.writeframes(pcm)

        import shutil
        shutil.copy2(clean_path, "/tmp/spike_last_recording.wav")

        # Force filesystem flush before C code reads
        os.sync()

        prompt = "<|startoftranscript|><|en|><|transcribe|><|notimestamps|>"
        with whisper_lock:
            _cactus_mod._lib.cactus_reset(whisper_model)
            buf = ctypes.create_string_buffer(65536)
            opts = b'{"use_vad": false}'
            _cactus_mod._lib.cactus_transcribe(
                whisper_model,
                clean_path.encode(), prompt.encode(),
                buf, len(buf),
                opts, _cactus_mod.TokenCallback(), None,
                None, 0,
            )
            transcript_raw = buf.value.decode()
        print(f"[DEBUG] Whisper raw: {transcript_raw}")

        parsed = json.loads(transcript_raw) if transcript_raw else {}
        transcript = parsed.get("response", "") or ""
        print(f"[DEBUG] Transcript: '{transcript}'")
        transcription_time_ms = (time.time() - t0) * 1000

        if not transcript.strip():
            return JSONResponse({
                "transcription": "",
                "function_calls": [],
                "source": "none",
                "confidence": 0,
                "total_time_ms": transcription_time_ms,
                "transcription_time_ms": transcription_time_ms,
                "routing_time_ms": 0,
                "error": "Empty transcription"
            })

        t1 = time.time()
        messages = [{"role": "user", "content": transcript}]
        result = generate_hybrid(messages, TOOLS)
        routing_time_ms = (time.time() - t1) * 1000

        return JSONResponse({
            "transcription": transcript,
            "function_calls": result.get("function_calls", []),
            "source": result.get("source", "unknown"),
            "confidence": result.get("confidence", 0),
            "total_time_ms": transcription_time_ms + routing_time_ms,
            "transcription_time_ms": transcription_time_ms,
            "routing_time_ms": routing_time_ms,
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return JSONResponse(
            {"error": f"{type(e).__name__}: {e}"},
            status_code=500,
        )

    finally:
        base = tmp_path.replace(".wav", "")
        for p in [tmp_path, af_path, base + "_clean.wav"]:
            if os.path.exists(p):
                os.unlink(p)


@app.get("/health")
async def health():
    return {"status": "ok"}
