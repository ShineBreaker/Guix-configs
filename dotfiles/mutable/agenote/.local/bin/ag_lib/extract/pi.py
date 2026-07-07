# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""pi conversation extractor (JSONL event stream, parentId reconstruction).

XDG path (from source/config.org:1864):
  PI_CODING_AGENT_SESSION_DIR = $XDG_DATA_HOME/pi/sessions

Schema: JSONL event stream, each line {type, id, parentId, timestamp, ...}
  type=session  → {id, timestamp (ISO UTC), cwd}
  type=message  → {id, parentId, role, content, model, ...}

Key: rebuild message order by parentId chain (NOT timestamp, unlike codex/claude).
ISO UTC timestamp needs timezone normalization.
"""

from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path

from ag_lib.reconcile import ReconciledFact, RECONCILE_DEFAULT_WEIGHT
from ag_lib.extract import resolve_xdg_path, extract_title

PI_SESSIONS_DIR = resolve_xdg_path(
    "PI_CODING_AGENT_SESSION_DIR",
    "$XDG_DATA_HOME/pi/sessions",
)

RECONCILE_DEFAULT_WEIGHT  # pi 是自家 agent，沿用 reconcile 统一基准 0.7


def _parse_iso_timestamp(ts: str) -> datetime | None:
    """Parse ISO UTC timestamp (handle trailing Z)."""
    if not ts:
        return None
    try:
        ts = ts.replace("Z", "+00:00")
        return datetime.fromisoformat(ts).replace(tzinfo=None)
    except (ValueError, TypeError):
        return None


def _normalize_content(content) -> str:
    """Extract text from pi message content (str, list of parts)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        texts: list[str] = []
        for part in content:
            if isinstance(part, dict):
                ptype = part.get("type", "")
                if ptype == "text":
                    texts.append(part.get("text", ""))
                elif ptype == "tool_use":
                    texts.append(
                        f"[tool_use: {part.get('name', '?')}] "
                        f"{json.dumps(part.get('input', {}), ensure_ascii=False)[:300]}"
                    )
                elif ptype == "tool_result":
                    c = part.get("content", "")
                    if isinstance(c, str):
                        texts.append(f"[tool_result] {c[:500]}")
                    else:
                        texts.append(
                            f"[tool_result] {json.dumps(c, ensure_ascii=False)[:500]}"
                        )
            elif isinstance(part, str):
                texts.append(part)
        return "\n".join(t for t in texts if t)
    return str(content)


def _extract_session_file(jsonl_path: Path) -> tuple[list[ReconciledFact], list[str]]:
    """Extract from one .jsonl session file (parentId-ordered)."""
    facts: list[ReconciledFact] = []
    errors: list[str] = []
    session_meta: dict = {}
    messages: list[dict] = []

    try:
        with open(jsonl_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    evt = json.loads(line)
                except json.JSONDecodeError:
                    continue
                etype = evt.get("type", "")
                if etype == "session":
                    session_meta = {
                        "id": evt.get("id", jsonl_path.stem),
                        "cwd": evt.get("cwd", ""),
                    }
                elif etype == "message":
                    messages.append(evt)
    except OSError as e:
        return [], [str(e)]

    if not messages:
        return facts, errors

    # Build parentId tree
    msg_by_id: dict[str, dict] = {m.get("id", ""): m for m in messages if m.get("id")}
    children: dict[str, list[str]] = {}
    for m in messages:
        pid = m.get("parentId", "") or ""
        if pid:
            children.setdefault(pid, []).append(m.get("id", ""))

    # Find roots (no parentId or parent not in messages)
    root_ids: list[str] = []
    for m in messages:
        pid = m.get("parentId", "") or ""
        if not pid or pid not in msg_by_id:
            rid = m.get("id", "")
            if rid:
                root_ids.append(rid)

# Iterative DFS walk (avoid Python recursion limit on deep 700+ chains)
    ordered: list[dict] = []

    for rid in root_ids:
        stack: list[str] = [rid]
        while stack:
            mid = stack.pop()
            if mid not in msg_by_id:
                continue
            ordered.append(msg_by_id[mid])
            # Push children in reverse so leftmost is processed first
            cids = children.get(mid, [])
            for cid in reversed(cids):
                stack.append(cid)

    # First user message as title
    title = "Untitled"
# Note: real schema nests role/content under message: {id, parentId, timestamp, type:message, message:{role, content, timestamp}}
    for m in ordered:
        msg = m.get("message", {}) if isinstance(m.get("message"), dict) else {}
        if msg.get("role") == "user":
            text = _normalize_content(msg.get("content", "")).strip()
            title = extract_title(text) or "Untitled"
            break

    session_id = session_meta.get("id", jsonl_path.stem)
    cwd = session_meta.get("cwd", "")
    tag = cwd.split("/")[-1] if cwd else "pi"

# user → assistant pairing (role/content nested under message.* per real schema)
    current_user: str | None = None
    current_user_ts: str = ""
    for m in ordered:
        msg = m.get("message", {}) if isinstance(m.get("message"), dict) else {}
        role = msg.get("role", "")
        text = _normalize_content(msg.get("content", "")).strip()
        if role == "user":
            current_user = text
            # 优先用 message 事件顶层 timestamp；回退 message 内嵌 timestamp
            current_user_ts = str(m.get("timestamp") or msg.get("timestamp") or "")
        elif role == "assistant" and current_user and text:
            facts.append(
                ReconciledFact(
                    id=f'pi:{session_id}:{m.get("id", ordered.index(m))}',
                    source="pi",
                    native_id=m.get("id", str(ordered.index(m))),
                    title=title,
                    category="general",
                    content=f"USER: {current_user[:1000]}\n\nASSISTANT: {text[:2000]}",
                    trust_score=0.5,
                    weight=RECONCILE_DEFAULT_WEIGHT,
                    tags=[tag],
                    timestamp=current_user_ts,
                )
            )
            current_user = None
            current_user_ts = ""
    return facts, errors


def extract_pi() -> tuple[list[ReconciledFact], list[str]]:
    """Extract from pi sessions/ (read-only, parentId-rebuilt)."""
    all_facts: list[ReconciledFact] = []
    all_errors: list[str] = []
    if not PI_SESSIONS_DIR.exists():
        return [], [f"pi sessions dir 不存在: {PI_SESSIONS_DIR}"]
    for jsonl_path in sorted(PI_SESSIONS_DIR.glob("*.jsonl")):
        facts, errors = _extract_session_file(jsonl_path)
        all_facts.extend(facts)
        all_errors.extend(errors)
    return all_facts, all_errors