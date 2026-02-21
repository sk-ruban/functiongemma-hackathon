"""
Spike Bridge Server
Local FastAPI server bridging Swift UI to Cactus on-device inference.
Run: uvicorn server:app --host 127.0.0.1 --port 8420
"""

import sys, os, json, tempfile
sys.path.insert(0, "../../cactus/python/src")

from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import JSONResponse
from cactus import cactus_init, cactus_transcribe, cactus_destroy

# Import generate_hybrid from the hackathon main.py
sys.path.insert(0, "../..")
from main import generate_hybrid

app = FastAPI()

# ── Model paths (adjust if needed) ──
WHISPER_PATH = "../../cactus/weights/whisper-small"
FUNCTIONGEMMA_PATH = "../../cactus/weights/functiongemma-270m-it"

# ── Tool definitions ──
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
async def transcribe_and_act(audio: UploadFile = File(...)):
    """
    Full pipeline: audio → transcription → tool routing → response.

    Returns JSON:
    {
        "transcription": "open safari and type hello",
        "function_calls": [
            {"name": "open_app", "arguments": {"name": "Safari"}},
            {"name": "type_text", "arguments": {"text": "hello"}}
        ],
        "source": "on-device" | "cloud (fallback)",
        "confidence": 0.95,
        "total_time_ms": 234.5,
        "transcription_time_ms": 89.2,
        "routing_time_ms": 145.3
    }
    """
    import time

    # ── Step 1: Save uploaded audio to temp file ──
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        content = await audio.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        # ── Step 2: Transcribe with Cactus Whisper ──
        t0 = time.time()
        whisper = cactus_init(WHISPER_PATH)
        prompt = "<|startoftranscript|><|en|><|transcribe|><|notimestamps|>"
        transcript_raw = cactus_transcribe(whisper, tmp_path, prompt)
        transcript = json.loads(transcript_raw).get("response", "")
        cactus_destroy(whisper)
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

        # ── Step 3: Route through generate_hybrid ──
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

    finally:
        os.unlink(tmp_path)


@app.get("/health")
async def health():
    return {"status": "ok"}
