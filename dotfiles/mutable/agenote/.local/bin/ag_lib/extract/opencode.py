# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""opencode conversation extractor (SQLite, opencode-stable.db).

Schema (verified ~/.local/share/opencode/opencode-stable.db, 476MB):
  session(id, title, directory, time_created, time_updated, project_id, ...)
  message(id, session_id, time_created, data JSON)
    data.role = 'user' | 'assistant'
    data.modelID = model identifier
    data.agent = agent name
  part(id, message_id, session_id, time_created, data JSON)
    data.type = 'text' | 'reasoning' | 'tool' | 'patch'

Triple read-only via open_sqlite_ro().
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from ag_lib.reconcile import ReconciledFact, RECONCILE_DEFAULT_WEIGHT
from ag_lib.extract import open_sqlite_ro, resolve_xdg_path, extract_title

# Path resolution: env override → XDG default → ~/local/share/opencode/opencode-stable.db
OPENCODE_DB = Path(
    os.environ.get(
        "OPENCODE_DB",
        str(
            resolve_xdg_path(
                "OPENCODE_DB", "~/.local/share/opencode/opencode-stable.db"
            )
        ),
    )
).expanduser()

# RECONCILE_DEFAULT_WEIGHT 从 reconcile 统一导入，避免分散定义


def _categorize(session_row) -> str:
    """Derive category from session.title heuristics."""
    title = (session_row["title"] or "").lower()
    if any(k in title for k in ("chat", "对话")):
        return "chat"
    if any(k in title for k in ("tool", "工具", "tooling")):
        return "tool"
    if any(k in title for k in ("fix", "bug", "修复", "错误")):
        return "fix"
    return "general"


def _session_to_facts(session_row, conn) -> list[ReconciledFact]:
    """Convert one opencode session to user→assistant ReconciledFact pairs."""
    facts: list[ReconciledFact] = []
    messages = conn.execute(
        "SELECT id, time_created, data FROM message WHERE session_id = ? ORDER BY time_created",
        (session_row["id"],),
    ).fetchall()

    current_user: str | None = None
    current_user_ts: str = ""
    for msg in messages:
        try:
            md = json.loads(msg["data"])
        except (json.JSONDecodeError, TypeError):
            continue
        role = md.get("role", "")

        if role == "user":
            parts = conn.execute(
                "SELECT data FROM part WHERE message_id = ? ORDER BY time_created",
                (msg["id"],),
            ).fetchall()
            texts: list[str] = []
            for p in parts:
                try:
                    pd = json.loads(p["data"])
                    if pd.get("type") == "text":
                        texts.append(pd.get("text", ""))
                except (json.JSONDecodeError, TypeError):
                    continue
            content = "\n\n".join(t for t in texts if t).strip()
            if content:
                current_user = content
                current_user_ts = str(msg["time_created"] or "")

        elif role == "assistant" and current_user:
            parts = conn.execute(
                "SELECT data FROM part WHERE message_id = ? ORDER BY time_created",
                (msg["id"],),
            ).fetchall()
            resp_parts: list[str] = []
            for p in parts:
                try:
                    pd = json.loads(p["data"])
                    ptype = pd.get("type", "")
                    if ptype == "text":
                        resp_parts.append(pd.get("text", ""))
                    elif ptype == "reasoning":
                        resp_parts.append(f"[reasoning] {pd.get('text', '')[:200]}")
                    elif ptype == "tool":
                        tool_name = pd.get("tool", "?")
                        resp_parts.append(f"[tool: {tool_name}]")
                    elif ptype == "patch":
                        files = pd.get("files", [])
                        resp_parts.append(f"[patch: {len(files)} files]")
                except (json.JSONDecodeError, TypeError):
                    continue
            resp_content = "\n\n".join(t for t in resp_parts if t).strip()
            if resp_content:
                sess_title = session_row["title"] or "Untitled"
                facts.append(
                    ReconciledFact(
                        id=f'opencode:{session_row["id"]}:{msg["id"]}',
                        source="opencode",
                        native_id=msg["id"],
                        title=extract_title(current_user) or sess_title[:80],
                        category=_categorize(session_row),
                        content=f"USER: {current_user[:1000]}\n\nASSISTANT: {resp_content[:2000]}",
                        trust_score=0.5,
                        weight=RECONCILE_DEFAULT_WEIGHT,
                        tags=[
                            (
                                session_row["directory"].split("/")[-1]
                                if session_row["directory"]
                                else "unknown"
                            )
                        ],
                        timestamp=current_user_ts,
                    )
                )
                current_user = None
                current_user_ts = ""
    return facts


def extract_opencode() -> tuple[list[ReconciledFact], list[str]]:
    """Extract all conversation turns from opencode-stable.db (read-only)."""
    facts: list[ReconciledFact] = []
    errors: list[str] = []
    try:
        conn = open_sqlite_ro(OPENCODE_DB)
    except FileNotFoundError as e:
        return [], [str(e)]
    try:
        sessions = conn.execute(
            "SELECT id, title, directory, time_created, time_updated "
            "FROM session ORDER BY time_created"
        ).fetchall()
        for sess in sessions:
            try:
                facts.extend(_session_to_facts(sess, conn))
            except Exception as e:
                errors.append(f"session={sess['id']}: {e}")
    finally:
        conn.close()
    return facts, errors


def trace_session(session_id: str) -> dict:
    """回查一个 session 的完整原始对话（dream trace 溯源用，不截断）。

    与 _session_to_facts 的区别：
    - 不截断（[:1000]/[:2000] 全去掉），reasoning/tool/patch 取全文
    - 返回结构化 {session, messages: [{role, ts, parts: [{type, text}]}]}，
      而非拼成单条 content

    三重只读保护复用 open_sqlite_ro（与 extract 一致）。
    """
    try:
        conn = open_sqlite_ro(OPENCODE_DB)
    except FileNotFoundError as e:
        return {"error": str(e), "session_id": session_id}
    try:
        sess = conn.execute(
            "SELECT id, title, directory, time_created FROM session WHERE id = ?",
            (session_id,),
        ).fetchone()
        if sess is None:
            return {"error": f"session {session_id} 不存在", "session_id": session_id}
        messages_raw = conn.execute(
            "SELECT id, time_created, data FROM message "
            "WHERE session_id = ? ORDER BY time_created",
            (session_id,),
        ).fetchall()
        msgs: list[dict] = []
        for m in messages_raw:
            try:
                md = json.loads(m["data"])
            except (json.JSONDecodeError, TypeError):
                continue
            parts_out: list[dict] = []
            parts = conn.execute(
                "SELECT data FROM part WHERE message_id = ? ORDER BY time_created",
                (m["id"],),
            ).fetchall()
            for p in parts:
                try:
                    pd = json.loads(p["data"])
                except (json.JSONDecodeError, TypeError):
                    continue
                ptype = pd.get("type", "")
                entry: dict = {"type": ptype}
                if ptype == "text":
                    entry["text"] = pd.get("text", "")
                elif ptype == "reasoning":
                    entry["text"] = pd.get("text", "")  # 不截断
                elif ptype == "tool":
                    entry["tool"] = pd.get("tool", "?")
                    entry["input"] = pd.get("input", {})
                elif ptype == "patch":
                    entry["files"] = pd.get("files", [])
                parts_out.append(entry)
            msgs.append(
                {
                    "role": md.get("role", ""),
                    "ts": str(m["time_created"] or ""),
                    "parts": parts_out,
                }
            )
        return {
            "source": "opencode",
            "session_id": session_id,
            "session": {
                "title": sess["title"],
                "directory": sess["directory"],
                "time_created": str(sess["time_created"] or ""),
            },
            "messages": msgs,
        }
    finally:
        conn.close()
