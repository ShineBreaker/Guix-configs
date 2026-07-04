#!/usr/bin/env python3
"""
pi → hermes importer

Reads ~/.local/share/pi/sessions/*.jsonl and writes them into the
hermes SQLite session store (state.db) via SessionDB, so they show
up in `hermes sessions list` and can be resumed with
`hermes --resume <id>`.

Usage:
  # dry-run on a single file (prints plan, no writes)
  ./import-to-hermes.py --dry-run <file.jsonl>

  # import one session
  ./import-to-hermes.py <file.jsonl>

  # import all 245 sessions
  ./import-to-hermes.py --all
"""
import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

PI_DIR = Path.home() / ".local" / "share" / "pi" / "sessions"
SOURCE_TAG = "imported-pi"

# Path to the nix-store hermes python on this host. Sharing its lib lets
# us reuse the running daemon's SessionDB / HermesState code so schema
# and locks are guaranteed identical.
HERMES_PY = os.environ.get(
    "HERMES_AGENT_PY",
    # Auto-discover the nix-store hermes-agent-env venv. The user
    # python can't import hermes_state; we re-exec under the venv.
    # Override with $HERMES_AGENT_PY if your install lives elsewhere
    # (Guix, plain pip, …).
    "",  # resolved at runtime by _resolve_hermes_py()
)


def _resolve_hermes_py():
    """Find /nix/store/*-hermes-agent-env/bin/python3 with the user's
    $HERMES_HOME. Set $HERMES_AGENT_PY to override."""
    import glob
    if HERMES_PY and Path(HERMES_PY).exists():
        return HERMES_PY
    try:
        from hermes_constants import get_hermes_home
        target_home = str(get_hermes_home())
    except Exception:
        target_home = str(Path.home() / ".local" / "share" / "hermes")
    candidates = sorted(glob.glob("/nix/store/*-hermes-agent-env/bin/python3"))
    for c in candidates:
        try:
            out = subprocess.run(
                [c, "-c",
                 "from hermes_constants import get_hermes_home; "
                 "print(get_hermes_home())"],
                capture_output=True, text=True, timeout=10,
            )
            if out.returncode == 0 and out.stdout.strip() == target_home:
                return c
        except Exception:
            continue
    return candidates[0] if candidates else ""


def _parse_ts(v):
    """
    pi jsonl timestamps are ISO-8601 strings (with trailing 'Z');
    coerce to a UTC unix timestamp (seconds). Falls back to None on
    unparseable input — caller can use a previous seen value.
    """
    if v is None:
        return None
    if isinstance(v, (int, float)):
        # Heuristic: > 1e12 means milliseconds.
        return float(v) / 1000.0 if v > 1e12 else float(v)
    if isinstance(v, str):
        s = v.strip()
        if not s:
            return None
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        try:
            dt = datetime.fromisoformat(s)
        except ValueError:
            return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()
    raise TypeError(f"unsupported timestamp type: {type(v).__name__}")


def load_pi_session(path: Path):
    """Return (header, events_list) parsed from a pi jsonl session file."""
    events = []
    header = None
    with path.open() as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            e = json.loads(line)
            if e.get("type") == "session" and header is None:
                header = e
            events.append(e)
    if header is None:
        raise ValueError(f"no session header in {path}")
    return header, events


def derive_title(first_user_text: str, fallback: str) -> str:
    if first_user_text:
        t = first_user_text.replace("\n", " ").strip()
        return t[:60] + ("…" if len(t) > 60 else "")
    return fallback


def _split_user_content(content):
    if isinstance(content, str):
        return [content], []
    text = []
    images = []
    for blk in content or []:
        btype = blk.get("type")
        if btype == "text":
            text.append(blk.get("text", ""))
        elif btype == "image":
            images.append(blk)
    return text, images


def _split_assistant_content(content):
    if isinstance(content, str):
        return [content], [], None, []
    text = []
    thinking = []
    tool_calls = []
    images = []
    for blk in content or []:
        btype = blk.get("type")
        if btype == "text":
            text.append(blk.get("text", ""))
        elif btype == "thinking":
            thinking.append(blk.get("thinking", ""))
        elif btype == "toolCall":
            # pi toolCall → OpenAI-style tool_call dict
            tool_calls.append({
                "id": blk.get("id"),
                "type": "function",
                "function": {
                    "name": blk.get("name"),
                    "arguments": json.dumps(blk.get("arguments", {}), ensure_ascii=False),
                },
            })
        elif btype == "image":
            images.append(blk)
    return text, thinking, tool_calls, images


def _flatten_text(content):
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    parts = []
    for blk in content or []:
        if blk.get("type") == "text":
            parts.append(blk.get("text", ""))
        else:
            parts.append(json.dumps(blk, ensure_ascii=False))
    return "\n".join(parts)


def _content_for_hermes(text_parts, image_parts):
    """
    scalar str for plain text, list-of-parts for mixed/attachments.
    Empty string (not None) for assistant turns with only thinking/
    tool_calls so OpenAI-protocol consumers don't see a missing content.
    """
    if image_parts:
        parts = [{"type": "text", "text": p} for p in text_parts if p]
        parts.extend(image_parts)
        return parts
    joined = "\n".join(p for p in text_parts if p)
    return joined if joined is not None else ""


def convert(pi_id: str, header: dict, events: list):
    """
    Translate pi events → list of message dicts ready for
    SessionDB.append_message. Skips metadata events (thinking_level_change,
    custom, custom_message, compaction) — they carry no conversation content.

    pi sometimes splits one logical assistant turn into several adjacent
    message events (e.g. a thinking-only stub followed by a toolCall
    message). We coalesce consecutive assistant events into a single
    hermes assistant message so the round-trip preserves turn ordering
    (thinking → tool_call(s) → text) inside one row.
    """
    cwd = header.get("cwd")
    started_at = _parse_ts(header.get("timestamp")) or time.time()

    first_user_text = None
    model = None
    provider = None
    msgs = []
    last_ts = started_at

    # Accumulator for the current open assistant run.
    a_text = []
    a_thinking = []
    a_tool_calls = []
    a_images = []
    a_ts = None
    a_finish = None
    a_token = None

    def _flush_assistant():
        nonlocal a_text, a_thinking, a_tool_calls, a_images, a_ts, a_finish, a_token
        if a_ts is None:
            return
        msgs.append({
            "role": "assistant",
            "content": _content_for_hermes(a_text, a_images),
            "reasoning_content": "\n\n".join(a_thinking) if a_thinking else None,
            "tool_calls": a_tool_calls or None,
            "timestamp": a_ts,
            "token_count": a_token,
            "finish_reason": a_finish,
        })
        a_text, a_thinking, a_tool_calls, a_images = [], [], [], []
        a_ts = a_finish = a_token = None

    for ev in events:
        t = ev.get("type")
        ts = _parse_ts(ev.get("timestamp")) or last_ts
        # Monotonic guard — keep ts strictly non-decreasing for sqlite ordering.
        if ts < last_ts:
            ts = last_ts + 1e-3
        last_ts = ts

        if t != "message":
            if t == "model_change":
                model = ev.get("model") or model
                provider = ev.get("provider") or provider
            continue

        m = ev.get("message") or {}
        role = m.get("role")
        content = m.get("content")
        usage = m.get("usage") or {}
        stop = m.get("stopReason")

        if role == "user":
            _flush_assistant()
            text_parts, image_parts = _split_user_content(content)
            if not first_user_text and text_parts:
                first_user_text = "".join(text_parts)
            msgs.append({
                "role": "user",
                "content": _content_for_hermes(text_parts, image_parts),
                "timestamp": ts,
                "token_count": usage.get("input") if usage else None,
                "finish_reason": stop,
            })

        elif role == "assistant":
            text_parts, thinking_parts, tool_calls, image_parts = _split_assistant_content(content)
            if a_ts is None:
                a_ts = ts
            a_text.extend(text_parts)
            a_thinking.extend(thinking_parts)
            a_tool_calls.extend(tool_calls or [])
            a_images.extend(image_parts)
            if stop:
                a_finish = stop
            if usage.get("output") is not None:
                a_token = usage["output"]
            if m.get("model"):
                model = m["model"]
            if m.get("provider"):
                provider = m["provider"]

        elif role == "toolResult":
            _flush_assistant()
            msgs.append({
                "role": "tool",
                "content": _flatten_text(content),
                "tool_call_id": m.get("toolCallId"),
                "tool_name": m.get("toolName"),
                "timestamp": ts,
            })

        elif role == "bashExecution":
            _flush_assistant()
            msgs.append({
                "role": "tool",
                "content": _flatten_text(content),
                "tool_name": "bashExecution",
                "timestamp": ts,
            })

        # anything else: skip

    _flush_assistant()

    title = derive_title(first_user_text, pi_id)
    model_config = {"model": model, "provider": provider} if model else None
    return title, model, model_config, started_at, last_ts, cwd, msgs


def import_one(path: Path, dry_run: bool = False, db=None):
    header, events = load_pi_session(path)
    pi_id = header["id"]
    title, model, model_config, started_at, last_ts, cwd, msgs = convert(pi_id, header, events)
    info = {
        "file": path.name,
        "pi_id": pi_id,
        "title": title,
        "model": model,
        "cwd": cwd,
        "started_at": started_at,
        "ended_at": last_ts,
        "n_messages": len(msgs),
        "n_tool_calls": sum(1 for m in msgs if m.get("tool_calls")),
    }
    if dry_run:
        return info

    from hermes_state import SessionDB  # imported only when writing
    db = db or SessionDB()

    # Idempotency guard — skip if this session was already imported.
    existing = db.get_session(pi_id)
    if existing is not None:
        info["skipped"] = True
        info["reason"] = f"session {pi_id} already in store (source={existing.get('source')})"
        return info

    db.create_session(
        session_id=pi_id,
        source=SOURCE_TAG,
        model=model,
        model_config=model_config,
        cwd=cwd,
    )
    # create_session doesn't accept started_at — back-fill from header.
    db._conn.execute(
        "UPDATE sessions SET started_at=? WHERE id=?",
        (started_at, pi_id),
    )

    for m in msgs:
        db.append_message(
            session_id=pi_id,
            role=m["role"],
            content=m.get("content"),
            tool_call_id=m.get("tool_call_id"),
            tool_calls=m.get("tool_calls"),
            tool_name=m.get("tool_name"),
            timestamp=m["timestamp"],
            token_count=m.get("token_count"),
            finish_reason=m.get("finish_reason"),
            reasoning_content=m.get("reasoning_content"),
            observed=False,
        )

    db.end_session(pi_id, end_reason="imported-pi")
    # Restore ended_at to the last-message timestamp (end_session uses now()).
    db._conn.execute(
        "UPDATE sessions SET ended_at=?, title=? WHERE id=?",
        (last_ts, title, pi_id),
    )
    db._conn.commit()
    return info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", help="pi session .jsonl files")
    ap.add_argument("--all", action="store_true", help="import all of ~/.local/share/pi/sessions/*.jsonl")
    ap.add_argument("--dry-run", action="store_true", help="parse and report, no writes")
    args = ap.parse_args()

    files = []
    if args.all:
        files = sorted(PI_DIR.glob("*.jsonl"))
    else:
        files = [Path(f) for f in args.files]

    if not files:
        ap.error("no files given; pass paths or --all")

    # Re-exec under the nix-store hermes python so SessionDB imports work
    # (hermes ships its own venv; the user python may not have the module).
    if not args.dry_run and "/nix/store/" not in sys.executable:
        py = _resolve_hermes_py()
        if not py:
            print(
                "hermes python not found. Set $HERMES_AGENT_PY to the "
                "nix-store hermes-agent-env venv, or install hermes-agent.",
                file=sys.stderr,
            )
            sys.exit(2)
        os.environ["HERMES_AGENT_PY"] = py
        cmd = [py, str(Path(__file__).resolve())] + sys.argv[1:]
        sys.exit(subprocess.call(cmd))

    if args.dry_run:
        for f in files:
            try:
                info = import_one(f, dry_run=True)
                print(json.dumps(info, ensure_ascii=False))
            except Exception as exc:
                print(json.dumps({"file": str(f), "error": str(exc)}))
        return

    from hermes_state import SessionDB  # under hermes python now
    db = SessionDB()
    ok = err = 0
    for f in files:
        try:
            info = import_one(f, dry_run=False, db=db)
            ok += 1
            print(f"  ✓ {f.name[:40]:40s} {info['n_messages']:5d} msgs / {info['n_tool_calls']:4d} tools  →  {info['title'][:40]}")
        except Exception as exc:
            err += 1
            print(f"  ✗ {f.name}: {exc}", file=sys.stderr)
    print(f"\ndone: {ok} ok, {err} failed")


if __name__ == "__main__":
    main()