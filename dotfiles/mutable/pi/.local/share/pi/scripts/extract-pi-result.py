#!/usr/bin/env python3
"""Extract the last assistant text from Pi JSON stream events (one JSON object per line)."""
import sys
import json

last_text = ""
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        if obj.get("type") != "message_end":
            continue
        msg = obj.get("message", obj)
        if msg.get("role") != "assistant":
            continue
        for part in msg.get("content", []):
            if part.get("type") == "text":
                last_text = part["text"]
                break
    except (json.JSONDecodeError, KeyError, TypeError):
        continue

if last_text:
    sys.stdout.write(last_text)
