#!/usr/bin/env python3
"""Extract assistant text and semantic status from Pi JSON stream events."""
import argparse
import json
import sys


def text_from_message(msg):
    parts = msg.get("content", [])
    if isinstance(parts, str):
        return parts
    if not isinstance(parts, list):
        return ""

    texts = []
    for part in parts:
        if isinstance(part, dict) and part.get("type") == "text" and isinstance(part.get("text"), str):
            texts.append(part["text"])
    return "\n".join(texts)


parser = argparse.ArgumentParser()
parser.add_argument("--meta", help="write structured result metadata to this JSON file")
args = parser.parse_args()

last_text = ""
stop_reason = None
error_message = None
seen_assistant_end = False

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue

    if obj.get("type") == "error" and isinstance(obj.get("error"), str):
        error_message = obj["error"]
        continue

    if obj.get("type") != "message_end":
        continue

    msg = obj.get("message", obj)
    if not isinstance(msg, dict) or msg.get("role") != "assistant":
        continue

    seen_assistant_end = True
    stop_reason = msg.get("stopReason") or obj.get("stopReason") or stop_reason
    error_message = msg.get("errorMessage") or obj.get("errorMessage") or error_message

    text = text_from_message(msg)
    if text:
        last_text = text

result = {
    "text": last_text,
    "stopReason": stop_reason,
    "errorMessage": error_message,
    "seenAssistantEnd": seen_assistant_end,
}

if args.meta:
    with open(args.meta, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False)

if last_text:
    sys.stdout.write(last_text)
elif error_message:
    sys.stdout.write(error_message)

if error_message or stop_reason in {"error", "aborted"}:
    sys.exit(2)
if not seen_assistant_end:
    sys.exit(3)
