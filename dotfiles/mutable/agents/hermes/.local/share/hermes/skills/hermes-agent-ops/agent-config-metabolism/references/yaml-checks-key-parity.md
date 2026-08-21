# YAML ↔ CHECKS key parity — the silent empty-cfg bug

## The bug

When a Python script uses a tuple like `CHECKS = [("9", "errors", check_cross_window_errors), ...]` and dispatches via `cfg = thresholds.get(key, {})`, **the `key` string is the contract**. If your `metabolism_thresholds.yaml` section is named `cross_window_errors:` but the CHECKS tuple says `("9", "errors", ...)`, the check receives `cfg = {}`, every `.get("max_per_day", 5)` falls back to the function's hard-coded default, and the script emits `[GREEN]` based on the default — not your configured threshold.

This is silent. No exception. No warning. The script runs perfectly and reports nonsense.

## Real-world hit (2026-07-06)

A freshly-written `metabolism_check.py` shipped with **6 mismatches** that all looked GREEN at first run:

| CHECKS key | yaml key | Symptom |
|---|---|---|
| `symlinks` | `broken_symlinks` | always GREEN (default max=0 matches the env) |
| `frontmatter` | `rule_frontmatter` | always GREEN (no required_fields → empty filter) |
| `log_cap` | `log_line_cap` | GREEN by luck |
| `backup_tmp` | `backup_tmp_pile` | GREEN by luck |
| `cache_size` | `memory_cache_size` | GREEN by luck |
| `secrets` | `plaintext_secrets` | GREEN by luck (default max=0) |

3 other mismatches (`json_parseable`, `cross_window_errors`, `task_ledger_parity`) actually went **RED with bogus detail** because the defaults didn't match env state — that's how the bug was first noticed.

## The one-liner parity check

Run this AFTER editing either `CHECKS = [...]` in the script or the top-level sections of the threshold yaml:

```bash
python3 -c "
import re, sys
src = open('$HERMES_HOME/skills/hermes-agent-ops/agent-config-metabolism/scripts/metabolism_check.py').read()
check_keys = set(re.findall(r'^\s*\(\"(\d+)\",\s*\"([a-z_]+)\",\s*\w+\),', src, re.M))
yaml_keys = set()
for line in open('$HERMES_HOME/skills/hermes-agent-ops/agent-config-metabolism/scripts/metabolism_thresholds.yaml'):
    m = re.match(r'^([a-z_]+):\s*\$', line)
    if m and not line.startswith(' '): yaml_keys.add(m.group(1))
yaml_keys -= {'output'}
check_only = {k for _, k in check_keys}
yaml_only = yaml_keys - check_only
missing_in_yaml = check_only - yaml_keys
print('CHECKS not in yaml:', missing_in_yaml or '(none)')
print('yaml not in CHECKS:', yaml_only or '(none)')
sys.exit(1 if missing_in_yaml else 0)
"
```

Expected output: `CHECKS not in yaml: (none)` / `yaml not in CHECKS: (none)`. Exit code 0.

## Naming convention

Pick ONE side as the canonical name source and stick to it. Two safe conventions:

1. **CHECKS is canonical** (recommended for short-lived scripts): when adding a new check, write the CHECKS tuple first, then copy that string as the yaml section name verbatim. One rename = one place.
2. **yaml is canonical** (recommended for long-lived scripts users tune): write yaml first with semantic names (`memory_cache_size` > `cache_size`), then align CHECKS tuples to match.

This skill follows convention 2 because users edit `metabolism_thresholds.yaml` to tune thresholds; renaming a yaml section shouldn't break the script.

## Pattern (don't reinvent)

Any time you write a config-driven dispatcher — list of `(name, key, function)` tuples reading from yaml/json/toml — encode the parity check as a **verification step**, not a runtime assert. Runtime asserts are good, but a one-liner you run after editing either side catches drift before the next cron tick fires.