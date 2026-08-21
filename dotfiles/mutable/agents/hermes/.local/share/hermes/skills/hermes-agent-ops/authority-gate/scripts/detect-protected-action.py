#!/usr/bin/env python3
"""detect-protected-action.py — 给定命令字符串，判断是否命中 P 清单。

ad-hoc verification — not a test suite.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path
from typing import NamedTuple


class Match(NamedTuple):
    category: str  # P1/P2/P3/P4/P5
    pattern: str
    severity: str  # "必走"/"建议"


# Rule-based patterns. 顺序重要：先 long-specific, 后 generic.
RULES: list[tuple[str, str, re.Pattern, str]] = [
    # P1: 不可逆文件系统
    ("P1", "rm -rf", re.compile(r"\brm\s+-rf?\b|\brm\s+-fr\b"), "必走"),
    ("P1", "trash 大目录", re.compile(r"\btrash\b.*(?:^|\s)/"), "必走"),
    ("P1", "git push --force to protected", re.compile(r"\bgit\s+push\s+.*--force.*(?:origin\s+)?(?:main|master|prod)\b"), "必走"),
    ("P1", "git reset --hard", re.compile(r"\bgit\s+reset\s+--hard\b"), "必走"),
    ("P1", "git clean -fd", re.compile(r"\bgit\s+clean\s+-f"), "必走"),
    # P2: 凭据 / 付费
    ("P2", "API key in curl", re.compile(r"\bcurl\b.*(?:api[_-]?key|token|secret)\s*="), "必走"),
    ("P2", "sudo", re.compile(r"\bsudo\b"), "必走"),
    ("P2", "edit ~/.hermes/.env", re.compile(r"~/?\.hermes/\.env\b"), "必走"),
    ("P2", "edit ~/.hermes/auth.json", re.compile(r"~/?\.hermes/auth\.json\b"), "必走"),
    # P3: 跨会话状态
    ("P3", "edit hermes config.yaml", re.compile(r"~/?\.hermes/config\.yaml\b"), "必走"),
    ("P3", "hermes cron create", re.compile(r"\bhermes\s+cron\s+create\b"), "必走"),
    ("P3", "hermes skills uninstall", re.compile(r"\bhermes\s+skills\s+uninstall\b"), "必走"),
    ("P3", "edit ~/.bashrc", re.compile(r"(?:^|[^a-zA-Z0-9_])(?:sed\s+-i\b|(?:>|>>)\s+~/?\.(?:ba|z)shrc\b|~/?\.(?:ba|z)shrc\b\s*(?:>|>>))"), "必走"),
    ("P3", "git remote set-url", re.compile(r"\bgit\s+remote\s+set-url\b"), "必走"),
    # P4: 发布 / 公开
    ("P4", "git push (first time)", re.compile(r"\bgit\s+push\b.*(?:origin|upstream)\b"), "必走"),
    ("P4", "twine upload", re.compile(r"\btwine\s+upload\b"), "必走"),
    ("P4", "npm publish", re.compile(r"\bnpm\s+publish\b"), "必走"),
    ("P4", "git tag in release", re.compile(r"\bgit\s+tag\b.*(?:v\d|\d+\.\d+\.\d+)"), "建议"),
    # P5: 批量 / 不可逆
    ("P5", "find -delete", re.compile(r"\bfind\b.*-delete\b"), "必走"),
    ("P5", "rsync --delete", re.compile(r"\brsync\b.*--delete\b"), "必走"),
    ("P5", "guix remove", re.compile(r"\bguix\s+remove\b"), "必走"),
    ("P5", "kubectl delete", re.compile(r"\bkubectl\s+delete\b"), "必走"),
    ("P5", "DROP TABLE", re.compile(r"\bDROP\s+TABLE\b"), "必走"),
    ("P5", "DELETE FROM no WHERE", re.compile(r"\bDELETE\s+FROM\b(?![^\n;]*\bWHERE\b)"), "必走"),
]


def detect(cmd: str) -> list[Match]:
    hits: list[Match] = []
    for cat, pat_name, pattern, severity in RULES:
        if pattern.search(cmd):
            hits.append(Match(category=cat, pattern=pat_name, severity=severity))
    return hits


def main():
    if len(sys.argv) < 2:
        print("用法: detect-protected-action.py '<command>'", file=sys.stderr)
        print("      echo '<command>' | detect-protected-action.py", file=sys.stderr)
        sys.exit(2)

    if len(sys.argv) == 2 and sys.argv[1] == "-":
        cmd = sys.stdin.read()
    else:
        cmd = " ".join(sys.argv[1:])

    hits = detect(cmd)
    if not hits:
        print(f"OK (no protected action detected): {cmd[:80]}")
        sys.exit(0)

    print(f"PROTECTED: {cmd[:100]}")
    for h in hits:
        print(f"  - {h.category} [{h.severity}] pattern: {h.pattern}")
    sys.exit(1)


if __name__ == "__main__":
    main()