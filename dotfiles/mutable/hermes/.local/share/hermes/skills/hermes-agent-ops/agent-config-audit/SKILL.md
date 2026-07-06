---
name: agent-config-audit
description: "Weekly red-light audit of Hermes Agent's own config. Triggers on agent slow / dumber over time, duplicate injection, zombie skills, state drift, monitor lying."
version: 0.1.0
author: Hermes
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [audit, health-check, config, drift, zombie-skills, injection-budget, monitoring]
    related_skills: [skill-authoring, hermes-skill-curation, hermes-memory-routing]
---

# Agent Config Audit

A weekly self-audit of Hermes Agent's own configuration. The agent's
context-injection overhead, skill count, state stores, and monitor
fidelity all drift over time; this skill runs 14 fact-based checks and
exits non-zero on red. **Machines verify, humans only look at reds.**

The premise (from the original post): an agent that gets slower or
"dumber" is almost never a model problem — it is being fed
contradictory, duplicated, or stale instructions. The cure is
metabolism, not a stronger model.

## When to Use

Trigger this skill on any of these signals (user or self-detected):

- "AI 变笨了" / "agent 变慢了" / "变笨" / "回答质量下降"
- "每次对话的固定开销太大" / "上下文越来越长"
- "技能太多" / "好多 skill 没用过" / "想清理 skill"
- "规则打架" / "两条规则冲突" / "AI 不知道听谁的"
- "监控说一切正常但其实不对" / "绿灯骗人"
- "上次跑是 X 天前" / "需要体检" / "周检" / "全面体检"
- "agent 配置审计" / "agent config audit"
- Schedule: every Sunday via `cronjob` (see §"Schedule")

Do **not** use this skill for: per-request debugging (use terminal
directly), one-off file lookups (`search_files`), or skill-library
*reorganization* — that is `hermes-skill-curation`.

## Prerequisites

- `$HERMES_HOME` defaults to `~/.local/share/hermes` (your user's
  Guix-configs deployment puts it there, not `~/.hermes/`). Override
  with `HERMES_HOME=/path hermes-config-audit`.
- `bash` ≥4, `python3` ≥3.9, `find`, `du`, `wc`, `stat`, `awk`,
  `grep` — all stdlib for a normal Linux install.
- `trash-cli` (your `~/.local/bin/trash-put`) **only** if a check
  recommends a deletion — never invoked automatically.

## How to Run

```bash
# One-shot audit (prints red/yellow/green per check, exits non-zero on red)
~/.local/share/hermes/skills/hermes-agent-ops/agent-config-audit/scripts/health-check.sh

# JSON output (for piping into a cron deliverable or a delegate_task)
~/.local/share/hermes/skills/hermes-agent-ops/agent-config-audit/scripts/health-check.sh --json

# Custom budgets
HERMES_INJECTION_BUDGET_KB=30 SKILL_COUNT_BUDGET=180 \
  ~/.local/share/hermes/skills/hermes-agent-ops/agent-config-audit/scripts/health-check.sh

# Tighter budget for a smaller profile
HERMES_HOME=~/.local/share/hermes/profiles/minimal \
  INJECTION_BUDGET_KB=15 SKILL_COUNT_BUDGET=60 \
  ~/.local/share/hermes/skills/hermes-agent-ops/agent-config-audit/scripts/health-check.sh
```

**Exit codes** (use these in cron + `notify_on_complete`):

| Code | Meaning | Cron action |
|------|---------|-------------|
| `0`  | All green | Silent (no delivery) |
| `1`  | At least one yellow | Optional: log only |
| `2`  | At least one red   | Deliver to user (the whole point) |

The principle: **machines verify, humans only look at reds.** Green
output is suppressed in cron delivery.

## Quick Reference

| Thing | Where |
|---|---|
| Edit budgets | `scripts/health-check.sh` env vars at top + env overrides |
| 14 checks, full spec | `references/14-checks.md` |
| Per-check detection method | `references/14-checks.md` (same file, per-section) |
| Schedule via cron | `cronjob(action='create', schedule='0 9 * * 0', script=...)` |
| Customize a check | patch `scripts/health-check.sh` (the file IS the procedure) |
| Symlink to your bin | `ln -s ../skills/.../scripts/health-check.sh ~/.local/bin/hermes-audit` |

## Procedure

1. **Pick the trigger.** Match the user's wording (or self-detected
   signal) against "When to Use" above. If unclear, ask one
   `clarify` with `choices=["weekly scheduled run", "one-shot ad-hoc
   audit", "diagnose a specific symptom"]` — do **not** enumerate
   inside the question string.

2. **Run the script.** Invoke through the `terminal` tool:

   ```bash
   ~/.local/share/hermes/skills/hermes-agent-ops/agent-config-audit/scripts/health-check.sh
   ```

   Stdout is the canonical report. The script writes nothing to disk
   on green; on red it appends a single line to
   `$HERMES_HOME/audit/last-red.log` for diffing across runs.

3. **Read the report top-down, reds first.** Each line is one of:
   - `🔴 RED  <check>: <evidence>` — needs human action
   - `🟡 YEL  <check>: <evidence>` — watch, not urgent
   - `🟢 GRN  <check>` — silent (suppressed in cron delivery)

   The evidence string is *the* fact — file path, byte count, count
   diff, etc. Don't paraphrase it; show it to the user verbatim.

4. **Map red → action.** Each check in `references/14-checks.md`
   has a "What to do" subsection. Common resolutions:
   - duplicate injection → `trash-put` the duplicate (or merge)
   - zombie skills → `hermes-skill-curation` (it owns that domain)
   - JSON parse error → `python3 -m json.tool <file>` to locate
   - monitor lies → trust the timestamp probe, not the report
   - secret in plaintext → `trash-put` + re-encrypt via `secrets`
     helper in your Guix-configs repo

5. **Schedule the weekly run** (if user wants recurrence):

   ```python
   cronjob(
     action="create",
     name="agent-config-audit-weekly",
     schedule="0 9 * * 0",            # Sunday 09:00 local
     script="~/.local/share/hermes/skills/hermes-agent-ops/agent-config-audit/scripts/health-check.sh",
     no_agent=True,                    # the script IS the job
     deliver="origin",
   )
   ```

   `no_agent=True` is critical: the script is watchdog-style, its
   stdout is the message. Empty stdout = silent (no false alarms).
   Non-zero exit = error alert (so a broken audit can't fail
   silently — that would itself be a "monitor lies" violation).

6. **Track drift over time.** After every red, append a dated note
   to `$HERMES_HOME/audit/history.log` (the script does this
   automatically on red). The shape of *which* checks go red over
   weeks is more diagnostic than any single run.

## Pitfalls

- **Don't trust `hermes skills list` as the source of truth for
  skill count.** The bundled manifest + hub lockfiles can
  disagree with the filesystem. Check #2 enumerates via
  `find ... -name SKILL.md` instead.
- **Don't auto-delete on red.** The script reports; you decide.
  Use `trash-put`, never `rm`/`rm -rf` (your standing
  preference). `hermes-skill-curation` is the skill for
  structural cleanup; this skill is the watchdog.
- **Don't conflate `~/.local/share/hermes/Trash/` with the XDG
  `~/.local/share/Trash/`.** They are two different trash
  directories. `trash-put` uses XDG.
- **A green run is not a "system healthy" guarantee.** It only
  proves the 14 specific facts the script checks. The original
  post's whole point is that monitors are incomplete — extend
  the script when a new failure mode appears, don't disable
  checks.
- **The script reads `$HERMES_HOME`, not `~/.hermes/`.** Your
  Guix deployment pins it at `~/.local/share/hermes`; if you
  copy this skill to a fresh install, the env-var override is
  the first thing to check.
- **Secret redaction in cron delivery.** If you wire
  `deliver="origin"`, the cron framework auto-redacts obvious
  API keys, but a leak through check #14 (plaintext secrets) is
  the one case where the redacted message is the alert itself —
  consider `deliver="local"` and a separate human-pull channel
  for the secret-leak red.
- **Schedule drift on laptops.** A Sunday 09:00 cron on a
  sleeping laptop will *not* fire. Pair with `kanban.failure_limit`
  semantics or a separate `hermes cron run` weekly manual.

## Verification

Run it once and confirm the output shape:

```bash
~/.local/share/hermes/skills/hermes-agent-ops/agent-config-audit/scripts/health-check.sh
echo "exit=$?"
# Expected: 14 lines, each starting with 🔴/🟡/🟢, exit 0/1/2
```

Then force one check red to prove the alerting path works:

```bash
# Temporarily tighten the budget
INJECTION_BUDGET_KB=1 ~/.local/share/hermes/skills/hermes-agent-ops/agent-config-audit/scripts/health-check.sh
echo "exit=$?"  # Expected: 2 (red on check #1)
```

If `--json` round-trips, the cron deliverable will work:

```bash
~/.local/share/hermes/skills/hermes-agent-ops/agent-config-audit/scripts/health-check.sh --json | python3 -m json.tool
```

---

**Source:** distilled from a 2026-07-06 public post on agent
self-audit ("AI 每次开工前要吞下 39KB 互相矛盾的指令—— 它不是变笨
了，是被喂笨的"). 14-check list, red/yellow/green semantics, and the
"machine verifies, human only looks at red" principle are
verbatim from that post.
