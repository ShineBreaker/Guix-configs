#!/usr/bin/env python3
"""Extract assistant text and semantic status from Pi JSON stream events."""
import argparse
import json
import os
import shutil
import sys
import textwrap
from datetime import datetime


USE_COLOR = sys.stderr.isatty() and not os.environ.get("NO_COLOR")
TERM_WIDTH = max(60, min(120, shutil.get_terminal_size((100, 24)).columns))


class Style:
    reset = "\033[0m" if USE_COLOR else ""
    bold = "\033[1m" if USE_COLOR else ""
    dim = "\033[2m" if USE_COLOR else ""
    red = "\033[31m" if USE_COLOR else ""
    green = "\033[32m" if USE_COLOR else ""
    yellow = "\033[33m" if USE_COLOR else ""
    blue = "\033[34m" if USE_COLOR else ""
    magenta = "\033[35m" if USE_COLOR else ""
    cyan = "\033[36m" if USE_COLOR else ""


def paint(text, *styles):
    if not USE_COLOR:
        return text
    return "".join(styles) + text + Style.reset


def now():
    return datetime.now().strftime("%H:%M:%S")


def wrap_line(text, *, indent="  ", initial="  ", limit=None):
    width = limit or TERM_WIDTH
    return textwrap.fill(
        text,
        width=width,
        initial_indent=initial,
        subsequent_indent=indent,
        break_long_words=False,
        break_on_hyphens=False,
    )


def rule(title):
    ensure_assistant_break()
    label = f" {title} "
    available = max(0, TERM_WIDTH - len(label) - 2)
    left = available // 2
    right = available - left
    emit(paint("-" * left + label + "-" * right, Style.dim))


def log_line(label, message="", *, color=Style.cyan):
    ensure_assistant_break()
    stamp = paint(now(), Style.dim)
    tag = paint(f"[{label}]", color, Style.bold)
    if message:
        emit(f"{stamp} {tag} {message}")
    else:
        emit(f"{stamp} {tag}")


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


def short(value, limit=240):
    if value is None:
        return ""
    if isinstance(value, str):
        text = value
    else:
        try:
            text = json.dumps(value, ensure_ascii=False)
        except TypeError:
            text = str(value)
    text = " ".join(text.split())
    if len(text) > limit:
        return text[: limit - 3] + "..."
    return text


def pretty_json(value, limit=260):
    if value is None:
        return ""
    if isinstance(value, str):
        return short(value, limit)
    try:
        rendered = json.dumps(value, ensure_ascii=False, sort_keys=True)
    except TypeError:
        rendered = str(value)
    return short(rendered, limit)


def result_text(result):
    if not isinstance(result, dict):
        return ""
    content = result.get("content")
    if not isinstance(content, list):
        return ""
    texts = []
    for part in content:
        if isinstance(part, dict) and part.get("type") == "text" and isinstance(part.get("text"), str):
            texts.append(part["text"])
    return "\n".join(texts)


def emit(line=""):
    print(line, file=sys.stderr, flush=True)


def ensure_assistant_break():
    global assistant_line_open
    if globals().get("assistant_line_open"):
        emit()
        assistant_line_open = False


parser = argparse.ArgumentParser()
parser.add_argument("--meta", help="write structured result metadata to this JSON file")
cli_args = parser.parse_args()

last_text = ""
stop_reason = None
error_message = None
seen_assistant_end = False
printed_header = False
running_tools = {}
assistant_started = False
emitted_assistant = ""
assistant_line_open = False


def emit_assistant(text, *, final=False):
    global assistant_started, assistant_line_open, emitted_assistant
    if not text:
        return

    if not assistant_started:
        emit()
        rule("assistant")
        assistant_started = True

    if text.startswith(emitted_assistant):
        delta = text[len(emitted_assistant) :]
    else:
        if emitted_assistant and not emitted_assistant.endswith("\n"):
            emit()
        delta = text

    if delta:
        print(delta, end="", file=sys.stderr, flush=True)
        assistant_line_open = not delta.endswith("\n")
        emitted_assistant = text

    if final:
        ensure_assistant_break()
        rule("done")

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue

    event_type = obj.get("type")

    if not printed_header:
        rule("subagent stream")
        printed_header = True

    if event_type == "agent_start":
        log_line("agent", "started", color=Style.green)
        continue

    if event_type == "message_update":
        msg = obj.get("message", obj)
        if isinstance(msg, dict) and msg.get("role") == "assistant":
            emit_assistant(text_from_message(msg))
        continue

    if event_type == "tool_execution_start":
        tool_id = obj.get("toolCallId", "")
        tool_name = obj.get("toolName", "tool")
        running_tools[tool_id] = tool_name
        tool_args = pretty_json(obj.get("args"))
        message = paint(tool_name, Style.bold)
        if tool_args:
            message += paint("  args: ", Style.dim) + tool_args
        log_line("tool+", message, color=Style.blue)
        continue

    if event_type == "tool_execution_update":
        tool_name = obj.get("toolName") or running_tools.get(obj.get("toolCallId"), "tool")
        partial = short(result_text(obj.get("partialResult")) or obj.get("partialResult"), 160)
        if partial:
            message = paint(tool_name, Style.bold) + paint("  update: ", Style.dim) + partial
            log_line("tool.", message, color=Style.magenta)
        continue

    if event_type == "tool_execution_end":
        tool_id = obj.get("toolCallId", "")
        tool_name = obj.get("toolName") or running_tools.pop(tool_id, "tool")
        running_tools.pop(tool_id, None)
        failed = bool(obj.get("isError"))
        status = "failed" if failed else "done"
        summary = short(result_text(obj.get("result")) or obj.get("result"), 240)
        message = paint(tool_name, Style.bold) + paint(f"  {status}", Style.dim)
        if summary:
            message += "\n" + wrap_line(summary, initial="  -> ", indent="     ")
        log_line("tool!", message, color=Style.red if failed else Style.green)
        continue

    if event_type == "agent_end":
        log_line("agent", "finished", color=Style.green)
        continue

    if event_type == "error" and isinstance(obj.get("error"), str):
        error_message = obj["error"]
        log_line("error", error_message, color=Style.red)
        continue

    if event_type != "message_end":
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
        emit_assistant(text, final=True)

result = {
    "text": last_text,
    "stopReason": stop_reason,
    "errorMessage": error_message,
    "seenAssistantEnd": seen_assistant_end,
}

if cli_args.meta:
    with open(cli_args.meta, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False)

if last_text:
    sys.stdout.write(last_text)
elif error_message:
    sys.stdout.write(error_message)

if error_message or stop_reason in {"error", "aborted"}:
    sys.exit(2)
if not seen_assistant_end:
    sys.exit(3)
