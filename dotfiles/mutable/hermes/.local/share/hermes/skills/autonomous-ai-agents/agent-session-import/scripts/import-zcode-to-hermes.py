#!/usr/bin/env python3
"""
zcode → hermes importer

Reads the zcode SQLite store at ``~/.zcode/cli/db/db.sqlite`` and writes
the selected session(s) into the hermes SQLite session store
(``state.db``) via ``SessionDB``, so they show up in
``hermes sessions list`` and can be resumed with
``hermes chat --resume <id>``.

Usage:
  # dry-run on one session (prints the row-plan, no writes)
  ./import-zcode-to-hermes.py --dry-run sess_6a94a941-...

  # import one session
  ./import-zcode-to-hermes.py sess_6a94a941-...

  # import every parent (non-subagent) session, skipping ones that
  # already exist in hermes (idempotent)
  ./import-zcode-to-hermes.py --all-parents

  # list candidate sessions
  ./import-zcode-to-hermes.py --list
"""
import argparse
import json
import os
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ZCODE_DB = Path.home() / ".zcode" / "cli" / "db" / "db.sqlite"
SOURCE_TAG = "imported-zcode"
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
    # Nix: pick the venv whose hermes_state reports our home
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
                 f"from hermes_constants import get_hermes_home; "
                 f"print(get_hermes_home())"],
                capture_output=True, text=True, timeout=10,
            )
            if out.returncode == 0 and out.stdout.strip() == target_home:
                return c
        except Exception:
            continue
    return candidates[0] if candidates else ""


# ---------------------------------------------------------------------------
# timestamp / json helpers
# ---------------------------------------------------------------------------

def _ms_to_s(v):
    """zcode stores every time field as ms since epoch; hermes uses seconds."""
    if v is None:
        return None
    if isinstance(v, str):
        try:
            v = int(v)
        except ValueError:
            return None
    if not isinstance(v, (int, float)):
        return None
    return float(v) / 1000.0 if v > 1e12 else float(v)


def _safe_json_loads(s):
    if not s:
        return {}
    try:
        return json.loads(s)
    except (TypeError, ValueError):
        return {}


# ---------------------------------------------------------------------------
# zcode reader
# ---------------------------------------------------------------------------

def fetch_session_row(zdb, session_id):
    return zdb.execute(
        "SELECT id, title, directory, parent_id, task_type, "
        "time_created, time_updated, time_archived "
        "FROM session WHERE id = ?", (session_id,),
    ).fetchone()


def fetch_messages(zdb, session_id):
    """Return messages in time order, each row as sqlite3.Row."""
    cur = zdb.execute(
        "SELECT id, time_created, data FROM message "
        "WHERE session_id = ? ORDER BY time_created, id", (session_id,),
    )
    return cur.fetchall()


def fetch_parts_for(zdb, message_id):
    """Return parts in time order (use part.id as secondary sort)."""
    cur = zdb.execute(
        "SELECT id, time_created, data FROM part "
        "WHERE message_id = ? "
        "ORDER BY time_created, id", (message_id,),
    )
    return cur.fetchall()


# ---------------------------------------------------------------------------
# message → hermes writer
# ---------------------------------------------------------------------------

# Synthetic user text (auto-injected system reminders) is collapsed to a
# short prefix marker instead of being inlined into the conversation.
SYNTHETIC_FOLD_PREFIX = "[system-reminder]"


def build_assistant_payload(parts):
    """
    Turn a list of zcode part rows for one assistant message into a
    (text, reasoning_content, tool_calls) triple, matching the
    hermes SessionDB.append_message signature.

    zcode's assistant turn always looks like:
        step-start, [reasoning]?, [text]?, tool* , step-finish
    We skip the step-* boundary markers (hermes has no analogue) and
    merge text+reasoning; tool calls become OpenAI-style tool_calls
    on the assistant message plus a paired tool message per result.
    """
    text_chunks = []
    reasoning_chunks = []
    tool_calls = []  # list of {"id","type":"function","function":{"name","arguments"}}

    for p in parts:
        d = _safe_json_loads(p["data"])
        ptype = d.get("type")
        if ptype == "text":
            t = d.get("text") or ""
            if t:
                text_chunks.append(t)
        elif ptype == "reasoning":
            t = d.get("text") or ""
            if t:
                reasoning_chunks.append(t)
        elif ptype == "tool":
            call_id = d.get("callID") or ""
            name = d.get("tool") or "unknown"
            state = d.get("state") or {}
            inp = state.get("input")
            # OpenAI tool_calls.arguments is a JSON STRING, not a dict.
            if isinstance(inp, str):
                args_str = inp
            else:
                args_str = json.dumps(inp, ensure_ascii=False) if inp is not None else "{}"
            tool_calls.append({
                "id": call_id,
                "type": "function",
                "function": {"name": name, "arguments": args_str},
            })
        # step-start / step-finish / compaction → ignored here

    text = "\n\n".join(text_chunks) if text_chunks else ""
    reasoning = "\n\n".join(reasoning_chunks) if reasoning_chunks else None
    return text, reasoning, tool_calls


def build_user_payload(parts):
    """
    Combine user-side parts into a single content string.
    - Regular text → kept as-is
    - text with synthetic:true → folded to a short marker so the
      conversation stays readable (synthetic text is mostly TodoWrite
      nudges and skill hints)
    - file attachments → represented as a one-line stub (the URL is
      zcode-artifact://, not a real http URL, so we just note the
      filename to keep the LLM on resume from trying to fetch)
    """
    pieces = []
    for p in parts:
        d = _safe_json_loads(p["data"])
        ptype = d.get("type")
        if ptype == "text":
            t = d.get("text") or ""
            if d.get("synthetic"):
                head = t.splitlines()[0][:120] if t else ""
                pieces.append(f"{SYNTHETIC_FOLD_PREFIX} {head}".rstrip())
            elif t:
                pieces.append(t)
        elif ptype == "file":
            fn = d.get("filename") or "(file)"
            pieces.append(f"[attachment: {fn}]")
        # compaction / tool / etc → skipped for user messages
    return "\n\n".join(pieces)


# ---------------------------------------------------------------------------
# conversion (one zcode session → list of (role, kwargs) tuples)
# ---------------------------------------------------------------------------

def convert_session(zdb, session_id, *, time_floor):
    """
    Walk a single zcode session and yield kwargs dicts ready to hand
    to SessionDB.append_message. Time-floor is the strict-monotonicity
    guard: every emitted timestamp is at least 1 ms greater than the
    last one we wrote.
    """
    out = []
    last_ts = time_floor
    messages = fetch_messages(zdb, session_id)
    for m in messages:
        md = _safe_json_loads(m["data"])
        role = md.get("role")
        if role not in ("user", "assistant"):
            continue
        parts = fetch_parts_for(zdb, m["id"])

        # Strict monotonicity: max(prev + 1ms, parsed).
        parsed = _ms_to_s(m["time_created"]) or last_ts
        ts = max(last_ts + 0.001, parsed)

        if role == "user":
            content = build_user_payload(parts)
            kw = {
                "role": "user",
                "content": content,
                "timestamp": ts,
            }
        else:  # assistant
            text, reasoning, tool_calls = build_assistant_payload(parts)
            # assistant with no text and no tool calls (e.g. only
            # step-start / step-finish) — still emit "" not None so
            # OpenAI consumers don't trip on missing content.
            kw = {
                "role": "assistant",
                "content": text if text else "",
                "tool_calls": tool_calls or None,
                "reasoning_content": reasoning,
                "timestamp": ts,
            }
            # The finish reason is on the step-finish part; pull the
            # last one we see for this turn.
            finish = md.get("finish")
            if finish:
                kw["finish_reason"] = finish
        out.append((kw, parts))
        last_ts = ts
    return out


# ---------------------------------------------------------------------------
# tool result emission — a "tool" hermes row per part.type=tool
# ---------------------------------------------------------------------------

def emit_tool_results(db, session_id, parts, base_ts):
    """
    For every tool part in an assistant turn, write one hermes "tool"
    row paired with the assistant tool_call. The base_ts advances by
    1ms per emitted row so ordering stays monotonic.
    """
    ts = base_ts
    for p in parts:
        d = _safe_json_loads(p["data"])
        if d.get("type") != "tool":
            continue
        call_id = d.get("callID") or ""
        name = d.get("tool") or "unknown"
        state = d.get("state") or {}
        output = state.get("output") or ""
        status = state.get("status") or ""
        # Truncate extremely long outputs to keep state.db from
        # ballooning; a 50KB cap is well above what the LLM needs
        # on resume.
        if isinstance(output, str) and len(output) > 50_000:
            output = output[:50_000] + "\n\n[... truncated by importer ...]"
        content = output if output else f"(no output; status={status})"
        ts = max(ts + 0.001, _ms_to_s(state.get("time", {}).get("end")) or ts)
        db.append_message(
            session_id=session_id,
            role="tool",
            content=content,
            tool_name=name,
            tool_call_id=call_id,
            timestamp=ts,
        )


# ---------------------------------------------------------------------------
# top-level import
# ---------------------------------------------------------------------------

def import_one(zdb, db, session_id, *, dry_run=False):
    srow = fetch_session_row(zdb, session_id)
    if not srow:
        print(f"  ✗ session {session_id} not found in zcode db", file=sys.stderr)
        return False

    if db is not None and db.get_session(session_id):
        print(f"  · {session_id[:32]}  already in hermes — skipping (idempotent)")
        return True

    title = srow["title"] or session_id
    directory = srow["directory"] or None
    parent_id = srow["parent_id"] or None

    # Best-effort model metadata: read the first message that has a
    # model field, default to GLM-5.2 (matches the only provider we
    # observed in db.sqlite).
    model = None
    provider = None
    for m in fetch_messages(zdb, session_id):
        md = _safe_json_loads(m["data"])
        if md.get("modelID"):
            model = md["modelID"]
            provider = md.get("providerID")
            break
        if isinstance(md.get("model"), dict) and md["model"].get("modelID"):
            model = md["model"]["modelID"]
            provider = md["model"].get("providerID")
            break

    if dry_run:
        n_msg = zdb.execute(
            "SELECT COUNT(*) FROM message WHERE session_id=?", (session_id,)
        ).fetchone()[0]
        n_tool = zdb.execute(
            "SELECT COUNT(*) FROM part p JOIN message m ON p.message_id=m.id "
            "WHERE m.session_id=? AND json_extract(p.data,'$.type')='tool'",
            (session_id,),
        ).fetchone()[0]
        print(f"  [dry-run] {session_id}")
        print(f"    title    : {title!r}")
        print(f"    directory: {directory}")
        print(f"    parent   : {parent_id or '-'}")
        print(f"    model    : {model} (provider={provider})")
        print(f"    messages : {n_msg}  tool parts: {n_tool}")
        return True

    db.create_session(
        session_id=session_id,
        source=SOURCE_TAG,
        model=model,
        model_config={"provider": provider} if provider else None,
        cwd=directory,
        parent_session_id=parent_id,
    )

    # backfill session-level time + title (create_session stamps time.time())
    started = _ms_to_s(srow["time_created"])
    ended = _ms_to_s(srow["time_updated"]) or started
    # SessionDB is the same library used elsewhere; raw SQL on its
    # private _conn is the documented escape hatch in agent-session-import.
    db._execute_write(lambda c: c.execute(
        "UPDATE sessions SET started_at=?, ended_at=?, title=?, end_reason=? "
        "WHERE id=?",
        (started, ended, title[:120], f"imported-{SOURCE_TAG}", session_id),
    ))

    # Walk messages; for each assistant turn, emit assistant row
    # followed by one "tool" row per part.type=tool.
    time_floor = started
    for kw, parts in convert_session(zdb, session_id, time_floor=time_floor):
        db.append_message(session_id=session_id, **kw)
        if kw["role"] == "assistant" and kw.get("tool_calls"):
            emit_tool_results(db, session_id, parts, kw["timestamp"])

    # start_reason-style: we already set end_reason in the raw UPDATE
    # above, so call end_session with a no-op reason that won't clobber.
    # (end_session refuses to overwrite an existing ended_at.)
    if db.get_session(session_id).get("ended_at") is None:
        db.end_session(session_id, end_reason=f"imported-{SOURCE_TAG}")
    n = db._conn.execute(
        "SELECT COUNT(*) FROM messages WHERE session_id=?", (session_id,)
    ).fetchone()[0]
    print(f"  ✓ {session_id[:32]}  {title[:40]!r}  ({n} hermes rows)")
    return True


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def list_sessions(zdb):
    cur = zdb.execute(
        "SELECT id, title, task_type, "
        "(SELECT COUNT(*) FROM message WHERE session_id=session.id) AS msgs, "
        "time_created "
        "FROM session ORDER BY time_created"
    )
    rows = cur.fetchall()
    for r in rows:
        when = _ms_to_s(r["time_created"])
        when_iso = datetime.fromtimestamp(when, tz=timezone.utc).strftime("%Y-%m-%d %H:%M") if when else "?"
        marker = "  " if r["task_type"] == "interactive" else "S "
        print(f"{marker}{r['id'][:36]:36}  msgs={r['msgs']:>4}  {when_iso}  {r['title'][:50]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session_id", nargs="?", help="zcode session id to import (with or without sess_ prefix)")
    ap.add_argument("--all-parents", action="store_true",
                    help="import every session whose task_type='interactive' (skip subagents)")
    ap.add_argument("--list", action="store_true", help="list candidate sessions and exit")
    ap.add_argument("--dry-run", action="store_true", help="print the plan, write nothing")
    args = ap.parse_args()

    if not ZCODE_DB.exists():
        sys.exit(f"zcode db not found at {ZCODE_DB}")

    # The user-python can't import hermes_state — re-exec under the
    # nix-store venv to get SessionDB. Skip for --list / --dry-run
    # (we never touch hermes in those modes).
    if not (args.list or args.dry_run):
        if "/nix/store/" not in sys.executable:
            py = _resolve_hermes_py()
            if not py:
                sys.exit(
                    "hermes python not found. Set $HERMES_AGENT_PY to the "
                    "nix-store hermes-agent-env venv, or install the "
                    "hermes-agent package."
                )
            os.environ["HERMES_AGENT_PY"] = py
            os.execvp(py, [py, str(Path(__file__).resolve())] + sys.argv[1:])

    zdb = sqlite3.connect(str(ZCODE_DB))
    zdb.row_factory = sqlite3.Row

    if args.list:
        list_sessions(zdb)
        return 0

    # --all-parents --dry-run: still no hermes needed.
    if args.all_parents and args.dry_run:
        cur = zdb.execute(
            "SELECT id, title, "
            "(SELECT COUNT(*) FROM message WHERE session_id=session.id) AS msgs "
            "FROM session WHERE task_type='interactive' "
            "ORDER BY time_created"
        )
        for r in cur.fetchall():
            print(f"  [dry-run] {r['id'][:36]:36}  msgs={r['msgs']:>4}  {r['title'][:50]}")
        return 0

    if args.all_parents:
        from hermes_state import SessionDB
        db = SessionDB()
        cur = zdb.execute(
            "SELECT id FROM session WHERE task_type='interactive' "
            "ORDER BY time_created"
        )
        ids = [r["id"] for r in cur.fetchall()]
        ok = 0
        for sid in ids:
            if import_one(zdb, db, sid, dry_run=args.dry_run):
                ok += 1
        print(f"\n{'[dry-run] would import' if args.dry_run else 'imported'}: {ok}/{len(ids)}")
        return 0

    if not args.session_id:
        ap.error("provide a session id, or --all-parents, or --list")

    sid = args.session_id
    if not sid.startswith("sess_"):
        sid = "sess_" + sid

    if args.dry_run:
        # dry-run only reads the zcode db; no need to import hermes_state.
        ok = import_one(zdb, None, sid, dry_run=True)
        return 0 if ok else 1

    # from here we will write to hermes — lazy import after dry-run
    # short-circuit so user-python dry-runs don't need hermes_state.
    from hermes_state import SessionDB
    db = SessionDB()
    ok = import_one(zdb, db, sid, dry_run=False)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main() or 0)
