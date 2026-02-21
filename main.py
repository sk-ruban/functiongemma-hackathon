
import sys
sys.path.insert(0, "cactus/python/src")
functiongemma_path = "cactus/weights/functiongemma-270m-it"

import json, os, time, re
from cactus import cactus_init, cactus_complete, cactus_destroy, cactus_reset
from google import genai
from google.genai import types

DESCRIPTION_OVERRIDES = {
    "set_timer": "Set a countdown timer for a duration in minutes. NOT an alarm.",
    "set_alarm": "Set an alarm for a specific time of day. NOT a timer.",
    "create_reminder": "Create a reminder with a title and time.",
}

_model = None

def _get_model():
    global _model
    if _model is None:
        _model = cactus_init(functiongemma_path)
    return _model


def _repair_json(raw_str):
    """Attempt to fix common FunctionGemma JSON issues."""
    if not raw_str:
        return raw_str
    # Fix leading zeros in numbers (e.g. "minute":01 → "minute":1)
    raw_str = re.sub(r':\s*0+(\d+)', r':\1', raw_str)
    # Fix fullwidth colon (：) → normal colon
    raw_str = raw_str.replace('：', ':')
    # Remove <escape> tags
    raw_str = raw_str.replace('<escape>', '')
    return raw_str

def _fix_arguments(function_calls):
    """Post-process function call arguments."""
    for call in function_calls:
        args = call.get("arguments", {})
        for key, val in args.items():
            if isinstance(val, (int, float)) and val < 0:
                args[key] = abs(val)
    return function_calls


def generate_cactus(messages, tools):
    """Run function calling on-device via FunctionGemma + Cactus."""
    model = _get_model()
    cactus_reset(model)

    enriched_tools = []
    for t in tools:
        t_copy = dict(t)
        if t["name"] in DESCRIPTION_OVERRIDES:
            t_copy["description"] = DESCRIPTION_OVERRIDES[t["name"]]
        enriched_tools.append(t_copy)

    cactus_tools = [{
        "type": "function",
        "function": t,
    } for t in enriched_tools]

    raw_str = cactus_complete(
        model,
        [{"role": "system", "content": "You are a model that can do function calling with the following functions"}] + messages,
        tools=cactus_tools,
        force_tools=True,
        max_tokens=256,
        stop_sequences=["<|im_end|>", "<end_of_turn>"],
        confidence_threshold=0.1,
        tool_rag_top_k=0,
    )

    try:
        raw = json.loads(raw_str)
    except json.JSONDecodeError:
        try:
            raw = json.loads(_repair_json(raw_str))
        except json.JSONDecodeError:
            return {
                "function_calls": [],
                "total_time_ms": 0,
                "confidence": 0,
            }

    calls = _fix_arguments(raw.get("function_calls", []))

    return {
        "function_calls": calls,
        "total_time_ms": raw.get("total_time_ms", 0),
        "confidence": raw.get("confidence", 0),
    }


def generate_cloud(messages, tools):
    """Run function calling via Gemini Cloud API."""
    client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY"))

    gemini_tools = [
        types.Tool(function_declarations=[
            types.FunctionDeclaration(
                name=t["name"],
                description=t["description"],
                parameters=types.Schema(
                    type="OBJECT",
                    properties={
                        k: types.Schema(type=v["type"].upper(), description=v.get("description", ""))
                        for k, v in t["parameters"]["properties"].items()
                    },
                    required=t["parameters"].get("required", []),
                ),
            )
            for t in tools
        ])
    ]

    contents = [m["content"] for m in messages if m["role"] == "user"]

    start_time = time.time()

    gemini_response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=contents,
        config=types.GenerateContentConfig(tools=gemini_tools),
    )

    total_time_ms = (time.time() - start_time) * 1000

    function_calls = []
    for candidate in gemini_response.candidates:
        for part in candidate.content.parts:
            if part.function_call:
                function_calls.append({
                    "name": part.function_call.name,
                    "arguments": dict(part.function_call.args),
                })

    return {
        "function_calls": function_calls,
        "total_time_ms": total_time_ms,
    }


ACTION_VERBS = {"set", "check", "get", "send", "text", "play", "find", "remind",
                "look", "search", "create", "wake", "tell", "show", "turn", "make",
                "start", "message", "ask", "add", "cancel", "stop", "open"}

def _decompose_query(query):
    """Split multi-intent query into sub-queries. Only splits when word after
    conjunction is an action verb."""
    splitters = [" and ", ", ", " then ", " also ", " plus "]
    parts = [query]
    for splitter in splitters:
        new_parts = []
        for part in parts:
            candidates = part.split(splitter)
            if len(candidates) == 1:
                new_parts.append(part)
                continue
            merged = [candidates[0]]
            for c in candidates[1:]:
                first_word = c.strip().split()[0].lower() if c.strip() else ""
                if first_word in ACTION_VERBS:
                    merged.append(c.strip())
                else:
                    merged[-1] += splitter + c
            new_parts.extend(merged)
        parts = new_parts
    return [p.strip() for p in parts if p.strip()]


def generate_hybrid(messages, tools):
    """Hybrid inference with query decomposition for multi-intent queries."""
    user_msg = messages[-1]["content"] if messages else ""
    sub_queries = _decompose_query(user_msg)

    # Single intent — normal path
    if len(sub_queries) <= 1:
        local = generate_cactus(messages, tools)
        if local["function_calls"]:
            local["source"] = "on-device"
            return local
        cloud = generate_cloud(messages, tools)
        cloud["source"] = "cloud (fallback)"
        cloud["total_time_ms"] += local["total_time_ms"]
        return cloud

    # Multi-intent — per-sub-query with cloud fallback
    all_calls = []
    total_time = 0
    for sq in sub_queries:
        sub_messages = [{"role": "user", "content": sq}]
        local = generate_cactus(sub_messages, tools)
        total_time += local.get("total_time_ms", 0)
        if local["function_calls"]:
            all_calls.extend(local["function_calls"])
        else:
            cloud = generate_cloud(sub_messages, tools)
            total_time += cloud.get("total_time_ms", 0)
            all_calls.extend(cloud.get("function_calls", []))

    if all_calls:
        return {
            "function_calls": all_calls,
            "total_time_ms": total_time,
            "source": "on-device",
        }

    # Everything failed
    cloud = generate_cloud(messages, tools)
    cloud["source"] = "cloud (fallback)"
    cloud["total_time_ms"] += total_time
    return cloud


def print_result(label, result):
    """Pretty-print a generation result."""
    print(f"\n=== {label} ===\n")
    if "source" in result:
        print(f"Source: {result['source']}")
    if "confidence" in result:
        print(f"Confidence: {result['confidence']:.4f}")
    if "local_confidence" in result:
        print(f"Local confidence (below threshold): {result['local_confidence']:.4f}")
    print(f"Total time: {result['total_time_ms']:.2f}ms")
    for call in result["function_calls"]:
        print(f"Function: {call['name']}")
        print(f"Arguments: {json.dumps(call['arguments'], indent=2)}")


############## Example usage ##############

if __name__ == "__main__":
    tools = [{
        "name": "get_weather",
        "description": "Get current weather for a location",
        "parameters": {
            "type": "object",
            "properties": {
                "location": {
                    "type": "string",
                    "description": "City name",
                }
            },
            "required": ["location"],
        },
    }]

    messages = [
        {"role": "user", "content": "What is the weather in San Francisco?"}
    ]

    on_device = generate_cactus(messages, tools)
    print_result("FunctionGemma (On-Device Cactus)", on_device)

    cloud = generate_cloud(messages, tools)
    print_result("Gemini (Cloud)", cloud)

    hybrid = generate_hybrid(messages, tools)
    print_result("Hybrid (On-Device + Cloud Fallback)", hybrid)
