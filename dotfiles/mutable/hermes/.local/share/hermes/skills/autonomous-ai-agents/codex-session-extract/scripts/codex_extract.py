#!/usr/bin/env python3
"""Extract a codex rollout jsonl into a clean, information-dense markdown.

What we keep (high signal):
  - User messages (text + reasoning if not encrypted)
  - Assistant messages (text only — encrypted reasoning is dropped)
  - Tool calls (name + args) and tool outputs (truncated when very long)
  - Compaction summaries (handoff from prior model)
  - Per-turn metadata: timestamp, turn_id, model, effort, personality, cwd

What we drop (noise):
  - token_count / turn_aborted / turn_diff / task_started / task_complete events
  - world_state (AGENTS.md injection — same across all turns, not this session's dialogue)
  - session_meta JSON block (already in frontmatter)
  - base_instructions (codex boilerplate, ~16KB, not dialogue)
  - inter_agent_communication_metadata
  - Encrypted reasoning stubs (encrypted_content is opaque — not dialogue)

Usage: extract_codex_session.py <rollout.jsonl> <output.md>
"""

from __future__ import annotations
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from collections import Counter


# ---------- thresholds ----------
MAX_OUTPUT_INLINE = 800      # chars; outputs longer than this get folded
MAX_ARG_INLINE = 1500        # chars; tool-call args longer than this get folded
MIN_TEXT_KEEP = 0            # keep even 1-char messages (could be "ok" / "好")


# ---------- codex 0.144+ shim parser ----------
_TOOL_CALL_RE = re.compile(r'await\s+tools\.(\w+)\(')


def extract_json_from_shim(shim: str) -> str:
    """Pull the JSON literal out of `await tools.<name>({...});`.

    Strategy:
      1. Find the position right after `await tools.<name>(`
      2. Scan forward to find the matching `)`, counting nested parens
         (so `exec_command({"cmd":"echo )"})` doesn't get cut short)
      3. Extract what's between, try to parse as JSON, pretty-print

    Codex often chains multiple `await tools.<name>(...)` in one shim
    (e.g. `update_plan(...)` then `exec_command(...)`). The FIRST call is
    the primary one; we only extract it. Later calls are noise from the
    agent's planning that the user already sees in the conversation flow.

    Returns the JSON string if found, else the raw input.
    """
    if not shim:
        return ""
    m = _TOOL_CALL_RE.search(shim)
    if not m:
        return shim
    start = m.end()  # position right after the opening `(`
    # Find matching `)` accounting for nested parens + JSON string literals.
    depth = 1
    i = start
    in_string = False
    escape = False
    while i < len(shim):
        ch = shim[i]
        if escape:
            escape = False
            i += 1
            continue
        if ch == "\\" and in_string:
            escape = True
            i += 1
            continue
        if ch == '"' and not escape:
            in_string = not in_string
            i += 1
            continue
        if not in_string:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    break
        i += 1
    if depth != 0:
        return shim  # unbalanced — give up, return raw
    inner = shim[start:i].strip()
    try:
        obj = json.loads(inner)
        return json.dumps(obj, indent=2, default=str)
    except Exception:
        return inner


# ---------- helpers ----------

def ts_to_local(ts: str | None) -> str:
    if not ts:
        return ""
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return dt.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    except Exception:
        return ts


def shorten(s, n=120):
    s = "" if s is None else str(s)
    s = s.replace("\n", " ").strip()
    return s if len(s) <= n else s[:n] + "…"


def safe_json_loads(s):
    if isinstance(s, dict):
        return s
    if not s:
        return None
    try:
        return json.loads(s)
    except Exception:
        return None


def is_encrypted_reasoning(part: dict) -> bool:
    """codex wraps reasoning text in encrypted_content. Skip when we have no plaintext."""
    enc = part.get("encrypted_content")
    if enc and not part.get("text"):
        return True
    # also skip empty-text reasoning with only summary (and no plaintext text)
    if not part.get("text") and not part.get("summary"):
        return True
    return False


def fold_block(label: str, body: str, max_chars: int) -> str:
    """Render body inline if short, else as a fenced block + a <details> summary.

    Markdown: GitHub-flavored <details><summary> works in Hermes desktop renderer.
    """
    body = (body or "").rstrip()
    if not body:
        return ""
    if len(body) <= max_chars:
        return body + "\n\n"
    truncated = body[:max_chars]
    suffix = ""
    if len(body) > max_chars:
        suffix = f"\n\n<details><summary>{label} (truncated, {len(body):,} chars total — first {max_chars} shown)</summary>\n\n{body}\n\n</details>\n\n"
        return suffix
    return truncated + "\n\n"


def normalize_output(out) -> str:
    """function_call_output / custom_tool_call_output may be str OR list of content blocks.

    Filtering rules (drop noise):
      - blocks of type encrypted_content with no plaintext text → drop
      - blocks of type agent_message where ALL content parts are encrypted → drop
      - agent_message blocks keep their plaintext parts (e.g. FINAL_ANSWER body)
      - other blocks: append text field if present, else JSON-dump
    """
    if isinstance(out, list):
        parts = []
        for blk in out:
            if isinstance(blk, dict):
                btype = blk.get("type", "")
                content = blk.get("content")
                if btype == "agent_message" and isinstance(content, list):
                    # Strip encrypted parts from sub-agent messages; keep plaintext input_text.
                    txt_parts = [
                        c.get("text", "") for c in content
                        if isinstance(c, dict) and c.get("type") == "input_text" and c.get("text")
                    ]
                    if not txt_parts:
                        # all parts were encrypted — skip
                        continue
                    parts.append("".join(txt_parts))
                    continue
                if btype == "encrypted_content":
                    # skip pure encrypted blocks
                    continue
                if "text" in blk:
                    parts.append(str(blk["text"]))
                else:
                    parts.append(json.dumps(blk, default=str))
            else:
                parts.append(str(blk))
        return "\n".join(parts)
    if isinstance(out, str):
        return out
    return "" if out is None else str(out)


def extract_message_text_and_calls(content_list: list[dict]):
    """Return (markdown_text, [tool_calls]) for a user/assistant message.

    Filters out encrypted reasoning. Keeps plaintext reasoning if any.
    """
    md = []
    calls = []
    skipped_reasoning = 0
    for part in content_list or []:
        pt = part.get("type")
        if pt in ("text", "input_text", "output_text"):
            t = (part.get("text") or "").rstrip()
            if t:
                md.append(t + "\n\n")
        elif pt == "reasoning":
            if is_encrypted_reasoning(part):
                skipped_reasoning += 1
                continue
            t = (part.get("text") or "").strip()
            if not t and part.get("summary"):
                t = "\n".join(part.get("summary") or [])
            if t:
                md.append(f"> **Reasoning**\n>\n> {t.replace(chr(10), chr(10) + '> ')}\n\n")
        elif pt == "refusal":
            md.append(f"> **Refusal**: {part.get('refusal','')}\n\n")
        elif pt == "function_call":
            calls.append({
                "kind": "call",
                "name": part.get("name", ""),
                "arguments": part.get("arguments", ""),
                "call_id": part.get("call_id", ""),
            })
        elif pt == "function_call_output":
            calls.append({
                "kind": "output",
                "call_id": part.get("call_id", ""),
                "output": part.get("output", ""),
            })
        else:
            # unknown part: keep as JSON dump (rare, low signal)
            md.append(f"<!-- unknown content part: {pt} -->\n")
            md.append("```json\n" + json.dumps(part, default=str) + "\n```\n\n")
    return "".join(md), calls, skipped_reasoning


def render_tool_call(tc):
    args = tc.get("arguments", "")
    args_obj = safe_json_loads(args)
    args_render = json.dumps(args_obj, indent=2, default=str) if args_obj is not None else (args or "")
    cid = (tc.get("call_id") or "")[:12]
    out = [f"**🧰 Tool call — `{tc.get('name','')}`** (`call_id={cid}…`)\n\n"]
    if len(args_render) <= MAX_ARG_INLINE:
        out.append("```json\n" + args_render.rstrip() + "\n```\n\n")
    else:
        out.append("<details><summary>Arguments ({} chars)</summary>\n\n```json\n".format(len(args_render)))
        out.append(args_render.rstrip() + "\n```\n\n</details>\n\n")
    return "".join(out)


def render_tool_output(tc):
    """Render a tool output. Long outputs are truncated — keep first N chars as 'preview',
    and skip the rest of the body (it can always be re-fetched from the source jsonl).

    Length policy:
      - <= 800 chars  → full body inline
      - <= 4000 chars → first 800 inline + 'full output' note (collapsed)
      - >  4000 chars → first 800 inline + 'this output was N chars; not inlined' note
    """
    body = normalize_output(tc.get("output", ""))
    cid = (tc.get("call_id") or "")[:12]
    if not body:
        return f"**↳ Tool output** (`call_id={cid}…`) — _empty_\n\n"
    lang = "json" if body.lstrip().startswith(("{", "[")) else "text"
    if len(body) <= MAX_OUTPUT_INLINE:
        return f"**↳ Tool output** (`call_id={cid}…`)\n\n```{lang}\n{body.rstrip()}\n```\n\n"
    preview = body[:MAX_OUTPUT_INLINE]
    if len(body) <= 4000:
        # Medium-length: show full body inside <details>, plus preview inline for skimmers
        return (
            f"**↳ Tool output** (`call_id={cid}…`) — {len(body):,} chars\n\n"
            f"```{lang}\n{preview.rstrip()}\n```\n\n"
            f"<details><summary>Full output</summary>\n\n"
            f"```{lang}\n{body.rstrip()}\n```\n\n"
            f"</details>\n\n"
        )
    # Long: drop the body entirely from the doc; cite length only
    return (
        f"**↳ Tool output** (`call_id={cid}…`) — {len(body):,} chars (truncated, preview only)\n\n"
        f"```{lang}\n{preview.rstrip()}\n```\n\n"
        f"_(Output truncated; source: see codex session rollout jsonl `call_id={tc.get('call_id','')}`)_\n\n"
    )


def new_turn(ts, payload=None):
    payload = payload or {}
    return {
        "timestamp": ts,
        "turn_id": payload.get("turn_id", ""),
        "model": payload.get("model", "") or "?",
        "effort": payload.get("effort", ""),
        "personality": payload.get("personality", ""),
        "cwd": payload.get("cwd", ""),
        "sandbox": (payload.get("sandbox_policy", {}) or {}).get("type", ""),
        "items": [],
        "tool_call_buffers": {},
    }


def attach_tool_call_to_turn(turn: dict, tc: dict) -> None:
    """Append a tool call/output to the current assistant item in the turn.

    If the most recent item isn't an assistant message (or there's no
    assistant item yet), synthesise one with empty text so the renderer
    emits the call/output under an `🤖 **Assistant**` heading.
    """
    items = turn["items"]
    if items and items[-1]["role"] == "assistant" and not items[-1]["text"]:
        # Append to the in-flight empty assistant message
        items[-1]["tool_calls"].append(tc)
        return
    if items and items[-1]["role"] == "assistant":
        # Existing assistant message — append; allow text + tool calls to coexist
        items[-1]["tool_calls"].append(tc)
        return
    # No assistant item yet (e.g. custom_tool_call arrived before any message) —
    # synthesise one. Use the tool call timestamp.
    items.append({
        "role": "assistant",
        "ts": tc.get("ts", ""),
        "text": "",
        "tool_calls": [tc],
    })


# ---------- main ----------

def main():
    if len(sys.argv) != 3:
        print("usage: extract_codex_session.py <rollout.jsonl> <output.md>", file=sys.stderr)
        sys.exit(2)
    src = Path(sys.argv[1]).expanduser()
    out = Path(sys.argv[2]).expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)

    lines = []
    with src.open() as f:
        for ln in f:
            ln = ln.strip()
            if ln:
                lines.append(json.loads(ln))

    # ---- PASS 1: extract, drop noise ----
    session_meta = None
    compacted = []
    turns = []
    task_events_kept = []  # currently we drop all of these; reserved for future
    current_turn = None
    stats = Counter()
    skipped_reasoning_total = 0
    dropped_event_types = Counter()

    for rec in lines:
        t = rec.get("type")
        ts = rec.get("timestamp", "")
        payload = rec.get("payload", {}) or {}

        if t == "session_meta":
            session_meta = payload
            stats["session_meta"] += 1
            continue

        if t == "world_state":
            stats["world_state"] += 1  # dropped
            continue

        if t == "turn_context":
            current_turn = new_turn(ts, payload)
            turns.append(current_turn)
            stats["turn_context"] += 1
            continue

        if t == "event_msg":
            et = payload.get("type")
            # Drop ALL event_msg; turn metadata already covers task lifecycle
            dropped_event_types[et] += 1
            stats["event_msg_dropped"] += 1
            continue

        if t == "compacted":
            compacted.append({"timestamp": ts, "payload": payload})
            stats["compacted"] += 1
            continue

        if t == "inter_agent_communication_metadata":
            stats["inter_agent_communication_metadata"] += 1
            continue

        if t == "response_item":
            rtype = payload.get("type", "")
            if rtype == "message":
                role = payload.get("role", "?")
                content_list = payload.get("content", []) or []
                md_text, tool_calls, skipped_r = extract_message_text_and_calls(content_list)
                skipped_reasoning_total += skipped_r
                if current_turn is None:
                    current_turn = new_turn(ts, {})
                    turns.append(current_turn)
                # Skip empty developer messages from very first turn (system noise)
                if role == "developer" and not md_text.strip() and not tool_calls:
                    stats["empty_developer_dropped"] += 1
                    continue
                current_turn["items"].append({
                    "role": role, "ts": ts, "text": md_text, "tool_calls": tool_calls,
                })
                for tc in tool_calls:
                    if tc["kind"] == "call" and tc.get("call_id"):
                        current_turn["tool_call_buffers"][tc["call_id"]] = tc
                stats[f"message:{role}"] += 1
            elif rtype == "reasoning":
                # top-level reasoning record (not nested in a message)
                if is_encrypted_reasoning(payload):
                    skipped_reasoning_total += 1
                    stats["reasoning_dropped"] += 1
                    continue
                t_text = (payload.get("text") or "").strip()
                if not t_text and payload.get("summary"):
                    t_text = "\n".join(payload.get("summary") or [])
                if t_text and current_turn is not None:
                    current_turn["items"].append({
                        "role": "_reasoning_",
                        "ts": ts,
                        "text": f"> **Reasoning**\n>\n> {t_text.replace(chr(10), chr(10) + '> ')}\n\n",
                        "tool_calls": [],
                    })
                    stats["reasoning_kept"] += 1
            elif rtype == "function_call":
                if current_turn is None:
                    current_turn = new_turn(ts, {})
                    turns.append(current_turn)
                tc = {
                    "kind": "call",
                    "name": payload.get("name", ""),
                    "arguments": payload.get("arguments", ""),
                    "call_id": payload.get("call_id", ""),
                    "ts": ts,
                }
                current_turn["tool_call_buffers"][tc["call_id"]] = tc
                attach_tool_call_to_turn(current_turn, tc)
                stats["function_call"] += 1
            elif rtype == "function_call_output":
                if current_turn is None:
                    continue
                tc = {
                    "kind": "output",
                    "call_id": payload.get("call_id", ""),
                    "output": payload.get("output", ""),
                    "ts": ts,
                }
                current_turn["tool_call_buffers"][tc["call_id"]] = tc
                attach_tool_call_to_turn(current_turn, tc)
                stats["function_call_output"] += 1
            elif rtype == "custom_tool_call":
                # codex 0.144+ embeds tool calls in a JS shim:
                #   const r = await tools.<name>(<JSON args>);
                #   text(r.output);
                # Extract the JSON literal if present, for cleaner args display.
                raw_input = payload.get("input", "")
                args_str = extract_json_from_shim(raw_input)
                if current_turn is None:
                    current_turn = new_turn(ts, {})
                    turns.append(current_turn)
                tc = {
                    "kind": "call",
                    "name": payload.get("name", ""),
                    "arguments": args_str,
                    "call_id": payload.get("call_id", ""),
                    "ts": ts,
                }
                current_turn["tool_call_buffers"][tc["call_id"]] = tc
                # Attach to current assistant item so the renderer emits it
                attach_tool_call_to_turn(current_turn, tc)
                stats["custom_tool_call"] += 1
            elif rtype == "custom_tool_call_output":
                if current_turn is None:
                    continue
                tc = {
                    "kind": "output",
                    "call_id": payload.get("call_id", ""),
                    "output": payload.get("output", ""),
                    "ts": ts,
                }
                current_turn["tool_call_buffers"][tc["call_id"]] = tc
                attach_tool_call_to_turn(current_turn, tc)
                stats["custom_tool_call_output"] += 1
            else:
                if current_turn is not None and len(json.dumps(payload)) > 50:
                    current_turn["items"].append({
                        "role": f"_response_item:{rtype}_",
                        "ts": ts,
                        "text": "```json\n" + json.dumps(payload, default=str) + "\n```\n\n",
                        "tool_calls": [],
                    })
                    stats[f"unknown:{rtype}"] += 1
            continue

    # ---- PASS 2: render ----
    out_lines: list[str] = []

    sid = (session_meta or {}).get("session_id", "?")
    cli = (session_meta or {}).get("cli_version", "")
    originator = (session_meta or {}).get("originator", "")
    src_kind = (session_meta or {}).get("source", "")
    thread_source = (session_meta or {}).get("thread_source", "")
    started = ts_to_local((session_meta or {}).get("timestamp", ""))
    cwd = (session_meta or {}).get("cwd", "")
    git = (session_meta or {}).get("git", {}) or {}

    # ---- header ----
    out_lines.append(f"# Codex session `{sid}`\n\n")
    out_lines.append(f"- **Session ID**: `{sid}`\n")
    out_lines.append(f"- **Started**: {started}\n")
    out_lines.append(f"- **CLI**: codex {cli} ({originator})\n")
    out_lines.append(f"- **Source / Thread**: {src_kind} / {thread_source}\n")
    if cwd:
        out_lines.append(f"- **CWD**: `{cwd}`\n")
    if git:
        out_lines.append(f"- **Git**: `{git.get('branch','')}` @ `{git.get('commit_hash','')[:10]}` ({git.get('repository_url','')})\n")

    # turn metadata: count by model
    model_counts = Counter(t["model"] for t in turns)
    if model_counts:
        model_summary = ", ".join(f"{m}×{c}" for m, c in model_counts.most_common())
        out_lines.append(f"- **Models used**: {model_summary}\n")
    out_lines.append(f"- **Turns**: {len(turns)}\n")
    if compacted:
        out_lines.append(f"- **Compaction events**: {len(compacted)}\n")
    out_lines.append(f"- **Source records**: {len(lines)} ({', '.join(f'{k}={v}' for k,v in stats.most_common(10))})\n")
    out_lines.append(f"- **Dropped**: encrypted reasoning stubs × {skipped_reasoning_total}; event_msg × {sum(dropped_event_types.values())} ({dict(dropped_event_types)}) ; world_state / metadata\n")
    out_lines.append("\n---\n\n")

    # ---- TOC ----
    out_lines.append("## Table of contents\n\n")
    out_lines.append("- [Compaction summaries](#compaction-summaries)\n" if compacted else "")
    out_lines.append("- [Conversation turns](#conversation-turns)\n\n")
    out_lines.append("---\n\n")

    # ---- compaction summaries ----
    if compacted:
        out_lines.append("## Compaction summaries\n\n")
        for i, c in enumerate(compacted, 1):
            ts = ts_to_local(c["timestamp"])
            msg = c["payload"].get("message", "")
            out_lines.append(f"### Compaction #{i} — {ts}\n\n")
            # Compaction messages can be very long (contain the entire handoff).
            # Fold if >4k chars but show first 4k inline as preview.
            if len(msg) <= 4000:
                out_lines.append(msg.rstrip() + "\n\n")
            else:
                out_lines.append(msg[:4000].rstrip() + "\n\n")
                out_lines.append(f"<details><summary>Full compaction message ({len(msg):,} chars)</summary>\n\n")
                out_lines.append(msg.rstrip() + "\n\n</details>\n\n")
        out_lines.append("---\n\n")

    # ---- turns ----
    out_lines.append("## Conversation turns\n\n")
    if not turns:
        out_lines.append("_No turns recorded._\n\n")
    else:
        for idx, turn in enumerate(turns, 1):
            ts = ts_to_local(turn["timestamp"])
            model = turn.get("model") or "?"
            effort = turn.get("effort", "")
            personality = turn.get("personality", "")
            cwd_t = turn.get("cwd") or ""
            tid = (turn.get("turn_id") or "")[:8]

            extras = []
            if effort:
                extras.append(f"effort={effort}")
            if personality:
                extras.append(f"personality={personality}")
            model_label = f"{model}" + (f" ({', '.join(extras)})" if extras else "")

            out_lines.append(f"### Turn {idx} — {ts} · `{tid}` · {model_label}\n\n")
            if cwd_t and cwd_t != cwd:
                out_lines.append(f"- cwd: `{cwd_t}`\n")
            out_lines.append("\n")

            emitted = set()
            for it in turn["items"]:
                role = it["role"]
                if role.startswith("_response_item:"):
                    # only emit if it has interesting content
                    if len(it["text"].strip()) > 50:
                        out_lines.append(f"_{role}_\n\n")
                        out_lines.append(it["text"])
                    continue

                # role header
                head = {
                    "user": "👤 **User**",
                    "assistant": "🤖 **Assistant**",
                    "developer": "🛠️ **Developer**",
                    "system": "ℹ️ **System**",
                }.get(role, f"**{role.title()}**")
                out_lines.append(f"{head}\n\n")

                if it["text"]:
                    out_lines.append(it["text"])
                for tc in it["tool_calls"]:
                    if tc["kind"] == "call":
                        out_lines.append(render_tool_call(tc))
                        emitted.add(tc.get("call_id", ""))
                    elif tc["kind"] == "output":
                        out_lines.append(render_tool_output(tc))
                        emitted.add(tc.get("call_id", ""))

            # Standalone buffered calls (not attached to a message)
            for call_id, tc in turn["tool_call_buffers"].items():
                if call_id in emitted:
                    continue
                if tc["kind"] == "call":
                    out_lines.append(render_tool_call(tc))
                elif tc["kind"] == "output":
                    out_lines.append(render_tool_output(tc))

            out_lines.append("\n")

    out.write_text("".join(out_lines))

    final_size = out.stat().st_size
    print(f"OK wrote {out} ({final_size:,} bytes, {len(turns)} turns, source {len(lines):,} records)")
    print(f"   dropped: encrypted reasoning × {skipped_reasoning_total}; event_msg × {sum(dropped_event_types.values())}")


if __name__ == "__main__":
    main()