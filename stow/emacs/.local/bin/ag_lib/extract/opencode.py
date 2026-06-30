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
        str(resolve_xdg_path("OPENCODE_DB", "~/.local/share/opencode/opencode-stable.db")),
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
                            session_row["directory"].split("/")[-1]
                            if session_row["directory"]
                            else "unknown"
                        ],
                    )
                )
                current_user = None
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