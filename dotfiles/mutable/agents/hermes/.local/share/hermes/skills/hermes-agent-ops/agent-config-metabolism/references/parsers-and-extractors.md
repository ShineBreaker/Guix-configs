# Parsers & Extractors — reusable Python patterns

Two techniques emerged during this skill's audit. Both are domain-general; reuse them next time you write a parser that needs to be lenient without going full regex-monster.

## 1. JSONC parser (trailing commas + `//` line comments)

**Problem.** TypeScript's `tsconfig.json` and VSCode's `tsdoc-metadata.json` use JSONC (`//` comments, trailing commas). Stock `json.loads` rejects both. Naive fix is to skip `lsp/**` paths — but that hides real signal.

**Solution.** Lenient parse with two passes — strip comments (state-machine to avoid breaking strings), then strip trailing commas.

```python
import json
import re


def _parse_json_lenient(text: str) -> tuple[bool, str]:
    """Parse JSON or JSONC. Returns (ok, error_msg)."""
    # 1. Strip // line comments, but only outside strings.
    out_lines = []
    for line in text.split("\n"):
        cleaned, in_str, esc = [], False, False
        for i, ch in enumerate(line):
            if esc:
                cleaned.append(ch); esc = False
            elif ch == "\\":
                cleaned.append(ch); esc = True
            elif ch == '"':
                in_str = not in_str; cleaned.append(ch)
            elif not in_str and i + 1 < len(line) and line[i:i+2] == "//":
                break
            else:
                cleaned.append(ch)
        out_lines.append("".join(cleaned))
    cleaned = "\n".join(out_lines)
    # 2. Strip trailing commas in objects/arrays.
    cleaned = re.sub(r",(\s*[\]}])", r"\1", cleaned)
    try:
        json.loads(cleaned)
        return True, ""
    except (json.JSONDecodeError, ValueError) as e:
        return False, f"{type(e).__name__}: {e}"
```

**Verification.** Fixture in `scripts/metabolism_check.py::check_json_parseable`: standard JSON, JSONC with `//` + trailing comma, and a genuinely broken file. All three classify correctly (1 pass, 1 pass, 1 fail).

## 2. Traceback tail-extraction per block (for log scanning)

**Problem.** A log line `"Traceback (most recent call last):"` carries no signal — the real type lives at the column-0 tail line (`ImportError: cannot import name 'jobs' from 'cron' (...)`). Naively grouping by `"Traceback"` collapses every different failure mode into one signature → you can't tell "1 cron import error ×2626" from "many distinct problems".

**Solution.** Pre-walk the text per-block to map each Traceback's absolute offset to its tail exception type. Then when classifying a `Traceback` line during the main scan, look up the nearest preceding block.

```python
import re

tail_by_offset: dict[int, str] = {}
tb_re = re.compile(
    r"Traceback \(most recent call last\):.*?(?=\nTraceback|\Z)",
    re.S,
)
for m in tb_re.finditer(text):
    block_lines = m.group(0).strip().split("\n")
    last_line = block_lines[-1].strip()
    em = re.match(
        r"^([\w.]+(?:Error|Exception|Warning|Failure|Interrupt))",
        last_line,
    )
    tail_by_offset[m.start()] = em.group(1) if em else "Exception"

# Main scan: for each line containing Traceback, find its block's tail.
for line_offset, line in enumerate_lines_with_offset(text):
    if "Traceback" in line:
        tail = "Traceback"
        for tb_pos in sorted(tail_by_offset):
            if tb_pos <= line_offset:
                tail = tail_by_offset[tb_pos]
            else:
                break
        sig = f"{log_name}::{tail}"
```

**Gotcha #1.** The naive `block.strip().split("\n")[-1]` is wrong when the next log line happens to also contain "ERROR" (e.g. python's logger writes the traceback, then immediately writes `2026-... ERROR mod: msg` — the last "line" of `split("\n")` is the next ERROR log, not the traceback tail). **The regex above with the indented-frame match `[ \t].*\n*` is safer.**

**Gotcha #2.** Catastrophic backtracking: `(?:[ \t].*\n)*([\w.]+(?:Error|Exception)...)*` looked correct but timed out on a 64KB log file. The line-by-line walk above is O(n) and never backtracks.

**Verification.** Fixture: two tracebacks in the same log file with different exception types. Confirm each gets a distinct signature (`a.log::ImportError×1`, `a.log::ModuleNotFoundError×1`) and that no `::Traceback×N` bare signature appears.

## 3. YAML key ↔ CHECKS key parity check (silent failure mode)

**Problem.** The script's `run()` dispatches checks via `thresholds.get(key, {})` where `key` comes from a CHECKS tuple. If a yaml section is named `backup_tmp_pile` but CHECKS says `"backup_tmp"`, the check runs on **empty cfg** and silently uses function defaults. Result: green even when the real threshold isn't loaded. This is the **classic "monitor not monitored" failure mode** this skill exists to catch — *in the monitor itself*.

**Solution.** One-liner guard for any yaml-driven config dispatcher:

```python
import re
src = open("metabolism_check.py").read()
check_keys = set(re.findall(r'^\s*\("(\d+)",\s*"([a-z_]+)",\s*\w+\),', src, re.M))
yaml_keys = set(re.findall(r"^([a-z_]+):\s*$", open("metabolism_thresholds.yaml").read(), re.M))
yaml_keys -= {"output"}  # skip non-check sections
assert check_keys <= yaml_keys, f"CHECKS keys missing from yaml: {check_keys - yaml_keys}"
```

**Failure mode.** This bug shipped once in this skill: 6 of 14 checks (`symlinks`, `cache_size`, `log_cap`, `frontmatter`, `backup_tmp`, `secrets`) ran on empty cfg for the entire development cycle because the yaml was renamed while CHECKS wasn't. Both sides looked green; only manual cross-validation caught it. **The fix is to align one side or the other — prefer aligning CHECKS to the yaml (yaml is user-editable; CHECKS is internal).**

## 4. Cross-validation probes (Step 4 of SKILL.md Procedure)

The cheapest way to know whether the script's number is real: ask the same question with an independent shell pipeline. Three proven cross-checks (Python snippets, all under 10 lines):

- **Inject size** — sum real description field bytes, not whole files. (See `references/parsers-and-extractors.md` §1 for the regex.)
- **Error count** — count unique traceback exception TYPES (not lines), then compare to the script's "N unique sigs" output.
- **Broken JSON** — list actual file paths (not just count). The script's `bad.append((rel, err))` format already shows paths; the cross-check is to rerun with `find -name '*.json' | xargs python3 -c ...` and diff.

If script vs. cross-check differs by more than ±10%, the script has a bug — **patch the script before reporting any reds to the user**. Reporting a wrong number destroys user trust in the entire monitor faster than any single false positive.