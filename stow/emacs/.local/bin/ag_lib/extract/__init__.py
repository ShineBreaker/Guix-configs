# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""ag_lib.extract — cross-agent conversation extraction common layer.

Provide XDG-aware path resolution, SQLite read-only open helper, title extractor.
Each source (opencode/crush/codex/claude/pi) lives in its own file with signature:
    (list[ReconciledFact], list[str])
"""

from __future__ import annotations

import os
import re
import sqlite3
from pathlib import Path


# ── XDG-aware path resolution ──────────────────────────────────

def resolve_xdg_path(env_var: str, default: str) -> Path:
    """Resolve path respecting env var, then XDG base dirs.

    Lookup order:
      1. os.environ[env_var] (direct override)
      2. $XDG_DATA_HOME / $XDG_CONFIG_HOME from default placeholder
      3. expanduser fallback (~/...)

    default may use $XDG_DATA_HOME/$XDG_CONFIG_HOME placeholders:
        resolve_xdg_path('CODEX_HOME', '$XDG_CONFIG_HOME/codex')
    """
    val = os.environ.get(env_var)
    if val:
        return Path(val).expanduser()

    # Resolve $XDG_*_HOME placeholders in default
    m = re.match(r'\$XDG_(\w+)_HOME', default)
    if m:
        xdg_key = f"XDG_{m.group(1)}_HOME"
        xdg_val = os.environ.get(xdg_key)
        if xdg_val:
            remainder = default.split('/', 1)[1] if '/' in default else ''
            return Path(xdg_val) / remainder

    return Path(default.replace('~', str(Path.home()))).expanduser()


# ── SQLite read-only open (triple protection) ─────────────────

def open_sqlite_ro(db_path: Path) -> sqlite3.Connection:
    """Triple read-only SQLite protection:
    1. file: URI + mode=ro (SQLite layer rejects writes)
    2. PRAGMA query_only = 1 (connection layer rejects DML/DDL)
    3. Caller never constructs write statements (convention)
    """
    if not db_path.exists():
        raise FileNotFoundError(f"DB 不存在: {db_path}")
    uri = f"file:{db_path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA query_only = 1")
    return conn


# ── Title extraction helper ───────────────────────────────────

_TITLE_BRACKET_RE = re.compile(r"^【([^】]+)】")
_TITLE_SENT_RE = re.compile(r"[^。\n!?:;]+")


def extract_title(content: str, max_len: int = 60) -> str:
    """Unified title extractor: 【...】 bracket → first sentence → truncate."""
    m = _TITLE_BRACKET_RE.match(content.strip())
    if m:
        return m.group(1).strip()[:max_len]
    first = _TITLE_SENT_RE.match(content.strip())
    raw = (first.group(0).strip() if first else content.strip())[:40]
    return raw or "(untitled)"