# 14 Checks — Detection Methods

The script implements the 14 checks; this file is *why* each check
exists and *what to do* when it goes red. Numbers below are defaults
from the script — override via env (see SKILL.md "How to Run").

| # | Check | Default budget | Why it matters |
|---|-------|----------------|----------------|
| 01 | 常驻注入体积 | ≤ 25 KB | Each session re-injects MEMORY.md + USER.md. Two duplicate rule files = 39 KB of contradicting instructions, every turn. |
| 02 | 可触发技能总数 | ≤ 160 | Past 200 the routing becomes unreliable, mirrors rot, and humans can't audit. |
| 03 | 坏 symlink / 死引用 | 0 | Stow/deploy drift; agents follow dead links silently. |
| 04 | 关键配置文件存在性 | all of: `config.yaml`, `.env`, `auth.json` | Missing config = no agent. Missing `.env` = keys fall back to env (more leakage surface). |
| 05 | 规则文件格式合法 | 0 missing `---` header | A rule without frontmatter gets silently dropped by the prompt builder. |
| 06 | 状态类 JSON 可解析 | 0 unparseable | `auth.json` corrupted → no auth. `gateway_state.json` → gateway dies. |
| 07 | 定时任务真实在跑 | mtime ≤ 168h (7d) | Don't trust the cron job's own "I'm running" report. Probe the **heartbeat file's mtime** on disk. |
| 08 | 数据管线新鲜度 | mtime ≤ 672h (28d) | If MEMORY.md hasn't been touched in a month, the ingest is broken — even if cron is running. |
| 09 | 跨窗口派工错误计数 | < 5 ERROR/Traceback per logs | Counts error lines across `~/.local/share/hermes/logs/*.log`. |
| 10 | 单个日志文件行数上限 | ≤ 50 000 lines | A 2 GB log file is its own kind of failure. |
| 11 | 任务台账两份存储一致 | jobs count = kanban count | Detects drift between cron jobs.json and the kanban board. |
| 12 | 备份/临时文件堆积 | ≤ 20 .bak/.tmp/.swp/~ files | `*.bak.*` accumulates faster than you think. |
| 13 | 记忆与缓存目录体积 | memory ≤ 50 MB, cache ≤ 500 MB | Cross-platform `du -sm`, a watermark not a hard cap. |
| 14 | 明文密钥特征扫描 | 0 hits | Scan MEMORY.md/USER.md for `sk-…`, `ghp_…`, `AKIA…`, `xoxb-…` patterns. |

## What to do for each red

**01 — Injection budget too big**
Identify the duplicates: `diff MEMORY.md USER.md` (often near-identical
when one is a stale copy). Or two MEMORY.md files in different
locations: `find ~/.local/share/hermes -name MEMORY.md`. Action:
`trash-put` the duplicate, **not** the canonical one. (The
`memory` tool is the only thing that should write the canonical
file — see `hermes-memory-routing`.)

**02 — Skill count over budget**
Two failure modes:
- *Real growth*: legitimately added >160 skills. Use
  `hermes-skill-curation` to prune, but do **not** auto-prune from
  this script — it's a watchdog, not a curator.
- *Zombie mirrors*: `find ~/.local/share/hermes/skills -type l` to
  find symlinks pointing to deleted targets. `trash-put` the
  broken ones, then re-run.

**03 — Bad symlinks**
List: `find ~/.local/share/hermes -maxdepth 6 -type l ! -exec test -e {} \;`.
For each, decide: re-link the target, or `trash-put` the link. Don't
`rm` — use `trash-put` (XDG trash, your standing preference).

**04 — Config missing**
Recreate from your Guix-configs repo: `cd ~/Projects/Config/Guix-configs && blue home`.
Verify with `md5sum` against the dotfile source.

**05 — Frontmatter missing**
Re-add the `---` block. Each SKILL.md is one bug; use
`skill_view(name=<skill>)` on the affected skill to read the
expected frontmatter.

**06 — JSON unparseable**
`python3 -m json.tool <file>` to see the syntax error. Usually a
trailing comma from a half-written update. Don't hand-edit
`auth.json` — regenerate via `hermes auth add …`.

**07 — Cron not actually running**
This is the **monitor lies** failure. The cron job may report
"healthy" while its heartbeat file is 30 days old. Probable cause:
the scheduler died (`hermes cron status`). Manual kick:
`hermes cron run <job_id>` for each paused/dead job.

**08 — Pipeline data stale**
The cron is running (07 is green) but the data it should be
ingesting is old. Check the cron job's script directly:
`hermes cron list` → look at `command`/`script` for each.

**09 — Dispatch errors elevated**
`tail -100 ~/.local/share/hermes/logs/gateway.log` then `tail -100
cron-output/.../latest.log`. Don't just count — read the top 3
errors. Often it's a model-provider outage masquerading as "agent
errors".

**10 — Log file huge**
Rotate, don't delete. `mv gateway.log gateway.log.1 && touch
gateway.log` (the service usually reopens on next write). For
service-managed logs, send `SIGHUP` to the gateway.

**11 — Ledger drift**
One of the two stores is wrong. Read the more recent one (usually
the kanban board, which has `updated_at`) and re-derive the other
via `hermes cron create` / `hermes cron remove`.

**12 — Backup junk accumulated**
`trash-put` the `.bak` files. Don't use `rm`/`rm -rf`. Keep the
last 3 `config.yaml.bak.*` (those are the meaningful pre-edit
snapshots) but drop `.swp`/`.tmp`/`~` immediately.

**13 — Storage water high**
For `cache/`: `du -sh ~/.local/share/hermes/cache/*` and `trash-put`
the largest items. For `memories/`: if MEMORY.md itself is huge, run
`memory` tool with `action='remove'` on stale entries — but back
it up first.

**14 — Plaintext secret**
**Stop and rotate that key.** Then remove the line from MEMORY.md
(or USER.md) and re-encrypt the original secret into your
`secrets/` store (see the `age` workflow in your dotfile README).
The script does **not** auto-redact — it's your job.

## Customizing

Add a check by appending a `record RED|YEL|GRN "NN-name" "evidence"`
call. Order matters for the report (top to bottom is check 01 →
14), so renumber or insert carefully. Bump SKILL.md version
`patch` (new check) or `minor` (new category of check).

## Why red and yellow (not just red)?

YEL means "watch" — the fact is technically wrong, but the system
isn't on fire. The cron-delivery path suppresses yellow so you only
see reds in your inbox. Greens are silent. **The principle: machines
verify, humans only look at reds.** If a yellow persists for 3 weeks,
it has earned a red via promotion — edit the script and reclassify.
