# Threshold tuning

The 14 thresholds in `scripts/metabolism_thresholds.yaml` are **personal** — they reflect one user's setup (Hermes on Linux, ~50 active skills, weekly cron). Yours will differ. Use this guide to adjust.

## Sizing rules of thumb

| Profile | Inject (KB) | Skill count | Memory cache (MB) | Cron log age |
|---------|-------------|-------------|-------------------|--------------|
| Minimal agent (CLI, 1 user) | 15 | 50 | 50 | 14d |
| Standard agent (gateway + 5 skills) | 25 | 160 | 200 | 7d |
| Heavy agent (multi-profile, kanban) | 40 | 300 | 500 | 3d |

If your setup is bigger, raise thresholds. If you're seeing **all green** for months, your thresholds are too loose — tighten by 20% and see what surfaces.

## Per-check tuning

### 1. Inject size (default 25KB)

Sum of:
- System prompt (rules + personality + tools)
- All SKILL.md descriptions loaded into the index
- Memory.md + USER.md

Probe:
```bash
hermes chat -q "/status"  # shows context size
# OR look at $HERMES_HOME/agent/prompt_builder.py for the actual emit path
```

### 2. Skill count (default 160)

If you see `skills_list` returning > 200, that's a signal not a target. The target should be "the skills I actually use weekly" + 20% buffer.

Probe: `~/.local/bin/hermes skills list | wc -l` (after deduping against real disk — see `hermes-skill-curation` §1.4).

### 3. Broken symlinks (default 0)

Should always be 0. Any non-zero value means a dotfile source moved or got renamed without the symlink being updated.

### 7. Cron alive (default 7d)

How long since a scheduled job actually ran. If cron jobs claim to run daily but the log is 30 days old, either the daemon died or the schedule broke.

### 14. Plaintext secrets (default 0)

Greps for: `aws_`, `sk-`, `ghp_`, `xoxb-`, `xoxp-`, `Bearer eyJ`, `-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----`.

False-positive sources:
- Test fixtures with dummy keys
- Documentation examples
- `~/.env` (intentional — only check non-`.env` paths)

If your test fixtures have real-looking keys, exclude those paths via `thresholds.yaml` → `secret_grep.exclude_paths`.

## Schedule tuning

- **Weekly** (Sun 09:00): the original recommendation. Good for low-traffic agents.
- **Daily** (06:00): if you're adding skills/plugins rapidly or have kanban workers spinning.
- **Bi-weekly**: if you've been green for 3 months and want to reduce noise.

Don't go below weekly — drift needs time to accumulate before the check is worth the noise.

## When to update thresholds

| Trigger | Action |
|---------|--------|
| All green for 2+ months | Tighten by 20% |
| More than 3 reds per week | Either fix root causes OR raise thresholds (don't keep raising forever) |
| New profile / new platform | Re-baseline all thresholds |
| Switched model | Inject size may change — re-measure |