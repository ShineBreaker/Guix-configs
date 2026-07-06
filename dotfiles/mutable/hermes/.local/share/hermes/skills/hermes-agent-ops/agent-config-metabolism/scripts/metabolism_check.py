#!/usr/bin/env python3
"""
agent-config-metabolism — 14-check weekly audit.

Outputs 14 lines, each tagged [GREEN] / [RED] / [SKIP].
Writes the same report to $HERMES_HOME/cron/output/agent-config-metabolism-<ts>.log.

Thresholds live in metabolism_thresholds.yaml next to this script.
Stdlib only (yaml + json + subprocess + pathlib).
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# --- Paths ----------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
THRESHOLDS_PATH = SCRIPT_DIR / "metabolism_thresholds.yaml"

HERMES_HOME = Path(
    os.environ.get("HERMES_HOME") or Path.home() / ".local" / "share" / "hermes"
)


def _yaml_fallback(text: str) -> dict:
    """Minimal YAML subset loader — no PyYAML dep.

    Supports the flat key: value / list-of-strings structure used by
    metabolism_thresholds.yaml. Nested via 2-space indent.
    """
    root: dict = {}
    stack: list[tuple[int, dict]] = [(-1, root)]
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        content = line.strip()
        # pop deeper levels
        while stack and stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1]
        if content.startswith("- "):
            val = content[2:].strip()
            # ensure parent is a list
            if not isinstance(parent, list):
                # convert dict-as-list — shouldn't happen with our schema
                continue
            parent.append(_coerce(val))
        elif ":" in content:
            key, _, val = content.partition(":")
            key = key.strip()
            val = val.strip()
            if val == "":
                # nested block
                child: dict | list = {}
                parent[key] = child
                stack.append((indent, child))
            else:
                parent[key] = _coerce(val)
    return root


def _coerce(val: str):
    """Coerce YAML-ish scalar to python value."""
    if val in ("true", "True", "yes"):
        return True
    if val in ("false", "False", "no"):
        return False
    if val in ("null", "~", ""):
        return None
    # quoted string
    if (val.startswith('"') and val.endswith('"')) or (
        val.startswith("'") and val.endswith("'")
    ):
        return val[1:-1]
    # int / float
    try:
        return int(val)
    except ValueError:
        pass
    try:
        return float(val)
    except ValueError:
        pass
    return val


def load_thresholds() -> dict:
    if not THRESHOLDS_PATH.exists():
        sys.exit(f"ERROR: thresholds not found at {THRESHOLDS_PATH}")
    try:
        import yaml  # type: ignore
        with THRESHOLDS_PATH.open() as f:
            return yaml.safe_load(f) or {}
    except ImportError:
        with THRESHOLDS_PATH.open() as f:
            return _yaml_fallback(f.read())


# --- 14 checks ------------------------------------------------------------


def check_inject(cfg: dict) -> tuple[str, str]:
    """1. Inject size: sum of skill description fields + memory.md + USER.md.

    Only the `description` frontmatter field is injected into the system prompt
    (not the whole SKILL.md body). 25KB budget covers descriptions + memory.
    """
    max_kb = cfg.get("max_kb", 25)
    skills_dir = HERMES_HOME / "skills"
    desc_bytes = 0
    desc_count = 0
    if skills_dir.exists():
        import re as _re
        for p in skills_dir.rglob("SKILL.md"):
            try:
                # Read enough to cover typical frontmatter (≥4KB)
                head = p.read_text(errors="ignore")[:4096]
            except OSError:
                continue
            if not head.startswith("---"):
                continue
            # Find end of frontmatter (closing --- or end of head)
            fm_end = -1
            for marker in ("\n---", "\n...\n"):
                idx = head.find(marker, 3)
                if idx > 0:
                    fm_end = idx
                    break
            if fm_end < 0:
                fm_end = len(head)
            block = head[3:fm_end]
            m = _re.search(
                r'^description\s*:\s*(.*?)(?=\n[a-zA-Z_][\w-]*\s*:|\Z)',
                block, _re.M | _re.S,
            )
            if not m:
                continue
            desc = m.group(1).strip()
            if desc.startswith('"') and desc.endswith('"'):
                desc = desc[1:-1]
            if desc.startswith("'") and desc.endswith("'"):
                desc = desc[1:-1]
            desc = _re.sub(r"\s+", " ", desc)
            desc_bytes += len(desc.encode("utf-8"))
            desc_count += 1
    memory_dir = HERMES_HOME / "memories"
    mem_bytes = 0
    if memory_dir.exists():
        for p in memory_dir.rglob("*.md"):
            try:
                mem_bytes += p.stat().st_size
            except OSError:
                pass
    inject_bytes = desc_bytes + mem_bytes
    inject_kb = inject_bytes / 1024
    status = "GREEN" if inject_kb <= max_kb else "RED"
    detail = (
        f"inject {inject_kb:.1f}KB / {max_kb}KB "
        f"({desc_count} skills desc={desc_bytes}B + memory={mem_bytes}B)"
    )
    return status, detail


def check_skill_count(cfg: dict) -> tuple[str, str]:
    """2. Skill count: total SKILL.md under skills/."""
    max_n = cfg.get("max", 160)
    n = 0
    skills_dir = HERMES_HOME / "skills"
    if skills_dir.exists():
        n = sum(1 for _ in skills_dir.rglob("SKILL.md"))
    status = "GREEN" if n <= max_n else "RED"
    return status, f"skill_count {n} / {max_n}"


def check_broken_symlinks(cfg: dict) -> tuple[str, str]:
    """3. Broken symlinks under HERMES_HOME."""
    max_n = cfg.get("max", 0)
    broken: list[str] = []
    if HERMES_HOME.exists():
        for p in HERMES_HOME.rglob("*"):
            if p.is_symlink() and not p.exists():
                broken.append(str(p))
    n = len(broken)
    status = "GREEN" if n <= max_n else "RED"
    return status, f"symlinks {n} broken (max {max_n})"


def check_config_exists(cfg: dict) -> tuple[str, str]:
    """4. Critical config files present."""
    files = cfg.get("files", [])
    missing = [f for f in files if not (HERMES_HOME / f).exists()]
    status = "GREEN" if not missing else "RED"
    detail = f"config {'OK' if not missing else 'missing: ' + ','.join(missing)}"
    return status, detail


def check_rule_frontmatter(cfg: dict) -> tuple[str, str]:
    """5. Every SKILL.md / AGENTS.md has valid frontmatter.

    Frontmatter is valid iff:
      - file starts with `---`
      - `name:` and `description:` fields present in the frontmatter block
    Closing `---` is optional (YAML 1.1 — hermes accepts both styles).
    """
    required = cfg.get("required_fields", ["name", "description"])
    bad: list[str] = []
    skills_dir = HERMES_HOME / "skills"
    if skills_dir.exists():
        for p in skills_dir.rglob("SKILL.md"):
            try:
                # Read enough to cover typical frontmatter (≥4KB)
                head = p.read_text(errors="ignore")[:4096]
            except OSError:
                continue
            if not head.startswith("---"):
                bad.append(f"{p.name}:no_fm")
                continue
            # Find end of frontmatter (closing --- is optional)
            fm_end = -1
            for marker in ("\n---", "\n...\n"):
                idx = head.find(marker, 3)
                if idx > 0:
                    fm_end = idx
                    break
            if fm_end < 0:
                fm_end = len(head)
            block = head[3:fm_end]
            missing = [
                f for f in required
                if not re.search(rf"^{re.escape(f)}\s*:", block, re.M)
            ]
            if missing:
                bad.append(f"{p.name}:missing={','.join(missing)}")
    n_bad = len(bad)
    status = "GREEN" if n_bad == 0 else "RED"
    summary = "all valid" if n_bad == 0 else f"{n_bad} bad"
    detail = f"frontmatter {summary}"
    if n_bad > 0 and n_bad <= 5:
        detail += f" ({'; '.join(bad)})"
    return status, detail


def _parse_json_lenient(text: str) -> tuple[bool, str]:
    """Parse JSON with JSONC tolerance (trailing commas + // comments).

    TypeScript's tsconfig and VSCode's tsdoc metadata use JSONC. Standard
    `json.loads` rejects both. We strip those out before parsing.
    """
    # Strip // line comments (but not // inside strings).
    out_lines = []
    for line in text.split("\n"):
        in_str = False
        esc = False
        cleaned = []
        i = 0
        while i < len(line):
            ch = line[i]
            if esc:
                cleaned.append(ch)
                esc = False
            elif ch == "\\":
                cleaned.append(ch)
                esc = True
            elif ch == '"':
                in_str = not in_str
                cleaned.append(ch)
            elif not in_str and i + 1 < len(line) and line[i] == "/" and line[i + 1] == "/":
                break  # rest of line is comment
            else:
                cleaned.append(ch)
            i += 1
        out_lines.append("".join(cleaned))
    cleaned = "\n".join(out_lines)
    # Strip trailing commas in objects/arrays: ,] or ,}
    cleaned = re.sub(r",(\s*[\]}])", r"\1", cleaned)
    try:
        json.loads(cleaned)
        return True, ""
    except (json.JSONDecodeError, ValueError) as e:
        return False, f"{type(e).__name__}: {e}"


def check_json_parseable(cfg: dict) -> tuple[str, str]:
    """6. Every *.json under HERMES_HOME is valid JSON (or JSONC).

    JSONC tolerance catches tsconfig.json and tsdoc-metadata.json shipped
    by hermes LSP tooling (yaml-language-server, bash-language-server, etc.).
    These are NOT broken — they're JSONC, the de-facto TS/VSCode dialect.
    """
    globs = cfg.get("globs", ["*.json"])
    exclude = cfg.get("exclude", [])
    bad: list[tuple[str, str]] = []
    if HERMES_HOME.exists():
        for pat in globs:
            for p in HERMES_HOME.rglob(pat):
                rel = p.relative_to(HERMES_HOME).as_posix()
                if any(_glob_match(rel, ex) for ex in exclude):
                    continue
                try:
                    text = p.read_text(errors="ignore")
                except OSError:
                    continue
                ok, err = _parse_json_lenient(text)
                if not ok:
                    bad.append((rel, err))
    n_bad = len(bad)
    status = "GREEN" if n_bad == 0 else "RED"
    if n_bad == 0:
        detail = "json all parseable (JSON+JSONC)"
    else:
        sample = "; ".join(f"{r}[{t}]" for r, t in bad[:5])
        detail = f"json {n_bad} broken ({sample})"
    return status, detail


def check_cron_alive(cfg: dict) -> tuple[str, str]:
    """7. Cron tick log is fresh (last success < max_age_days)."""
    max_days = cfg.get("max_age_days", 7)
    ticker = HERMES_HOME / "cron" / "ticker_last_success"
    if not ticker.exists():
        return "RED", "cron ticker file missing"
    try:
        ts_str = ticker.read_text().strip()
        # Accept either ISO 8601 ("2026-07-06T...") or Unix timestamp float
        try:
            ts = _dt.datetime.fromisoformat(ts_str)
        except ValueError:
            ts = _dt.datetime.fromtimestamp(float(ts_str))
    except (ValueError, OSError):
        return "RED", "cron ticker unparseable"
    age = _dt.datetime.now() - ts
    age_days = age.total_seconds() / 86400
    status = "GREEN" if age_days <= max_days else "RED"
    return status, f"cron_alive {age_days:.1f}d / {max_days}d"


def check_pipeline_fresh(cfg: dict) -> tuple[str, str]:
    """8. Last session timestamp within max_age_hours."""
    max_h = cfg.get("max_age_hours", 24)
    # Look for the most recent *.jsonl under sessions/ or state.db mtime
    candidates = []
    sessions_dir = HERMES_HOME / "sessions"
    if sessions_dir.exists():
        for p in sessions_dir.rglob("*"):
            if p.is_file():
                candidates.append(p.stat().st_mtime)
    state_db = HERMES_HOME / "state.db"
    if state_db.exists():
        candidates.append(state_db.stat().st_mtime)
    if not candidates:
        return "RED", "no session data found"
    last_ts = max(candidates)
    age_h = (_dt.datetime.now().timestamp() - last_ts) / 3600
    status = "GREEN" if age_h <= max_h else "RED"
    return status, f"pipeline_fresh {age_h:.1f}h / {max_h}h"


def check_cross_window_errors(cfg: dict) -> tuple[str, str]:
    """9. Error count in scanned logs.

    Groups errors by (file:module:exception) signature so "26246 errors" reads as
    "47 unique signatures" — the metabolic point is whether you have N independent
    problems or one repeating failure. Signature expansion includes the actual
    exception type from Traceback tails (e.g. ModuleNotFoundError vs ImportError).
    """
    max_per = cfg.get("max_per_day", 5)
    log_globs = cfg.get("log_globs", [])
    err_count = 0
    sig_count: dict[str, int] = {}
    if HERMES_HOME.exists():
        for pat in log_globs:
            for p in HERMES_HOME.glob(pat):
                if not p.is_file():
                    continue
                try:
                    text = p.read_text(errors="ignore")
                except OSError:
                    continue
                # Pre-extract the tail exception type per Traceback block.
                # Walk the text line by line, finding each "Traceback" header and
                # consuming subsequent indented frames until we hit the column-0
                # exception line.
                tail_by_offset: dict[int, str] = {}
                lines = text.split("\n")
                i = 0
                while i < len(lines):
                    if lines[i].startswith("Traceback (most recent call last):"):
                        tb_start_offset = sum(len(l) + 1 for l in lines[:i])
                        # find the column-0 exception line (no leading whitespace)
                        j = i + 1
                        tail = None
                        while j < len(lines):
                            if lines[j] and not lines[j][0].isspace():
                                # column-0 line — should be the exception
                                em = re.match(
                                    r"^([\w.]+(?:Error|Exception|Warning|Failure|Interrupt))",
                                    lines[j],
                                )
                                if em:
                                    tail = em.group(1)
                                    break
                                # not an exception line — leave block unmarked
                                break
                            j += 1
                        tail_by_offset[tb_start_offset] = tail or "Exception"
                        i = j + 1 if tail else i + 1
                    else:
                        i += 1
                # Walk lines, find each line's absolute offset in text.
                pos = 0
                for line in text.splitlines(keepends=True):
                    line_start = pos
                    pos += len(line)
                    if "ERROR" not in line and "Traceback" not in line:
                        continue
                    err_count += 1
                    if "Traceback" in line:
                        # find nearest preceding Traceback start
                        tail = "Traceback"
                        for tb_pos in sorted(tail_by_offset):
                            if tb_pos <= line_start:
                                tail = tail_by_offset[tb_pos]
                            else:
                                break
                        sig = f"{p.name}::{tail}"
                    else:
                        m = re.search(r"ERROR\s+([\w.]+):?\s*(.*)", line)
                        if m:
                            sig = f"{p.name}::{m.group(1)}:{(m.group(2) or '')[:40]}"
                        else:
                            sig = f"{p.name}::ERROR"
                    sig_count[sig] = sig_count.get(sig, 0) + 1
    n_unique = len(sig_count)
    status = "GREEN" if err_count <= max_per else "RED"
    top = sorted(sig_count.items(), key=lambda x: -x[1])[:3]
    top_str = "; ".join(f"{k}×{v}" for k, v in top) if top else ""
    return status, f"errors {err_count} ({n_unique} unique sigs: {top_str})"


def check_log_line_cap(cfg: dict) -> tuple[str, str]:
    """10. Largest log file under max_lines."""
    max_lines = cfg.get("max_lines", 100000)
    largest = 0
    largest_path = ""
    logs_dir = HERMES_HOME / "logs"
    if logs_dir.exists():
        for p in logs_dir.rglob("*.log"):
            try:
                n = sum(1 for _ in p.open(errors="ignore"))
            except OSError:
                continue
            if n > largest:
                largest = n
                largest_path = p.name
    status = "GREEN" if largest <= max_lines else "RED"
    return status, f"log_cap {largest} lines (max {max_lines})"


def check_task_ledger_parity(cfg: dict) -> tuple[str, str]:
    """11. Two task ledgers are identical (skipped if disabled)."""
    if not cfg.get("enabled", False):
        return "SKIP", "task_ledger disabled"
    paths = cfg.get("paths", [])
    if len(paths) < 2:
        return "SKIP", "task_ledger needs ≥2 paths"
    blobs = []
    for rel in paths:
        p = HERMES_HOME / rel
        if not p.exists():
            return "RED", f"task_ledger missing: {rel}"
        try:
            blobs.append(p.read_bytes())
        except OSError:
            return "RED", f"task_ledger unreadable: {rel}"
    if blobs[0] == blobs[1]:
        return "GREEN", "task_ledger identical"
    return "RED", "task_ledger DRIFT"


def check_backup_tmp_pile(cfg: dict) -> tuple[str, str]:
    """12. Backup/tmp files count under HERMES_HOME."""
    max_files = cfg.get("max_files", 50)
    patterns = cfg.get("patterns", ["*.bak.*", "*.tmp", "*~"])
    n = 0
    if HERMES_HOME.exists():
        for pat in patterns:
            for p in HERMES_HOME.rglob(pat):
                if p.is_file():
                    n += 1
    status = "GREEN" if n <= max_files else "RED"
    return status, f"backup_tmp {n} files (max {max_files})"


def check_memory_cache_size(cfg: dict) -> tuple[str, str]:
    """13. cache/ + memory_store.db + audio_cache/ total size."""
    max_mb = cfg.get("max_mb", 200)
    targets = [
        HERMES_HOME / "cache",
        HERMES_HOME / "memory_store.db",
        HERMES_HOME / "audio_cache",
    ]
    total = 0
    for t in targets:
        if t.is_file():
            total += t.stat().st_size
        elif t.is_dir():
            for p in t.rglob("*"):
                if p.is_file():
                    total += p.stat().st_size
    total_mb = total / (1024 * 1024)
    status = "GREEN" if total_mb <= max_mb else "RED"
    return status, f"cache {total_mb:.1f}MB / {max_mb}MB"


def check_plaintext_secrets(cfg: dict) -> tuple[str, str]:
    """14. Grep for known credential shapes in non-.env paths."""
    if not cfg.get("enabled", True):
        return "SKIP", "secrets disabled"
    patterns = cfg.get("grep_patterns", [])
    exclude = cfg.get("exclude_paths", [".env"])
    hits: list[str] = []
    if HERMES_HOME.exists():
        for p in HERMES_HOME.rglob("*"):
            if not p.is_file() or p.stat().st_size > 1_000_000:
                continue
            rel = p.relative_to(HERMES_HOME).as_posix()
            if any(_glob_match(rel, ex) for ex in exclude):
                continue
            try:
                text = p.read_text(errors="ignore")
            except (OSError, UnicodeDecodeError):
                continue
            for pat in patterns:
                if re.search(pat, text):
                    hits.append(f"{rel}:{pat}")
                    break
    n = len(hits)
    status = "GREEN" if n == 0 else "RED"
    detail = "secrets none" if n == 0 else f"secrets {n} hits: {','.join(hits[:3])}"
    return status, detail


# --- Helpers --------------------------------------------------------------


def _glob_match(path: str, pattern: str) -> bool:
    """Minimal fnmatch for our exclude rules (supports ** and *)."""
    import fnmatch
    return fnmatch.fnmatch(path, pattern)


CHECKS = [
    ("1", "inject", check_inject),
    ("2", "skill_count", check_skill_count),
    ("3", "broken_symlinks", check_broken_symlinks),
    ("4", "config_exists", check_config_exists),
    ("5", "rule_frontmatter", check_rule_frontmatter),
    ("6", "json", check_json_parseable),
    ("7", "cron_alive", check_cron_alive),
    ("8", "pipeline_fresh", check_pipeline_fresh),
    ("9", "errors", check_cross_window_errors),
    ("10", "log_line_cap", check_log_line_cap),
    ("11", "task_ledger", check_task_ledger_parity),
    ("12", "backup_tmp_pile", check_backup_tmp_pile),
    ("13", "memory_cache_size", check_memory_cache_size),
    ("14", "plaintext_secrets", check_plaintext_secrets),
]


def run() -> int:
    thresholds = load_thresholds()
    output_cfg = thresholds.get("output", {})
    log_dir = HERMES_HOME / output_cfg.get("log_dir", "cron/output")
    log_dir.mkdir(parents=True, exist_ok=True)
    keep_logs = output_cfg.get("keep_logs", 12)

    lines: list[str] = []
    red_count = 0
    green_count = 0
    skip_count = 0

    for num, key, fn in CHECKS:
        cfg = thresholds.get(key, {})
        if not cfg.get("enabled", True):
            lines.append(f"[SKIP]   {num:>2}  {key} disabled")
            skip_count += 1
            continue
        try:
            status, detail = fn(cfg)
        except Exception as e:  # noqa: BLE001 — report, don't crash
            status = "ERROR"
            detail = f"{key} crashed: {type(e).__name__}: {e}"
        if status == "RED":
            red_count += 1
            tag = "[RED]"
        elif status == "ERROR":
            red_count += 1
            tag = "[ERROR]"
        elif status == "SKIP":
            skip_count += 1
            tag = "[SKIP]"
        else:
            green_count += 1
            tag = "[GREEN]"
        lines.append(f"{tag:<8}{num:>2}  {detail}")

    header = (
        f"# agent-config-metabolism — {_dt.datetime.now().isoformat(timespec='seconds')}\n"
        f"# HERMES_HOME={HERMES_HOME}\n"
        f"# {green_count} green / {red_count} red / {skip_count} skip"
    )
    report = "\n".join([header, *lines]) + "\n"

    # stdout
    sys.stdout.write(report)
    sys.stdout.flush()

    # log file
    ts = _dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")[:-3]  # ms precision avoids same-second overwrites
    log_path = log_dir / f"agent-config-metabolism-{ts}.log"
    log_path.write_text(report)

    # retention
    old_logs = sorted(log_dir.glob("agent-config-metabolism-*.log"), reverse=True)
    for old in old_logs[keep_logs:]:
        try:
            old.unlink()
        except OSError:
            pass

    # exit code: 0 green only, 1 any red, 2 all skipped
    if red_count == 0 and green_count == 0:
        return 2
    return 1 if red_count > 0 else 0


if __name__ == "__main__":
    sys.exit(run())