# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""codex conversation extractor (JSONL, history.jsonl + sessions/YYYY/MM/).

XDG path (from source/config.org:1837):
  CODEX_HOME = $XDG_CONFIG_HOME/codex = ~/.config/codex

Schema:
  - history.jsonl: each line {session_id, ts, text, cwd, ...}
    → builds session_id → {title, cwd, ts} index
  - sessions/YYYY/MM/rollout-*.jsonl: each line {type, message, timestamp, ...}
    type ∈ session | user | assistant | tool | response
    → rebuild user→assistant pairs by timestamp order (NOT parentId like pi)

Read-only: JSONL read-only, never constructs writes.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from ag_lib.reconcile import ReconciledFact, RECONCILE_DEFAULT_WEIGHT
from ag_lib.extract import resolve_xdg_path, extract_title

CODEX_HOME = resolve_xdg_path("CODEX_HOME", "$XDG_CONFIG_HOME/codex")
HISTORY_JSONL = CODEX_HOME / "history.jsonl"
SESSIONS_ROOT = CODEX_HOME / "sessions"

# codex 外部源：trust 0.5 → weight 0.6（略低于 hermes/pi 的 0.7）
EXTERNAL_RECONCILE_WEIGHT = round(RECONCILE_DEFAULT_WEIGHT - 0.1, 2)


def _load_history_index() -> dict[str, dict]:
    """Build session_id → {title, cwd, ts} index from history.jsonl."""
    index: dict[str, dict] = {}
    if not HISTORY_JSONL.exists():
        return index
    try:
        with open(HISTORY_JSONL, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                sid = entry.get("session_id", "")
                if sid and sid not in index:
                    index[sid] = {
                        "title": (entry.get("text", "Untitled") or "Untitled")[:80],
                        "cwd": entry.get("cwd", ""),
                        "ts": entry.get("ts", 0),
                    }
    except OSError:
        pass
    return index


def _normalize_message(msg) -> str:
    """Extract plain text from message which may be str, list of parts, or dict."""
    if isinstance(msg, str):
        return msg.strip()
    if isinstance(msg, list):
        texts: list[str] = []
        for part in msg:
            if isinstance(part, dict):
                if part.get("type") == "text":
                    texts.append(part.get("text", ""))
                elif part.get("type") == "input_text":
                    texts.append(part.get("text", ""))
                elif part.get("type") == "output_text":
                    texts.append(part.get("text", ""))
            elif isinstance(part, str):
                texts.append(part)
        return "\n".join(t for t in texts if t).strip()
    if isinstance(msg, dict):
        return _normalize_message(msg.get("content", msg.get("text", "")))
    return str(msg).strip()


def _extract_session_file(
    jsonl_path: Path, history_idx: dict[str, dict]
) -> tuple[list[ReconciledFact], list[str]]:
    """Extract from one rollout-*.jsonl file."""
    facts: list[ReconciledFact] = []
    errors: list[str] = []
    # Filename: rollout-<uuid>.jsonl → session_id = uuid
    session_id = jsonl_path.stem.replace("rollout-", "")
    meta = history_idx.get(session_id, {})
    title = meta.get("title", "Untitled")
    cwd = meta.get("cwd", "")

    events: list[dict] = []
    try:
        with open(jsonl_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except OSError as e:
        return [], [str(e)]

    # Sort by timestamp (ms or ISO string); fallback to insertion order
    def _ts_key(e: dict) -> float:
        ts = e.get("timestamp", e.get("ts", 0))
        if isinstance(ts, (int, float)):
            return float(ts)
        if isinstance(ts, str):
            try:
                from datetime import datetime
                ts = ts.replace("Z", "+00:00")
                return datetime.fromisoformat(ts).timestamp()
            except (ValueError, TypeError):
                return 0.0
        return 0.0

    events.sort(key=_ts_key)
# Real codex schema: {timestamp, type, payload}; session_meta→payload.{id,cwd},
    # response_item→payload.{type:"message", role, content:[{type:"input_text"|"output_text", text}]}
    session_id_evt: str | None = None
    cwd_evt: str | None = None
    current_user: str | None = None
    for evt in events:
        etype = evt.get("type", "")
        payload = evt.get("payload") if isinstance(evt.get("payload"), dict) else {}

        if etype == "session_meta":
            sid_meta = payload.get("id", "")
            if sid_meta and session_id_evt is None:
                session_id_evt = sid_meta
            cwd_meta = payload.get("cwd", "")
            if cwd_meta and cwd_evt is None:
                cwd_evt = cwd_meta

        elif etype == "response_item" and payload.get("type") == "message":
            role = payload.get("role", "")
            content = _normalize_message(payload.get("content", ""))
            if role == "user" and content:
                current_user = content
            elif role == "assistant" and current_user and content:
                tag = (cwd_evt or cwd).split("/")[-1] if (cwd_evt or cwd) else "codex"
                sid = session_id_evt or session_id
                evt_ts = str(evt.get("timestamp", ""))
                facts.append(
                    ReconciledFact(
                        id=f'codex:{sid}:{evt_ts or events.index(evt)}',
                        source="codex",
                        native_id=evt_ts or str(events.index(evt)),
                        title=extract_title(current_user) or title,
                        category="general",
                        content=f"USER: {current_user[:1000]}\n\nASSISTANT: {content[:2000]}",
                        trust_score=0.5,
                        weight=EXTERNAL_RECONCILE_WEIGHT,
                        tags=[tag],
                        timestamp=evt_ts,
                    )
                )
                current_user = None
    return facts, errors


def extract_codex() -> tuple[list[ReconciledFact], list[str]]:
    """Extract from codex history + sessions/YYYY/MM (read-only)."""
    all_facts: list[ReconciledFact] = []
    all_errors: list[str] = []
    if not CODEX_HOME.exists():
        return [], [f"CODEX_HOME 不存在: {CODEX_HOME}"]
    history_idx = _load_history_index()
    if SESSIONS_ROOT.exists():
        for jsonl_path in sorted(SESSIONS_ROOT.rglob("rollout-*.jsonl")):
            facts, errors = _extract_session_file(jsonl_path, history_idx)
            all_facts.extend(facts)
            all_errors.extend(errors)
    return all_facts, all_errors