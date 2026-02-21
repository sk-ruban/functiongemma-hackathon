<img src="assets/banner.png" alt="Logo" style="border-radius: 30px; width: 100%;">

# FunctionGemma Optimisation & Spike app: Voice-to-Action

**Team:** Ruban (Solo Dev) | **Location:** Singapore

## Methodology

I iterated through several approaches before landing on the final architecture:

1. **System prompt tuning.** I changed FunctionGemma's system prompt from the default to `"You are a model that can do function calling with the following functions"` — this improved tool selection accuracy on multi-tool queries.

2. **Tool description engineering.** FunctionGemma kept confusing `set_timer` and `set_alarm`. I added explicit disambiguation: *"Set a countdown timer for a duration in minutes. NOT an alarm."* This reduced timer/alarm swaps significantly.

3. **Confidence threshold tuning.** I lowered `confidence_threshold` to 0.1 to prevent premature cloud handoffs — FunctionGemma's built-in confidence signal was too conservative, rejecting correct outputs. I handle routing ourselves instead of relying on the model's self-assessment.

4. **Model singleton with KV cache reset.** Loading FunctionGemma on every call cost ~500ms. I switched to loading once and calling `cactus_reset` between queries to clear state without reinitializing.

5. **Tool RAG disabled.** Set `tool_rag_top_k=0` to pass all tools to the model instead of letting Cactus pre-filter. The pre-filtering was dropping the correct tool on some queries.

6. **JSON repair layer.** FunctionGemma outputs malformed JSON — leading zeros (`"minute":01`), fullwidth colons, `<escape>` tags. I added a repair pass before parsing.

7. **Query decomposition.** Multi-intent queries failed when sent as one prompt. I split on conjunctions but only when the next word is an action verb — preventing false splits on phrases like "mac and cheese" or "R&B".

8. **Pronoun resolution.** After decomposition, "find Laura and send her a message" needs "her" replaced with "Laura" in the second sub-query. I extract proper nouns from earlier sub-queries and substitute pronouns.

9. **Argument post-processing.** The biggest win. Rather than trusting FunctionGemma's arguments, I extract them from the original query. This fixed hallucinated song names, broken PM conversions, and wrong timer values.

10. **Validation ordering.** Initially I validated *before* fixing arguments — which meant `minute=120` got rejected and fell to cloud. Flipping the order (fix first, validate after) converted several cloud fallbacks to on-device.

11. **Cloud output normalization.** Gemini returns protobuf types, not native Python. Trailing periods on strings (`"thanks for lunch."`) caused F1 mismatches. I cast all cloud arguments to native types and strip trailing punctuation.

## Results

| Metric | Value |
|--------|-------|
| F1 (tool call accuracy) | 0.96 |
| On-device ratio | ~60% |
| Avg latency | ~1400ms |
| Hard cases (multi-intent) | 98% F1, 100% on-device |

## Trade-offs

- **5 tools only** — FunctionGemma-270M gets confused with more. Five well-scoped tools give high on-device accuracy.
- **Sequential sub-query execution** — Multi-intent queries run N model calls. Parallel would be faster but risks race conditions on macOS actions.
- **Rule-based slot filling** — Doesn't help with completely novel argument schemas, but cloud fallback catches those.
- **Cloud fallback adds latency** — ~1000ms penalty, but ensures correctness over speed.

---

## What is Spike?

Spike is a macOS menu bar voice agent. Hold a hotkey, speak a command, and your Mac executes it — opens apps, types text, presses keyboard shortcuts, clicks UI elements, reads screen content. The entire pipeline runs on-device by default: **Cactus Whisper** for transcription, **FunctionGemma-270M** for tool routing, with **Gemini 2.5 Flash** as a cloud fallback only when on-device confidence is low.

## Architecture

```
Voice ──→ Cactus Whisper (on-device) ──→ Transcribed text
                                              │
                                              ▼
                                     Query Decomposition
                                     (split multi-intent)
                                              │
                                              ▼
                                   FunctionGemma (on-device)
                                   Intent classification
                                              │
                                              ▼
                                    Rule-Based Slot Filling
                                    Fix arguments from query
                                              │
                                              ▼
                                   Validation + Sanity Check
                                      │              │
                                    Pass           Fail
                                      │              │
                                      ▼              ▼
                                  On-Device     Gemini Flash
                                  (~250ms)      (cloud fallback)
                                      │              │
                                      └──────┬───────┘
                                              ▼
                                    Action Dispatcher
                                    (NSWorkspace, CGEvent,
                                     AXUIElement)
```

**Key insight:** FunctionGemma is excellent at picking *which* function to call but poor at extracting *accurate arguments*. I follow the same architecture as production voice assistants (Siri, Alexa): neural model for intent classification, rule-based extraction for entities. FunctionGemma always runs first — regex is never used for function selection.

## Hybrid Routing — How It Works

1. **Query Decomposition** — Multi-intent queries ("open Safari and type google.com") are split on action verbs. Each sub-query gets independent FunctionGemma inference.

2. **Pronoun Resolution** — "Find Laura and send her a message" → second sub-query becomes "send Laura a message".

3. **FunctionGemma Inference** — On-device intent classification. Picks the function from available tools. ~200-400ms.

4. **Argument Fixing** — Post-processor extracts accurate arguments from the original query text. Handles AM/PM time conversion, song names, contact names, locations, reminder titles. If the tool type is unknown, model's original arguments pass through.

5. **Validation** — Rejects garbage outputs: out-of-range hours/minutes, CJK hallucinations, ISO datetime formats. Cross-checks function names against query keywords (e.g., "remind" → must be `create_reminder`, not `set_alarm`).

6. **Cloud Fallback** — When validation fails, Gemini 2.5 Flash handles it. Total latency includes both on-device attempt + cloud call for full transparency.

## Technologies

| Component | Technology | Purpose |
|-----------|-----------|---------|
| On-device transcription | **Cactus Whisper** (`cactus_transcribe`) | Voice → text, fully local |
| On-device tool routing | **FunctionGemma-270M** via **Cactus** (`cactus_complete`) | Intent classification |
| Cloud fallback | **Gemini 2.5 Flash** (`google-genai`) | Handles cases FunctionGemma can't |
| App execution | **macOS** NSWorkspace, CGEvent, AXUIElement | Opens apps, types, clicks, reads screen |
| Bridge server | **FastAPI** (Python) | Connects Swift frontend to Cactus/Gemini |
| Frontend | **SwiftUI** menu bar app | Hotkey capture, audio recording, result display |
| Audio | **AVAudioRecorder** (16kHz mono PCM) | Captures voice input |

## What Makes Spike Different

**Privacy-first.** Voice, screen content, and commands stay on-device. Cloud is only used when FunctionGemma's confidence drops below threshold — and the user sees exactly when that happens via the on-device/cloud badge.

**Real execution.** This isn't a mock demo. Spike opens real apps, types real text, presses real keyboard shortcuts, and clicks real buttons via macOS Accessibility APIs.

**Low latency.** On-device path: ~250ms from voice to action. Cloud fallback: ~1300ms. Users feel the difference.

**Generalizable routing.** The hybrid logic handles any tool schema. Known tools get argument fixing for near-perfect accuracy. Unknown tools degrade gracefully to cloud — correct but slower.

---

## Context
- Cactus runs Google DeepMind's FunctionGemma at up to 3000 toks/sec prefill speed on M4 Macs.
- While decode speed reaches 200 tokens/sec, all without GPU, to remain energy-efficient. 
- FunctionGemma is great at tool calling, but small models are not the smartest for some tasks. 
- There is a need to dynamically combine edge and cloud (Gemini Flash) to get the best of both worlds. 
- Cactus develops various strategies for choosing when to fall back to Gemini or FunctionGemma.

## Challenge
- FunctionGemma is just a tool-call model, but tool calling is the core of agentic systems. 
- You MUST design new strategies that decide when to stick with on-device or fall to cloud. 
- You will be objectively ranked on tool-call correctness, speed and edge/cloud ratio (priortize local). 
- You can focus on prompting, tool description patterns, confidence score algorithms, anything!
- Please ensure at least 1 team member has a Mac, Cactus runs on Macs, mobile devices and wearables.

## Setup (clone this repo and hollistically follow)
- Step 1: Fork this repo, clone to your Mac, open terminal.
- Step 2: `git clone https://github.com/cactus-compute/cactus`
- Step 3: `cd cactus && source ./setup && cd ..` (re-run in new terminal)
- Step 4: `cactus build --python`
- Step 5: `cactus download google/functiongemma-270m-it --reconvert`
- Step 6: Get cactus key from the [cactus website](https://cactuscompute.com/dashboard/api-keys)
- Sept 7: Run `cactus auth` and enter your token when prompted.
- Step 8: `pip install google-genai`
- Step 9: Obtain Gemini API key from [Google AI Studio](https://aistudio.google.com/api-keys)
- Step 10: `export GEMINI_API_KEY="your-key"`
- Step 11: Click on location to get Gemini credits - [SF](https://trygcp.dev/claim/cactus-x-gdm-hackathon-sf), [Boston](https://trygcp.dev/claim/cactus-x-gdm-hackathon-boston), [DC](https://trygcp.dev/claim/cactus-x-gdm-hackathon-dc), [London](https://trygcp.dev/claim/cactus-x-gdm-hackathon-london), [Singapore](https://trygcp.dev/claim/cactus-x-gdm-hackathon), [Online](https://trygcp.dev/claim/cactus-x-gdm-hackathon-online)
- Step 12: Join the [Reddit channel](https://www.reddit.com/r/cactuscompute/), ask any technical questions there.
- Step 13: read and run `python benchmark.py` to understand how objective scoring works.
- Note: Final objective score will be done on held-out evals, top 10 are then judged subjectively.

## Submissions
- Your main task is to modify the **internal logic** of the `generate_hybrid` method in `main.py`. 
- Do not modify the input or output signature (function arguments and return variables) of the `generate_hybrid` method. Keep the hybrid interface compatible with `benchmark.py`.
- Submit to the leaderboard `python submit.py --team "YourTeamName" --location "YourCity"`, only 1x every 1hr.
- The dataset is a hidden Cactus eval, quite difficult for FunctionGemma by design.
- Use `python benchmark.py` to iterate, but your best score is preserved.
- For transparency, hackers can see live rankings on the [leaderboard](https://cactusevals.ngrok.app).
- Leaderboard will start accepting submissions once event starts. 
- The top hackers in each location will make it to judging.

## Qualitative Judging 
- **Rubric 1**: The quality of your hybrid routing algorithm, depth and cleverness.
- **Rubric 2**: End-to-end products that execute function calls to solve real-world problems. 
- **Rubric 3**: Building low-latency voice-to-action products, leveraging `cactus_transcribe`.

## Quick Example

```python
import json
from cactus import cactus_init, cactus_complete, cactus_destroy

model = cactus_init("weights/lfm2-vl-450m")
messages = [{"role": "user", "content": "What is 2+2?"}]
response = json.loads(cactus_complete(model, messages))
print(response["response"])

cactus_destroy(model)
```

## API Reference

### `cactus_init(model_path, corpus_dir=None)`

| Parameter | Type | Description |
|-----------|------|-------------|
| `model_path` | `str` | Path to model weights directory |
| `corpus_dir` | `str` | (Optional) dir of txt/md files for auto-RAG |

```python
model = cactus_init("weights/lfm2-vl-450m")
model = cactus_init("weights/lfm2-rag", corpus_dir="./documents")
```

### `cactus_complete(model, messages, **options)`

| Parameter | Type | Description |
|-----------|------|-------------|
| `model` | handle | Model handle from `cactus_init` |
| `messages` | `list\|str` | List of message dicts or JSON string |
| `tools` | `list` | Optional tool definitions for function calling |
| `temperature` | `float` | Sampling temperature |
| `top_p` | `float` | Top-p sampling |
| `top_k` | `int` | Top-k sampling |
| `max_tokens` | `int` | Maximum tokens to generate |
| `stop_sequences` | `list` | Stop sequences |
| `include_stop_sequences` | `bool` | Include matched stop sequences in output (default: `False`) |
| `force_tools` | `bool` | Constrain output to tool call format |
| `tool_rag_top_k` | `int` | Select top-k relevant tools via Tool RAG (default: 2, 0 = use all tools) |
| `confidence_threshold` | `float` | Minimum confidence for local generation (default: 0.7, triggers cloud_handoff when below) |
| `callback` | `fn` | Streaming callback `fn(token, token_id, user_data)` |

```python
# Basic completion
messages = [{"role": "user", "content": "Hello!"}]
response = cactus_complete(model, messages, max_tokens=100)
print(json.loads(response)["response"])
```

```python
# Completion with tools
tools = [{
    "name": "get_weather",
    "description": "Get weather for a location",
    "parameters": {
        "type": "object",
        "properties": {"location": {"type": "string"}},
        "required": ["location"]
    }
}]

response = cactus_complete(model, messages, tools=tools)
cactus_complete(model, messages, callback=on_token)
```

**Response format** (all fields always present):
```json
{
    "success": true,
    "error": null,
    "cloud_handoff": false,
    "response": "Hello! How can I help?",
    "function_calls": [],
    "confidence": 0.85,
    "time_to_first_token_ms": 45.2,
    "total_time_ms": 163.7,
    "prefill_tps": 619.5,
    "decode_tps": 168.4,
    "ram_usage_mb": 245.67,
    "prefill_tokens": 28,
    "decode_tokens": 50,
    "total_tokens": 78
}
```

**Cloud handoff response** (when model detects low confidence):
```json
{
    "success": false,
    "error": null,
    "cloud_handoff": true,
    "response": null,
    "function_calls": [],
    "confidence": 0.18,
    "time_to_first_token_ms": 45.2,
    "total_time_ms": 45.2,
    "prefill_tps": 619.5,
    "decode_tps": 0.0,
    "ram_usage_mb": 245.67,
    "prefill_tokens": 28,
    "decode_tokens": 0,
    "total_tokens": 28
}
```

- When `cloud_handoff` is `True`, the model's confidence dropped below `confidence_threshold` (default: 0.7) and recommends deferring to a cloud-based model for better results. 

- You will NOT rely on this, hackers must design custom strategies to fall-back to cloud, that maximizes on-devices and correctness, while minimizing end-to-end latency!

### `cactus_transcribe(model, audio_path, prompt="")`

| Parameter | Type | Description |
|-----------|------|-------------|
| `model` | handle | Whisper model handle |
| `audio_path` | `str` | Path to audio file (WAV) |
| `prompt` | `str` | Whisper prompt for language/task |

```python
whisper = cactus_init("weights/whisper-small")
prompt = "<|startoftranscript|><|en|><|transcribe|><|notimestamps|>"
response = cactus_transcribe(whisper, "audio.wav", prompt=prompt)
print(json.loads(response)["response"])
cactus_destroy(whisper)
```

### `cactus_embed(model, text, normalize=False)`

| Parameter | Type | Description |
|-----------|------|-------------|
| `model` | handle | Model handle |
| `text` | `str` | Text to embed |
| `normalize` | `bool` | L2-normalize embeddings (default: False) |

```python
embedding = cactus_embed(model, "Hello world")
print(f"Dimension: {len(embedding)}")
```

### `cactus_reset(model)`

Reset model state (clear KV cache). Call between unrelated conversations.

```python
cactus_reset(model)
```

### `cactus_stop(model)`

Stop an ongoing generation (useful with streaming callbacks).

```python
cactus_stop(model)
```

### `cactus_destroy(model)`

Free model memory. Always call when done.

```python
cactus_destroy(model)
```

### `cactus_get_last_error()`

Get the last error message, or `None` if no error.

```python
error = cactus_get_last_error()
if error:
    print(f"Error: {error}")
```

### `cactus_rag_query(model, query, top_k=5)`

Query RAG corpus for relevant text chunks. Requires model initialized with `corpus_dir`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `model` | handle | Model handle (must have corpus_dir set) |
| `query` | `str` | Query text |
| `top_k` | `int` | Number of chunks to retrieve (default: 5) |

```python
model = cactus_init("weights/lfm2-rag", corpus_dir="./documents")
chunks = cactus_rag_query(model, "What is machine learning?", top_k=3)
for chunk in chunks:
    print(f"Score: {chunk['score']:.2f} - {chunk['text'][:100]}...")
```

## Next steps:
- Join the [Reddit channel](https://www.reddit.com/r/cactuscompute/), ask any technical questions there.
- To gain some technical insights on AI, checkout [Maths, CS & AI Compendium](https://github.com/HenryNdubuaku/maths-cs-ai-compendium). 
