---
name: agent-config-metabolism
description: "Weekly 14-check red/green audit of agent config bloat. Diagnoses inject size, zombie skills, state drift, monitor honesty, log bloat, secret leaks."
version: 0.3.0
author: Hermes
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [config-audit, agent-hygiene, weekly-check, red-green, monitoring]
    related_skills: [hermes-skill-curation, hermes-memory-routing, skill-authoring]
---

# Agent Config Metabolism

A **14-check weekly audit** that catches the three structural failure modes of any long-lived agent setup: *document-production cost < cleanup cost*, *duplicate state that drifts*, *monitors that monitor themselves*. The principle: **machines check facts, humans only see red**.

This is **not** a one-shot cleanup — it's a recurring healthcheck. The cron job (Sunday morning) runs `scripts/metabolism_check.py`; results land in `output/`. You only need to look when something is red.

## User Preferences (load these first)

Two user-stated principles that govern every interaction with this skill — captured after explicit corrections during the originating session.

### 1. Report first, ask before acting — **never execute fixes without approval**

When the audit surfaces red signals, **the deliverable is a detailed inspection report, not an auto-fix**. The agent's job:

- Surface every red with: *which file / which line / what's the real signal behind the number*
- Cross-validate each red against ground truth (independent shell pipeline) — never trust the script's first number
- Present the report with **decision options** (e.g. "trim description? raise threshold? investigate upstream?") and **stop**
- Wait for explicit user approval before touching any file

Trigger phrases that must switch to report-only mode:
- "你看看本次检查暴露出来了什么问题" (literally: "look at what the audit exposed" — implies report, not action)
- "向我汇报" / "report to me" / "find out what's wrong"
- "审核" / "review" (without explicit fix instruction)

When in doubt, default to **report mode**. Fixing on autopilot violates the user's "low-frequency but critical" preference that any autonomous-mode claim ("自主完成所有任务" / "你去休息") requires explicit opt-in first.

### 2. **Solve the root cause directly — never hide problems behind excludes or threshold-raising**

When a red turns out to be a real signal (not noise), the right response is to make the script **recognize the real situation**, not to suppress it. Concrete prohibitions:

- ❌ **Never add `exclude:` patterns** to silence a legitimate finding. `lsp/**`, `cache/**`, `node_modules/**`, or per-log-file excludes are how problems get pushed "to later" until they rot.
- ❌ **Never raise the threshold** to make a red turn green without explaining why the new number is the right one. Threshold-tuning is for genuine noise; hiding real signal is lying to yourself.
- ✅ **Extend the parser** to handle the legitimate case. Examples:
  - JSON files with `//` comments or trailing commas are **JSONC** (TypeScript/VSCode dialect) → write a lenient parser, don't exclude `lsp/**`
  - Log lines that contain "Traceback" but no recognizable error type → extract the column-0 exception tail per-block, don't blanket-exclude the log file
  - Cron poll errors that spam the log every 30s → fix the upstream import collision or rate-limit the endpoint, don't reduce log scan frequency

The "monitor monitors itself" failure mode from the original post predicts this exact drift: a script that "goes green" by ignoring real problems is the original sin this skill exists to catch. **If you find yourself adding an exclude, you're probably building a worse monitor.**

## When to Use

- "我的 agent 配置膨胀了" / "技能太多不知道哪些是僵尸"
- "周检 / 体检 / 配置代谢 / 红绿灯检查"
- "注入体积 / 重复规则 / 状态漂移 / 监控说谎"
- "187 个 skill 太多，想找哪些是真的在用"
- "AI 用久了变笨" — usually a symptom of bloated config, not the model
- "每周日自动跑配置检查"

## Prerequisites

- `$HERMES_HOME` set (defaults to `~/.local/share/hermes`)
- Standard Unix tools: `find`, `du`, `wc`, `stat`, `jq`, `python3`
- Triggers via `cronjob` tool (no external deps)

## How to Run

The canonical invocation through Hermes:

```python
# One-shot (interactive)
terminal(command="python3 $HERMES_HOME/skills/hermes-agent-ops/agent-config-metabolism/scripts/metabolism_check.py")

# Weekly cron (Sunday 09:00, no_agent=True — script IS the job)
cronjob(
    action="create",
    schedule="0 9 * * 0",
    name="agent-config-metabolism-weekly",
    prompt="",  # ignored when script+no_agent set
    script="skills/hermes-agent-ops/agent-config-metabolism/scripts/metabolism_check.py",
    no_agent=True,
    deliver="origin",
)
```

Or directly via shell:

```bash
python3 ~/.local/share/hermes/skills/hermes-agent-ops/agent-config-metabolism/scripts/metabolism_check.py
```

## Quick Reference

| Check | Threshold | File / source |
|-------|-----------|---------------|
| 1. Inject size | ≤ 25KB | sum of `description` field bytes + memory files |
| 2. Skill count | ≤ 160 | `find $HERMES_HOME/skills -name SKILL.md \| wc -l` |
| 3. Broken symlinks | 0 | `find $HERMES_HOME -xtype l` |
| 4. Config exists | all present | `config.yaml`, `.env`, `auth.json` |
| 5. Rule frontmatter | valid | every `SKILL.md`/`AGENTS.md` |
| 6. JSON parseable | all | `*.json` under `$HERMES_HOME` (with excludes) |
| 7. Cron alive | timestamp < 7d | `cron/jobs.json` + tick log |
| 8. Data pipeline fresh | < 24h | last session_ts vs now |
| 9. Cross-window errors | < 5/day | `logs/*.log` grouped by signature |
| 10. Log line cap | < 100k lines | each log file |
| 11. Task ledger parity | identical | kanban vs todo-store |
| 12. Backup/tmp pile | < 50 | `*.bak.*` + tmpfiles |
| 13. Memory cache size | ≤ budget | `cache/` + `memory_store.db` |
| 14. Plaintext secrets | 0 | grep `aws_\|sk-\|ghp_\|xoxb-` |

## Procedure

### Step 1: Run the script

```bash
python3 $HERMES_HOME/skills/hermes-agent-ops/agent-config-metabolism/scripts/metabolism_check.py
```

Output goes to stdout (red/green summary) AND `$HERMES_HOME/cron/output/agent-config-metabolism-<timestamp>.log`.

### Step 2: Read only the reds

The script returns a 14-line summary like:

```
[GREEN] 1  inject 12.3KB / 25KB
[RED]   2  skill_count 187 / 160  ← investigate
[GREEN] 3  symlinks 0
...
```

Each red is a concrete signal. The script does NOT auto-fix anything (cleanups are dangerous; humans should review).

### Step 3: Diagnose reds via the linked skill

| Red on check #... | Likely cause | Skill |
|----|----|----|
| 1 (inject too big) | duplicate rules injected twice | `hermes-skill-curation` §2 |
| 2 (skill count) | zombie skills from past imports | `hermes-skill-curation` §2 |
| 3 (broken symlinks) | dotfile source moved | `guix-configs-workflow` |
| 7 (cron not alive) | daemon died | `hermes-agent` §Durable |
| 14 (plaintext secret) | leaked credential | rotate immediately |

### Step 4: Cross-validate the script's claims against ground truth

**Before trusting any red/green, independently probe one claim** with a separate shell pipeline. The first run of a script that touches unfamiliar data is suspect until cross-validated. Three cheap cross-checks:

```bash
# Validate inject-size claim — sum real description fields, not whole files
python3 -c "
import re, pathlib
total = 0
for p in pathlib.Path('/home/brokenshine/.local/share/hermes/skills').rglob('SKILL.md'):
    head = p.read_text(errors='ignore')[:4096]
    if not head.startswith('---'): continue
    fm_end = head.find('\n---', 3)
    if fm_end < 0: fm_end = len(head)
    m = re.search(r'^description\s*:\s*(.*?)(?=\n[a-zA-Z_][\w-]*\s*:|\Z)', head[3:fm_end], re.M|re.S)
    if m:
        d = m.group(1).strip().strip('\"').strip(\"'\")
        total += len(d.encode())
print(f'{total} bytes ({total/1024:.1f} KB)')
"

# Validate error-count claim — count unique traceback exception TYPES (not lines)
grep -h "Traceback" ~/.local/share/hermes/logs/*.log 2>/dev/null | \
  python3 -c "
import sys, re, collections
c = collections.Counter()
for line in sys.stdin:
    m = re.search(r'\b\w+(?:Error|Exception)\b', line)
    if m: c[m.group(0)] += 1
for k, v in c.most_common(10): print(f'  {v:>5}  {k}')"

# Validate broken-JSON claim — see actual file paths
python3 -c "
import json, pathlib
home = pathlib.Path('/home/brokenshine/.local/share/hermes')
for p in home.rglob('*.json'):
    if any(s in p.as_posix() for s in ('node_modules', '.venv', 'lsp/', 'Trash/')): continue
    try: json.loads(p.read_text(errors='ignore'))
    except Exception as e: print(f'BROKEN: {p.relative_to(home)}  [{type(e).__name__}]')"
```

If the script's number disagrees with these by more than ±10%, the script has a bug — patch it before reporting reds to the user.

### Step 5: Schedule via cron

Use `cronjob(action='create', ...)` with the script and `no_agent=True` (so the script IS the job — no LLM tokens burned on a watchdog that just prints status).

```python
cronjob(
    action="create",
    schedule="0 9 * * 0",
    name="agent-config-metabolism-weekly",
    script="skills/hermes-agent-ops/agent-config-metabolism/scripts/metabolism_check.py",
    no_agent=True,
    deliver="origin",          # user preference — same as jeans-issue-fixer
                                # sends results to current chat (QQ).
                                # Other options: "telegram", "discord", "slack",
                                # "all", or a specific platform:chat_id:thread_id
)
```

To change delivery later: `cronjob(action='update', job_id='<id>', deliver='local')`.

## Pitfalls

- **Don't auto-fix on red.** The script outputs a report, not a cleanup. Red means "investigate", not "delete". `hermes-skill-curation` handles actual cleanup.
- **Thresholds are personal.** The script reads thresholds from a config file (`scripts/metabolism_thresholds.yaml`); adjust to your setup. 25KB inject / 160 skills are starting points, not universal truths.
- **Check 11 (task ledger parity) requires kanban enabled.** If you don't use kanban, skip that check (set `enabled: false` in thresholds).
- **Check 14 (plaintext secrets) is heuristic.** It greps for `sk-`, `aws_`, `ghp_`, `xoxb-`, `Bearer ` — these can false-positive on test fixtures. Review before rotating.
- **Cron sessions pass `skip_memory=True`.** Results don't pollute your main memory.
- **Self-update blindness.** If you set thresholds too loose, you'll see all-green while bloat grows. Tighten thresholds quarterly.
- **YAML key names MUST match the CHECKS list keys.** The script dispatches via `thresholds.get(key, {})` where `key` comes from the CHECKS tuple. If your yaml section is named `backup_tmp_pile` but CHECKS says `"backup_tmp"`, the check runs on **empty cfg** and silently falls back to function defaults — you'll see GREEN when the real threshold isn't loaded. Always grep CHECKS keys against yaml top-level keys after editing either side (see `references/yaml-checks-key-parity.md`).
- **Don't trust injected-size estimates.** Real inject is `sum(description field bytes)`, NOT `sum(SKILL.md file bytes) ÷ 5` (that's a ~7× over-estimate). When reading SKILL.md frontmatter, read **at least 4 KB** (not 600 bytes) — the 600-byte truncation silently broke 2 SKILL.md in this user's setup whose descriptions were 700-18000 bytes.
- **Don't trust raw error counts.** A literal grep `ERROR\|Traceback` over all logs surfaces N independent problems when in reality it's 1 repeating failure (the same cron import error ×2626 looks like 2626 issues but is one root cause). **Group by `(file:module:msg_prefix)` signature** before comparing to threshold — the metabolic signal is "how many unique problems", not "how many log lines".
- **Never `read_text()[:N]` then `write_text()` to modify a single field.** This silently truncates files whose content exceeds the slice. During the originating session, this exact pattern wiped the body of 3 SKILL.md files (emacs-config-debugging 19.6KB → 477 bytes, narrated-video-alignment 13.3KB → 590 bytes, guix-configs-workflow 51.5KB → 10.3KB) — all because the patch_desc helper sliced `[:800]` to find the `description:` line and then wrote back only the head. **Correct pattern for single-field edits**: use `patch_file` (or `patch()` tool) with unique `old_string` / `new_string`, never `write_file` after a head-slice. If you must use `write_file`, read the **full** file first, then verify byte count matches before AND after.

## Verification

After setup, run once and confirm:

```bash
python3 $HERMES_HOME/skills/hermes-agent-ops/agent-config-metabolism/scripts/metabolism_check.py | tee /tmp/metab-test.log
```

Expected output: 14 lines, each tagged `[GREEN]` or `[RED]`. If you see `[ERROR]` or fewer than 14 lines, the script failed — check `$HERMES_HOME/cron/output/agent-config-metabolism-<ts>.log` for stderr.

Then run the cross-validation probes from **Step 4** to confirm the script's numbers match ground truth.

## References

- `references/methodology.md` — why these 14 checks, the three structural failure modes, and the "monitor monitors" problem in depth.
- `references/threshold-tuning.md` — how to set thresholds for your own setup (smaller agent / larger team / heavy automation).
- `references/yaml-checks-key-parity.md` — the one-liner that catches the silent "yaml key drifted from CHECKS key" bug (the script runs but every check gets empty cfg).
- `references/parsers-and-extractors.md` — reusable Python patterns: JSONC lenient parser, Traceback tail extractor, yaml/CHECKS parity guard, cross-validation probes. Distilled from real bugs found while developing this skill.
- `scripts/metabolism_check.py` — the runnable audit (14 checks).
- `scripts/metabolism_thresholds.yaml` — editable thresholds.