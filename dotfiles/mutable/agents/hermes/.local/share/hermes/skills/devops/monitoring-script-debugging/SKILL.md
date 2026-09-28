---
name: monitoring-script-debugging
description: "Debug monitoring scripts that produce false RED/GREEN signals. Covers parser bugs, counting pitfalls, and cross-validation patterns for audit/healthcheck scripts."
version: 0.1.0
author: Hermes
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [monitoring, debugging, parser, audit, healthcheck, false-positive]
    related_skills: [agent-config-metabolism, diagnosing-bugs]
---

# Monitoring Script Debugging

Debug monitoring/audit scripts that produce false RED or false GREEN signals. The core principle: **the first run of a script that touches unfamiliar data is suspect until cross-validated**.

## When to Use

- An audit script reports a number that "feels wrong" (too high, too low, or contradicts intuition)
- A healthcheck flips between RED and GREEN without any real config change
- You're writing a parser that needs to be lenient (JSONC, log files, config files)
- You're counting errors/signals and need to decide: per-line vs per-event, total vs unique

## The Three Failure Modes

### 1. Parser Corruption (False RED)

A lenient parser that strips comments or normalizes input accidentally destroys valid data.

**JSONC block comment regex eats `/*` inside strings:**
```python
# BROKEN: regex matches /* inside JSON strings
text_no_block = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)

# FIX: string-aware block comment stripping
out_chars = []
i = 0
in_str = False
esc = False
while i < len(text):
    ch = text[i]
    if esc:
        out_chars.append(ch)
        esc = False
    elif ch == "\\" and in_str:
        out_chars.append(ch)
        esc = True
    elif ch == '"':
        in_str = not in_str
        out_chars.append(ch)
    elif not in_str and ch == "/" and i + 1 < len(text) and text[i + 1] == "*":
        i += 2
        while i < len(text) - 1:
            if text[i] == "*" and text[i + 1] == "/":
                i += 2
                break
            i += 1
        else:
            i = len(text)
        continue
    else:
        out_chars.append(ch)
    i += 1
text_no_block = "".join(out_chars)
```

**Lenient parser must not run before standard parser:**
```python
# BROKEN: lenient parser strips // inside valid JSON strings (e.g., https://)
ok, err = _parse_json_lenient(text)

# FIX: try standard first, fall back to lenient
try:
    json.loads(text)
    # Valid standard JSON — done
except (json.JSONDecodeError, ValueError):
    ok, err = _parse_json_lenient(text)
```

**Trailing comma regex `r",(\s*[\\]}])"` is broken:**
```python
# BROKEN: [\\]}] matches \, ], or } — not ] or }
cleaned = re.sub(r",(\s*[\\]}])", r"\1", cleaned)

# FIX: use []}] to match ] or }
cleaned = re.sub(r",(\s*[]}])", r"\1", cleaned)
```

### 2. Counting Pitfalls (False RED)

Counting the wrong thing inflates or deflates the signal.

**Per-line vs per-event:**
```python
# BROKEN: counts every frame line in a traceback as a separate error
for line in text.splitlines():
    if "Traceback" in line:
        err_count += 1

# FIX: count each traceback block once
tb_offsets_seen: set[int] = set()
for line in text.splitlines(keepends=True):
    if "Traceback" in line:
        for tb_pos in sorted(tail_by_offset):
            if tb_pos <= line_start and tb_pos not in tb_offsets_seen:
                tb_offsets_seen.add(tb_pos)
                err_count += 1
                break
```

**Total vs unique:**
```python
# BROKEN: threshold compares against total lines
status = "GREEN" if err_count <= max_per else "RED"

# FIX: threshold compares against unique signatures
status = "GREEN" if n_unique <= max_per else "RED"
```

**All-history vs rolling window:** a check named `max_per_day` that scans the
ENTIRE log (weeks of history) stays permanently RED on long-lived external
failures — the root cause never ages out, so the light never turns green even
after it's fixed. A permanently-red light is a fake red: it trains everyone to
ignore the report. Fix: count only lines inside a rolling window
(`window_days`, default 7) by parsing the per-line timestamp; untimestamped
lines (traceback blocks) inherit the previous line's. Normalize retry counters
`(1/3)(2/3)(3/3)` → `(n/3)`: three retries of one failure are one problem.

### 3. Silent False GREEN (Monitor Not Monitoring)

The script runs but the threshold isn't loaded, or the check is skipped entirely.

**YAML key ↔ CHECKS key drift:**
```python
# If yaml has "backup_tmp_pile" but CHECKS has "backup_tmp",
# the check runs on empty cfg and silently uses defaults.
# Guard:
assert check_keys <= yaml_keys, f"Missing: {check_keys - yaml_keys}"
```

**Fallback config parser produces wrong types:** a no-PyYAML fallback that
doesn't strip inline comments turns `max_kb: 30 # comment` into the STRING
`"30 # comment"` — every numeric comparison then crashes with `'<=' not
supported between instances of 'float' and 'str'`. Two silent variants are
worse: a `key:` block followed by `- item` lines stays an empty `{}`, so the
check reading `patterns` is a permanent fake GREEN; and a flow list
`[name, description]` degrades to a plain string, so `for f in required_fields`
iterates CHARACTERS and flags every file as invalid (a "62 bad" that is really
0). Rule: a fallback loader must handle the FULL config dialect — inline
comments, flow lists, block lists (indented AND compact `key:`/`- item` at the
same indent) — or it becomes the source of both false REDs and false GREENS.

**fnmatch excludes are anchored at the start:** `references/**` only matches
paths *beginning* with `references/`. Nested `.../hermes-agent/references/
native-mcp.md` is NOT excluded, so doc placeholders (`sk-xxx`) keep showing up
as secret hits. Any pattern that must match at any depth needs a leading `**/`:
`**/references/**`, `**/node_modules/**`.

### 4. Shell Safety Checks That Never Fire (Silent False GREEN in bash)

Same disease as the YAML drift above, in bash — and `set -euo pipefail` makes
it systematic, because a **failing predicate silently becomes "condition not
met"** rather than an error.

**`find | grep -q` under `pipefail` inverts the answer.** `grep -q` exits on
first match, `find` gets SIGPIPE (rc 141), `pipefail` propagates it, so the whole
pipeline reads as false even when matches exist:

```bash
# ❌ always false — active dirs read as "no recent writes"
if [ -d "$d" ] && find "$d" -type f -mtime -7 2>/dev/null | grep -q .; then
  echo "active"
fi

# ✅ no pipe, find stops itself
active_recent() { [ -d "$1" ] && [ -n "$(find "$1" -type f -mtime -7 -print -quit 2>/dev/null)" ]; }
```

The damage is worst in deletion/cleanup scripts: the check is the *only* thing
standing between a bug and deleted live data.

**`find -newermt "-7 days"` means "older than 7 days"** — the opposite of what
you want for an activity test. Use `-mtime -7`.

**Directory mtime ≠ activity.** `stat -c %y <dir>` only reflects child
add/remove, never in-place rewrites. A dir written daily can show a mtime weeks
old. Only `find <dir> -type f -mtime -N` answers "is this still in use".

**Rule: a destructive script's guard must be exercised, not just written.** A
safety check that has never printed its "blocked" branch is unverified. Run the
predicate standalone against a directory you KNOW is active and confirm it
returns true — `bash -c '...'` with the exact function, not a read-through.
Repeat the run 2-3× to rule out a race; a check that only sometimes fires is
also broken. `scripts/verify-active-recent.sh` is that probe.

## Cross-Validation Pattern

Before trusting any number from a monitoring script, ask the same question with an independent shell pipeline:

```bash
# Count unique error types (not lines)
grep -h "Traceback\|ERROR" logs/*.log | \
  python3 -c "
import sys, re, collections
c = collections.Counter()
for line in sys.stdin:
    m = re.search(r'\b\w+(?:Error|Exception)\b', line)
    if m: c[m.group(0)] += 1
for k, v in c.most_common(10): print(f'  {v:>5}  {k}')
print(f'Total unique: {len(c)}')
"

# List broken JSON files (not just count)
python3 -c "
import json, pathlib
home = pathlib.Path('/home/brokenshine/.local/share/hermes')
for p in home.rglob('*.json'):
    if any(s in p.as_posix() for s in ('node_modules', '.venv', 'lsp/', 'Trash/')): continue
    try: json.loads(p.read_text(errors='ignore'))
    except Exception as e: print(f'BROKEN: {p.relative_to(home)}  [{type(e).__name__}]')
"
```

If script vs cross-check differs by more than ±10%, the script has a bug — **patch the script before reporting any reds to the user**.

## Pitfalls

- **Don't add excludes to silence real signal.** If a parser fails on valid data, fix the parser. Excludes are how problems get pushed "to later" until they rot.
- **Don't raise thresholds without justification.** If 23 unique errors is normal for your setup, document why the threshold is 25 — don't just set it to 1000.
- **Test parsers on real data, not just fixtures.** The block comment bug only appeared on `tsconfig.json` files with `"paths": {"@/*": [...]}` — a pattern not in any test fixture.
- **Regex character classes are treacherous.** `[\\]}]` is not the same as `[}]`. Always test regex patterns on edge cases (escaped chars, empty strings, unicode).
- **Config loaders are the first suspect on mass TypeErrors.** Seven checks crashing with the same `'<=' not supported between instances of X and str'` is ONE loader bug (values came through as strings), not seven check bugs. Probe the loader output (`python3 -c "import importlib.util; ...; print(cfg)"`) before touching any check logic.
- **Synthetic fixtures must mirror the real data format.** A regression probe that gives traceback lines a timestamp — when real logs have none — fails with a "bug" that is actually a test-fixture bug. Tracebacks inherit the previous line's timestamp. Build fixtures from a real log sample, not from what the code "should" look like; a fixture that passes against real logs but fails synthetic ones is a fixture bug.
- **Regression probes belong in the skill.** After fixing parser/counter bugs, save the probe as `scripts/verify_*.py` under the skill (tempfile-isolated HOME + synthetic data, exit 0 = pass) so the next session re-runs it instead of re-deriving it. A verification script that was hand-typed once and deleted is a lesson that evaporates.
- **Destructive guards get verified against a known-positive input, not an empty one.** A cleanup script tested only on "everything is clean" passes while its guard is inverted. Always run the predicate against a fixture that MUST trip it.
- **A script that deletes is a script that must default to not running.** Ship dry-run-by-default with an explicit opt-in flag, and route deletion through a recoverable sink (`trash-put`, not `rm`). The plan is the artifact the user reviews; the flag is the decision point.

## References

- `references/parser-bugs-2026-07-26.md` — real bugs found during agent-config-metabolism audit
- `references/parser-bugs-2026-08-02.md` — fallback-YAML dialect bugs, fnmatch anchoring, rolling-window fix, fixture-format lesson (agent-config-metabolism audit)
- `scripts/verify-active-recent.sh` — regression probe for the bash activity guard (`find -mtime` vs `find | grep -q` under pipefail); run before trusting any cleanup/migration script's exclusion logic