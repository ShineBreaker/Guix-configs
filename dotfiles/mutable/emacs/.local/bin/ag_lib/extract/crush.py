# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""crush conversation extractor (SQLite, global + project-level DB scan).

Schema (verified ~/.config/crush/.crush/crush.db):
  sessions(id, title, parent_session_id, message_count, ...)
  messages(id, session_id, role, parts JSON list, model, created_at, ...)
    parts: [{"type": "text", "data": {"text": "..."}}, {"type": "finish", ...}]
  files, read_files, goose_db_version

Project-level DBs discovered via scan: ~/Documents, ~/Documents/Repo,
~/Documents/Org, ~/.emacs.d, /data/Documents 下 .crush/crush.db。
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from ag_lib.reconcile import ReconciledFact, RECONCILE_DEFAULT_WEIGHT
from ag_lib.extract import open_sqlite_ro, resolve_xdg_path, extract_title

CRUSH_GLOBAL_DB = resolve_xdg_path(
    "CRUSH_GLOBAL_DB", "~/.config/crush/.crush/crush.db"
)

CRUSH_SEARCH_ROOTS = [
    "~/Documents",
    "~/Documents/Repo",
    "~/Documents/Org",
    "~/.emacs.d",
    "/data/Documents",
]

# parts JSON 解析：只取 type=text 的 data.text，type=finish/skip 等忽略
_TYPE_TEXT = "text"


def find_crush_dbs() -> list[Path]:
    """Scan all project-level Crush databases (dedup, skip nix store/Trash)."""
    found: set[Path] = {CRUSH_GLOBAL_DB}
    for root_str in CRUSH_SEARCH_ROOTS:
        root = Path(root_str).expanduser()
        if not root.exists():
            continue
        for db_path in root.rglob(".crush/crush.db"):
            spath = str(db_path)
            if "/nix/store/" not in spath and "/Trash/" not in spath:
                found.add(db_path)
    return sorted(found)


def _parts_to_text(parts_raw: str) -> str:
    """crush messages.parts 是 JSON list，逐项提取 type=text.data.text 拼接。

    Skip types: finish, tool_use, tool_result 等非纯文本 part。
    """
    if not parts_raw:
        return ""
    try:
        parts = json.loads(parts_raw)
    except (json.JSONDecodeError, TypeError):
        return ""
    if not isinstance(parts, list):
        return ""
    texts: list[str] = []
    for part in parts:
        if not isinstance(part, dict):
            continue
        if part.get("type") != _TYPE_TEXT:
            continue
        data = part.get("data") or {}
        if isinstance(data, dict):
            t = data.get("text", "")
            if t:
                texts.append(t)
    return "\n".join(texts).strip()


def _categorize(text: str) -> str:
    content = (text or "").lower()[:200]
    if any(k in content for k in ("error", "fix", "bug", "错误", "修复")):
        return "fix"
    if any(k in content for k in ("tool", "工具")):
        return "tool"
    return "general"


def _extract_from_db(db_path: Path) -> tuple[list[ReconciledFact], list[str]]:
    facts: list[ReconciledFact] = []
    errors: list[str] = []
    try:
        conn = open_sqlite_ro(db_path)
    except FileNotFoundError as e:
        return [], [str(e)]
    try:
        # Determine project_dir: global vs project-level
        if ".config/crush" in str(db_path):
            project_dir = "(global)"
        else:
            project_dir = str(db_path).rsplit("/.crush/", 1)[0]

        sessions = conn.execute(
            "SELECT id, title, created_at, updated_at FROM sessions"
        ).fetchall()
        for sess in sessions:
            try:
                messages = conn.execute(
                    "SELECT id, role, parts, created_at FROM messages "
                    "WHERE session_id = ? ORDER BY created_at",
                    (sess["id"],),
                ).fetchall()
                current_user: str | None = None
                for msg in messages:
                    role = msg["role"] or ""
                    content = _parts_to_text(msg["parts"] or "")
                    if role == "user":
                        current_user = content
                    elif role == "assistant" and current_user and content:
                        tag = (
                            project_dir.split("/")[-1]
                            if project_dir != "(global)"
                            else "crush-global"
                        )
                        facts.append(
                            ReconciledFact(
                                id=f'crush:{db_path.name}:{sess["id"]}:{msg["id"]}',
                                source="crush",
                                native_id=str(msg["id"]),
                                title=extract_title(current_user)
                                or (sess["title"] or "Untitled"),
                                category=_categorize(current_user + " " + content),
                                content=f"USER: {current_user[:1000]}\n\nASSISTANT: {content[:2000]}",
                                trust_score=0.5,
                                weight=RECONCILE_DEFAULT_WEIGHT,
                                tags=[tag],
                            )
                        )
                        current_user = None
            except Exception as e:
                errors.append(f"session={sess['id']}: {e}")
    finally:
        conn.close()
    return facts, errors


def extract_crush() -> tuple[list[ReconciledFact], list[str]]:
    """Extract from all Crush databases (global + project-level)."""
    all_facts: list[ReconciledFact] = []
    all_errors: list[str] = []
    for db_path in find_crush_dbs():
        facts, errors = _extract_from_db(db_path)
        all_facts.extend(facts)
        all_errors.extend(errors)
    return all_facts, all_errors