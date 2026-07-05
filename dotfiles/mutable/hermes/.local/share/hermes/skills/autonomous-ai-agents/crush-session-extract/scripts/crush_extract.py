#!/usr/bin/env python3
"""
crush session extractor.

Reads a crush project-level SQLite DB (./.crush/crush.db), validates the time
unit (the schema comment says "ms" but the column actually stores seconds),
extracts sessions within a time window to either JSON or a readable Markdown
transcript, and runs a sanity check that message counts match.

Usage:
    crush_extract.py list [--db PATH] [--since YYYY-MM-DD] [--until YYYY-MM-DD]
    crush_extract.py show  --session ID [--db PATH]
    crush_extract.py dump  --session ID --format {md,json} [--out FILE] [--db PATH]
    crush_extract.py verify [--db PATH]    # hot-backup + row count check
    crush_extract.py find  [--root PATH]   # find all .crush/crush.db under root

Conventions:
- Crush stores DB at <project>/.crush/crush.db (per-project), NOT at
  ~/.crush/. The global ~/.config/crush/.crush/crush.db is only a migration
  header and has no sessions.
- Time columns (created_at / updated_at / finished_at) are UNIX SECONDS even
  though the schema comment says "milliseconds". This script auto-verifies
  and warns if values look like ms.
- `messages.parts` is a JSON TEXT array of {type, data} objects; we use
  `json_each` instead of slicing.
- Subagent sessions link via `sessions.parent_session_id` (not via parts).

Stdlib only.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

SCHEMA_TIME_HINT = "schema comment says ms but actual column is seconds"


# ---------------------------------------------------------------------------
# discovery
# ---------------------------------------------------------------------------

def find_crush_dbs(root: Path) -> list[Path]:
    """Walk root for .crush/crush.db files. Skips Trash and dotfile backup."""
    results: list[Path] = []
    root = root.expanduser().resolve()
    for path in root.rglob(".crush/crush.db"):
        # skip trash / backup copies
        if "/Trash/" in str(path) or ".bak" in path.name:
            continue
        results.append(path)
    return sorted(results, key=lambda p: p.stat().st_mtime, reverse=True)


def open_db(path: Path) -> sqlite3.Connection:
    if not path.exists():
        sys.exit(f"db not found: {path}")
    # journal_mode=WAL by default; force read-only-ish for safety
    uri = f"file:{path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def verify_time_unit(conn: sqlite3.Connection) -> str:
    """Crush's schema comment says ms; the actual column stores seconds.
    Heuristic: any session with created_at within [2024-01-01, now+1d] seconds.
    Returns 'seconds' or 'milliseconds'."""
    now_s = int(time.time())
    now_ms = now_s * 1000
    threshold_s = 1704067200  # 2024-01-01 UTC
    row = conn.execute(
        "SELECT MIN(created_at) AS mn, MAX(created_at) AS mx FROM sessions"
    ).fetchone()
    if row["mn"] is None:
        return "seconds"  # empty, default
    if threshold_s <= row["mn"] <= now_s + 86400:
        return "seconds"
    if threshold_s * 1000 <= row["mn"] <= now_ms + 86400_000:
        return "milliseconds"
    return "unknown"


def to_iso(ts: float, unit: str) -> str:
    if unit == "milliseconds":
        ts = ts / 1000.0
    return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# queries
# ---------------------------------------------------------------------------

def list_sessions(
    conn: sqlite3.Connection,
    since: str | None = None,
    until: str | None = None,
    unit: str = "seconds",
) -> list[dict[str, Any]]:
    where: list[str] = []
    params: list[Any] = []
    if since:
        where.append("created_at >= ?")
        params.append(parse_date(since, unit))
    if until:
        where.append("created_at <= ?")
        params.append(parse_date_end(until, unit))
    sql = "SELECT * FROM sessions"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY created_at DESC"
    rows = conn.execute(sql, params).fetchall()
    return [row_to_session(dict(r), unit) for r in rows]


def parse_date(s: str, unit: str) -> int:
    # accept YYYY-MM-DD or full ISO
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        sys.exit(f"bad date: {s}")
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    ts = int(dt.timestamp())
    return ts * 1000 if unit == "milliseconds" else ts


def parse_date_end(s: str, unit: str) -> int:
    # inclusive end-of-day
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        sys.exit(f"bad date: {s}")
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    # if user gave YYYY-MM-DD, push to end of day
    if len(s) == 10:
        dt = dt.replace(hour=23, minute=59, second=59)
    ts = int(dt.timestamp())
    return ts * 1000 if unit == "milliseconds" else ts


def row_to_session(row: dict[str, Any], unit: str) -> dict[str, Any]:
    row["created_at_iso"] = to_iso(row["created_at"], unit)
    row["updated_at_iso"] = to_iso(row["updated_at"], unit)
    return row


def fetch_messages(
    conn: sqlite3.Connection, session_id: str
) -> list[dict[str, Any]]:
    rows = conn.execute(
        "SELECT * FROM messages WHERE session_id = ? ORDER BY created_at ASC",
        (session_id,),
    ).fetchall()
    out = []
    for r in rows:
        d = dict(r)
        try:
            d["parts"] = json.loads(d["parts"])
        except (TypeError, json.JSONDecodeError):
            d["parts"] = []
        out.append(d)
    return out


def fetch_session(conn: sqlite3.Connection, session_id: str) -> dict[str, Any] | None:
    row = conn.execute(
        "SELECT * FROM sessions WHERE id = ?", (session_id,)
    ).fetchone()
    if not row:
        return None
    return dict(row)


# ---------------------------------------------------------------------------
# rendering
# ---------------------------------------------------------------------------

def render_markdown(
    session: dict[str, Any], messages: list[dict[str, Any]], unit: str
) -> str:
    title = session.get("title") or "(untitled)"
    sid = session.get("id")
    created = session.get("created_at_iso", "?")
    n_msgs = len(messages)
    cost = session.get("cost", 0.0)
    prompt_t = session.get("prompt_tokens", 0)
    comp_t = session.get("completion_tokens", 0)

    lines: list[str] = [
        f"# {title}",
        "",
        f"- session_id: `{sid}`",
        f"- created: {created}",
        f"- messages: {n_msgs}",
        f"- tokens: prompt={prompt_t} completion={comp_t}",
        f"- cost: ${cost:.4f}",
        "",
        "---",
        "",
    ]

    for idx, msg in enumerate(messages, 1):
        role = msg.get("role", "?")
        ts = msg.get("created_at")
        ts_iso = to_iso(ts, unit) if ts else "?"
        lines.append(f"## [{idx}] {role}  ({ts_iso})")
        lines.append("")
        for part in msg.get("parts") or []:
            ptype = part.get("type")
            data = part.get("data") or {}
            if ptype == "text":
                lines.append(data.get("text", ""))
                lines.append("")
            elif ptype == "reasoning":
                thinking = data.get("thinking") or ""
                if thinking:
                    lines.append("> **reasoning:**")
                    lines.append(">")
                    for ln in thinking.splitlines():
                        lines.append("> " + ln)
                    lines.append("")
            elif ptype == "tool_call":
                name = data.get("name", "?")
                call_id = data.get("id", "?")
                inp = data.get("input", "")
                if isinstance(inp, str):
                    try:
                        inp = json.loads(inp)
                    except json.JSONDecodeError:
                        pass
                lines.append(f"**→ tool_call `{name}`**  (id=`{call_id}`)")
                lines.append("")
                lines.append("```json")
                lines.append(json.dumps(inp, indent=2, ensure_ascii=False))
                lines.append("```")
                lines.append("")
            elif ptype == "tool_result":
                name = data.get("name", "?")
                call_id = data.get("tool_call_id", "?")
                content = data.get("content", "")
                lines.append(f"**← tool_result `{name}`**  (call_id=`{call_id}`)")
                lines.append("")
                if len(content) > 4000:
                    content = content[:4000] + f"\n... [truncated {len(content)-4000} chars]"
                lines.append("```")
                lines.append(content)
                lines.append("```")
                lines.append("")
            elif ptype == "finish":
                reason = data.get("reason", "?")
                t = data.get("time", 0)
                lines.append(f"*finish: reason={reason} time={t}ms*")
                lines.append("")
            else:
                lines.append(f"<!-- unknown part.type={ptype}: {json.dumps(data)[:200]} -->")
                lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# commands
# ---------------------------------------------------------------------------

def cmd_list(args: argparse.Namespace) -> None:
    db = Path(args.db).expanduser()
    conn = open_db(db)
    unit = verify_time_unit(conn)
    if unit == "unknown":
        sys.exit("could not determine time unit (no sessions?)")
    if args.warn_time:
        print(f"# {SCHEMA_TIME_HINT}; detected unit = {unit}", file=sys.stderr)
    sessions = list_sessions(conn, args.since, args.until, unit)
    if args.json:
        print(json.dumps(sessions, indent=2, ensure_ascii=False))
        return
    print(f"# {len(sessions)} session(s)  db={db}  unit={unit}")
    for s in sessions:
        print(
            f"{s['created_at_iso']}  "
            f"msgs={s['message_count']:>4}  "
            f"id={s['id'][:16]}  "
            f"{s['title'][:60]}"
        )


def cmd_show(args: argparse.Namespace) -> None:
    db = Path(args.db).expanduser()
    conn = open_db(db)
    unit = verify_time_unit(conn)
    sess = fetch_session(conn, args.session)
    if not sess:
        sys.exit(f"session not found: {args.session}")
    sess = row_to_session(sess, unit)
    msgs = fetch_messages(conn, args.session)
    print(json.dumps({
        "session": sess,
        "message_count_actual": len(msgs),
        "message_count_column": sess.get("message_count"),
    }, indent=2, ensure_ascii=False))


def cmd_dump(args: argparse.Namespace) -> None:
    db = Path(args.db).expanduser()
    conn = open_db(db)
    unit = verify_time_unit(conn)
    sess = fetch_session(conn, args.session)
    if not sess:
        sys.exit(f"session not found: {args.session}")
    sess = row_to_session(sess, unit)
    msgs = fetch_messages(conn, args.session)
    if args.format == "json":
        out = {"session": sess, "messages": msgs}
        text = json.dumps(out, indent=2, ensure_ascii=False)
    else:
        text = render_markdown(sess, msgs, unit)
    if args.out:
        Path(args.out).expanduser().write_text(text, encoding="utf-8")
        print(f"wrote {args.out} ({len(text)} chars, {len(msgs)} messages)")
    else:
        sys.stdout.write(text)


def cmd_verify(args: argparse.Namespace) -> None:
    db = Path(args.db).expanduser()
    if not db.exists():
        sys.exit(f"db not found: {db}")
    # hot-backup via sqlite's .backup (WAL-safe)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = db.with_suffix(f".pre-verify-{ts}.bak")
    src = sqlite3.connect(str(db))
    dst = sqlite3.connect(str(backup))
    with dst:
        src.backup(dst)
    src.close()
    dst.close()
    size = backup.stat().st_size
    print(f"# backup: {backup}  ({size:,} bytes)")
    # verify
    conn = open_db(db)
    unit = verify_time_unit(conn)
    n_sessions = conn.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
    n_messages = conn.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
    # cross-check: session.message_count vs actual
    bad = conn.execute("""
        SELECT s.id, s.title, s.message_count, COUNT(m.id) AS actual
        FROM sessions s LEFT JOIN messages m ON m.session_id = s.id
        GROUP BY s.id
        HAVING s.message_count != actual
    """).fetchall()
    print(f"# unit detected: {unit}")
    print(f"# sessions: {n_sessions}")
    print(f"# messages: {n_messages}")
    if bad:
        print(f"# !! {len(bad)} session(s) have message_count mismatch:")
        for r in bad:
            print(f"  {r['id'][:16]}  col={r['message_count']}  actual={r['actual']}  {r['title'][:40]}")
        sys.exit(1)
    print("# message_count column matches actual count for all sessions ✓")


def cmd_find(args: argparse.Namespace) -> None:
    root = Path(args.root).expanduser()
    dbs = find_crush_dbs(root)
    print(f"# found {len(dbs)} .crush/crush.db under {root}")
    for d in dbs:
        try:
            conn = open_db(d)
            n_s = conn.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
            n_m = conn.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
            conn.close()
        except sqlite3.Error as e:
            print(f"{d}  ERROR: {e}")
            continue
        size = d.stat().st_size
        mtime = datetime.fromtimestamp(d.stat().st_mtime, tz=timezone.utc).isoformat()
        print(f"{size:>10,}  {mtime}  sessions={n_s:>4}  msgs={n_m:>6}  {d}")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    p_list = sub.add_parser("list", help="list sessions (filterable by date)")
    p_list.add_argument("--db", default="~/.config/crush/.crush/crush.db")
    p_list.add_argument("--since", help="YYYY-MM-DD inclusive")
    p_list.add_argument("--until", help="YYYY-MM-DD inclusive")
    p_list.add_argument("--json", action="store_true")
    p_list.add_argument("--warn-time", action="store_true", help="print time-unit note")
    p_list.set_defaults(func=cmd_list)

    p_show = sub.add_parser("show", help="show one session metadata + message_count cross-check")
    p_show.add_argument("--db", required=True)
    p_show.add_argument("--session", required=True)
    p_show.set_defaults(func=cmd_show)

    p_dump = sub.add_parser("dump", help="dump session transcript to md or json")
    p_dump.add_argument("--db", required=True)
    p_dump.add_argument("--session", required=True)
    p_dump.add_argument("--format", choices=["md", "json"], default="md")
    p_dump.add_argument("--out", help="output file (default stdout)")
    p_dump.set_defaults(func=cmd_dump)

    p_verify = sub.add_parser("verify", help="hot-backup DB + cross-check message_count")
    p_verify.add_argument("--db", required=True)
    p_verify.set_defaults(func=cmd_verify)

    p_find = sub.add_parser("find", help="find all .crush/crush.db under a root")
    p_find.add_argument("--root", default="~")
    p_find.set_defaults(func=cmd_find)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()