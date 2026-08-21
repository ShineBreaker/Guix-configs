# Parser bugs found 2026-08-02 — agent-config-metabolism audit

Session: autonomous weekly audit of `metabolism_check.py` (14 checks).
Symptom: `6 green / 7 red / 1 skip` with seven `[ERROR]` lines, all the same
`TypeError: '<=' not supported between instances of 'float' and 'str'`, plus a
final crash `slice indices must be integers` on `old_logs[keep_logs:]`.

Root cause chain (ONE loader bug, seven visible crashes):

## 1. Fallback YAML loader could not parse its own config file

PyYAML is not installed → `load_thresholds()` fell back to `_yaml_fallback`.
Three dialect gaps:

| Gap | Symptom |
|-----|---------|
| Inline comments not stripped: `max_kb: 30 # comment` → `"30 # comment"` (str) | every numeric comparison crashes `'<=' between float/int and str`; `keep_logs` str breaks list slicing |
| Flow lists not parsed: `[name, description]` → plain string | `for f in required` iterates CHARACTERS → every SKILL.md reported missing fields → fake RED "62 bad" (ground truth: 0) |
| Block lists not parsed: `patterns:` + `- item` → empty `{}` | check that reads `patterns` silently matches nothing → permanent fake GREEN (monitor not monitoring) |

Diagnostic shortcut: when an audit collapses into mass TypeErrors, probe the
loader FIRST:

```bash
python3 -c "
import importlib.util
spec = importlib.util.spec_from_file_location('m', '.../metabolism_check.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cfg = m.load_thresholds()
print(cfg['inject'])   # {'enabled': True, 'max_kb': '30                # comment'} ← str!
"
```

Fixed parser requirements (now in metabolism_check.py):
- `_strip_comment(val)`: strip ` #...` outside quotes (`#` at line start or
  after whitespace only — YAML rule)
- flow list: `[a, b]` → `[_coerce(x) for x in inner.split(",")]`
- block list: `key:` empty block converts to list on first `- item`; sibling
  items must NOT pop the list container (`while stack[-1][0] > indent` for
  items, `>=` for keys)
- compact form `key:` / `- item` at the same indent must work too

## 2. fnmatch excludes anchored at pattern start

`exclude_paths` had `references/**`; `_glob_match` is `fnmatch.fnmatch`, whose
`*` matches `/` but the pattern is anchored at the path START. Nested path
`hermes-agent/skills/.../hermes-agent/references/native-mcp.md` did NOT match
`references/**` → doc placeholder `sk-xxx...xxxx` flagged as plaintext secret
(1 hit/week for weeks). Fix: `**/references/**`, `**/node_modules/**` — any
pattern matching at arbitrary depth needs the leading `**/`.
(Note: `**/venv/**` worked all along because its `*` eats the prefix.)

## 3. Check 9 counted all history, not a window

`max_per_day: 5` but the implementation scanned the ENTIRE logs (2 weeks of
retention) → 54 unique signatures of which ~50 were mirrors of 2 long-lived
EXTERNAL failures (weixin iLink connect, QQ bot token fetch — upstream, not
config). The check could never turn green even if both were fixed today, until
the logs rotated. Fix:
- `window_days: 7` (yaml) — parse per-line timestamps `YYYY-MM-DD HH:MM:SS`;
  untimestamped lines (Traceback blocks) inherit the previous line's
- retry normalization `re.sub(r"\(\d/(\d+)\)", r"(n/\1)", msg)` — three
  retries of one connection failure are one signature
- classification discipline: weixin poll 1/3+2/3+3/3 ×3 log files = 1 root
  cause mirrored, not 9 problems. Cross-file mirroring is the next level of
  normalization if 45 sigs still exceeds threshold.

## 4. Fixture-format lesson (verification methodology)

First version of the regression probe FAILED one assertion: `OldError` (an
out-of-window traceback) was counted. Root cause: the fixture gave traceback
lines a timestamp and placed an in-window ERROR line before an out-of-window
traceback — a timestamp mismatch that cannot occur in real logs (tracebacks
carry no timestamp and inherit the previous line's). The script was correct;
the fixture lied. Rule: build synthetic logs from a REAL sample, and when a
probe fails, check the fixture's format assumptions before the code.

## Reusable regression probe (v2, all-pass)

Saved pattern — tempfile-isolated HERMES_HOME + synthetic logs, exit 0 = pass.
The probe covers: fallback parser (inline comments, flow/block lists, nested
dicts), check-9 window + normalization + traceback state machine, threshold
type loading, fnmatch nested excludes. Full source was verified 15/15 on
2026-08-02; re-derive from this recipe or keep a copy under
`scripts/verify_core.py` next to the audited script.

Key skeleton:

```python
tmp = tempfile.mkdtemp(prefix="hermes-verify-")
os.environ["HERMES_HOME"] = tmp          # BEFORE importing the module
m = ...import metabolism_check.py...
cfg = m._yaml_fallback("""...full dialect sample...""")
assert cfg["inject"]["max_kb"] == 32     # inline comment stripped to int
assert cfg["rule_frontmatter"]["required_fields"] == ["name", "description"]
(logs / "test.log").write_text(synthetic_log)   # tracebacks WITHOUT timestamps
status, detail = m.check_cross_window_errors({"max_per_day": 5, "window_days": 7,
                                              "log_globs": ["logs/*.log"]})
assert "4 unique sigs" in detail         # weixin(n/3) + qqbot + bare + traceback
shutil.rmtree(tmp)
```
