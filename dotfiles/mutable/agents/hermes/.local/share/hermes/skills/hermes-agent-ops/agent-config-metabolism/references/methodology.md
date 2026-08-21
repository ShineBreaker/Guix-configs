# Methodology — Why these 14 checks

The post that inspired this skill observed: **"AI 用久了变笨" is rarely the model — it's the config.** Three structural failure modes show up everywhere an agent has lived long enough:

## The three failure modes

### 1. Document-production cost < cleanup cost

Every session wants to leave a trace ("look, I made a skill!"). No session wants to delete. So `~/.local/share/hermes/skills/` grows monotonically. After 6 months: 187 skill dirs, 134 of which are duplicates / archived / never-loaded. The agent's **inject size** (system prompt + skill metadata) balloons from ~5KB to ~39KB per turn. The model isn't dumber — it's reading 39KB of contradictory instructions before each message.

### 2. Same state in N places = drift over time

```
MEMORY.md  ──┐
fact_store ──┼── all claim to be "the truth"
USER.md   ──┘
```

Any two of these will drift. The third source of truth isn't free — it's a tax on every read.

### 3. Monitors not monitored → report green when red

A "health check" that runs but never compares its output to ground truth. Example from the original post: 106-day-stale log entry, dashboard said "all green" because the monitor only checked the JSON it had just written, not whether the JSON was still accurate.

## The 14 checks map to the three modes

| Mode | Checks |
|------|--------|
| Production cost | 1 (inject), 2 (skill count), 5 (rule format), 13 (cache size) |
| State drift | 4 (config exists), 6 (JSON parseable), 11 (task ledger parity), 14 (plaintext) |
| Monitor blindness | 3 (broken symlinks), 7 (cron alive), 8 (pipeline fresh), 9 (error count), 10 (log cap), 12 (backup pile) |

## The principle

> 机器查事实，人只看红灯。
>
> *Machines check facts. Humans only see red.*

This isn't a one-time cleanup script. It's a **metabolism** — weekly, automatic, idempotent. The cron job runs every Sunday. The script writes a report. You only open it when something is red. The cost of running is low (no LLM tokens with `no_agent=True`); the cost of *not* running is the model becoming "dumber" for reasons that have nothing to do with the model.

## What this skill is NOT

- Not a one-shot cleanup → use `hermes-skill-curation` for actual deletion
- Not a model benchmark → if your checks are all green and AI is still bad, the problem is the prompt, not the config
- Not a replacement for `hermes doctor` → that's a per-session tool check; this is a per-week config health check

## Origin

This skill is distilled from a viral post by a Fable agent user who ran a 4-subagent audit on their own config and found:
- 2 identical rule files injected every turn
- 1 memory snapshot in 3 places
- 187 skills, 53 of them zombie/duplicate
- 2 always-on rules contradicting each other ("post to twitter first" vs "build a site first")
- 1 health monitor reporting green while a 106-day-stale log was on the same page

The author's conclusion: **don't switch models. Install metabolism.**