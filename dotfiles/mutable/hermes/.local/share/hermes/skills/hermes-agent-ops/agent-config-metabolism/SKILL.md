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

Three user-stated principles that govern every interaction with this skill — captured after explicit corrections during originating sessions.

### 1. Autonomous cron mode — fix false-positives, escalate real decisions

**This is the default behavior for the weekly cron job.** When the audit runs as a scheduled task (not interactive Q&A), the agent should:

1. Run the audit script
2. Cross-validate each RED via independent shell probes
3. **Autonomously fix false-positives:**
   - Script bugs (e.g. JSONC parser missing block comments) → patch the script + verify
   - Thresholds too tight → adjust yaml with justification
   - Missing whitelist entries → add exclude_paths/filters with justification
4. **Escalate real problems to the user** with decision options (A/B/C) and a recommended direction
5. Re-run the script after fixes to confirm greens

The user explicitly opted into this mode on 2026-07-26: "只扫任务不解决问题？应该自主解决部分问题，然后假如有需要用户拍板的地方则直接说出来。"

### 2. Interactive mode — report first, ask before acting

When the user asks about the audit interactively (not via cron), stay in report-only mode:

- Surface every red with: *which file / which line / what's the real signal behind the number*
- Cross-validate each red against ground truth (independent shell pipeline) — never trust the script's first number
- Present the report with **decision options** and **stop**
- Wait for explicit user approval before touching any file

Trigger phrases that switch to interactive/report-only mode:
- "你看看本次检查暴露出来了什么问题"
- "向我汇报" / "report to me" / "find out what's wrong"
- "审核" / "review" (without explicit fix instruction)

### 3. **Solve the root cause directly — never hide problems behind excludes or threshold-raising**

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

# Weekly cron (Sunday 09:00, LLM-driven — agent fixes false-positives autonomously)
cronjob(
    action="create",
    schedule="0 9 * * 0",
    name="agent-config-metabolism-weekly",
    skills=["agent-config-metabolism"],
    prompt="""你是 Hermes Agent 的自主周检助手。加载 agent-config-metabolism skill，然后按以下流程执行：

## 执行流程

1. **跑审计脚本**
   python3 $HERMES_HOME/skills/hermes-agent-ops/agent-config-metabolism/scripts/metabolism_check.py

2. **分析 RED 项**（cross-validation）
   对每个 RED，独立用 shell 探针验证真伪。重点排查：
   - 脚本 bug（如 JSONC 解析器漏了块注释）
   - 阈值配置过紧（inject 27KB/25KB 这种轻微超标）
   - 白名单漏配（session dump Bearer、微信 poll 错误）
   - 真实问题（真正需要修复的）

3. **自主修复 false-positive**
   - 脚本 bug → 直接 patch 脚本 + 跑一次验证
   - 阈值过紧 → 调 yaml 并说明理由
   - 白名单漏配 → 加 exclude_paths/grep 过滤并说明理由
   - 修完后重跑脚本，确认 RED 变绿

4. **汇报结果**
   最终交付：
   - **已自主修复**：修了什么、怎么修的、验证结果
   - **真实问题需你拍板**：问题描述、选项（A/B/C）、建议方向
   - **全绿**：简洁确认即可

## 边界

- ❌ 不要动 `~/.config/agents/skills/`（Guix Home immutable）
- ❌ 不要碰 uncommit 的 git 文件
- ❌ 不要 push 到 remote
- ✅ 脚本 bug、阈值、白名单可以直接改
- ✅ 真正拿不准的，给我选项让我决定""",
    no_agent=False,  # LLM-driven, not script-driven
    deliver="origin",
)
```

Or directly via shell (read-only report):

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

Each red is a concrete signal. In **interactive mode**, the script does NOT auto-fix anything. In **autonomous cron mode**, false-positives are auto-patched and real problems are escalated with options.

### Step 3: Diagnose reds and decide action mode

| Red on check #... | Likely cause | Skill | Autonomous mode action |
|----|----|----|----|
| 1 (inject too big) | duplicate rules injected twice | `hermes-skill-curation` §2 | Cross-validate; if over threshold by <10%, adjust yaml with justification |
| 2 (skill count) | zombie skills from past imports | `hermes-skill-curation` §2 | Cross-validate; escalate with cleanup options if real |
| 3 (broken symlinks) | dotfile source moved | `guix-configs-workflow` | Escalate — broken symlinks need manual review |
| 6 (JSON parseable) | JSONC block comments or trailing commas | this skill | **Fix parser** (patch `_parse_json_lenient`) |
| 7 (cron not alive) | daemon died | `hermes-agent` §Durable | Escalate — cron daemon issues need investigation |
| 9 (errors) | gateway poll errors, MCP failures | `hermes-agent` | Cross-validate; if same signature repeating ×N, it's one root cause — check if upstream fixable |
| 14 (plaintext secret) | session dumps, test fixtures | this skill | Cross-validate; if session dump Bearer or test fixture, add exclude_paths |

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

### Step 5: Schedule via cron (LLM-driven autonomous mode)

Use `cronjob(action='create', ...)` with the skill and `no_agent=False` so the agent can autonomously fix false-positives and escalate real decisions.

```python
cronjob(
    action="create",
    schedule="0 9 * * 0",
    name="agent-config-metabolism-weekly",
    skills=["agent-config-metabolism"],
    prompt="""你是 Hermes Agent 的自主周检助手。加载 agent-config-metabolism skill，然后按以下流程执行：

## 执行流程

1. **跑审计脚本**
   python3 $HERMES_HOME/skills/hermes-agent-ops/agent-config-metabolism/scripts/metabolism_check.py

2. **分析 RED 项**（cross-validation）
   对每个 RED，独立用 shell 探针验证真伪。重点排查：
   - 脚本 bug（如 JSONC 解析器漏了块注释）
   - 阈值配置过紧（inject 27KB/25KB 这种轻微超标）
   - 白名单漏配（session dump Bearer、微信 poll 错误）
   - 真实问题（真正需要修复的）

3. **自主修复 false-positive**
   - 脚本 bug → 直接 patch 脚本 + 跑一次验证
   - 阈值过紧 → 调 yaml 并说明理由
   - 白名单漏配 → 加 exclude_paths/grep 过滤并说明理由
   - 修完后重跑脚本，确认 RED 变绿

4. **汇报结果**
   最终交付：
   - **已自主修复**：修了什么、怎么修的、验证结果
   - **真实问题需你拍板**：问题描述、选项（A/B/C）、建议方向
   - **全绿**：简洁确认即可

## 边界

- ❌ 不要动 `~/.config/agents/skills/`（Guix Home immutable）
- ❌ 不要碰 uncommit 的 git 文件
- ❌ 不要 push 到 remote
- ✅ 脚本 bug、阈值、白名单可以直接改
- ✅ 真正拿不准的，给我选项让我决定""",
    no_agent=False,
    deliver="origin",
)
```

**Exit code is always 0** — the report IS the signal. A non-zero exit would mark the cron job as "error" in the Hermes UI, which is exactly what we don't want even when there are REDs. 注意：实际部署中**并不存在 wrapper 脚本**兜底——早期 script 模式（no_agent=True）下脚本在 RED 时以 exit 1 结束，cron 直接标记 failed 且报告投递异常（2026-07-19、07-25、07-26 三次自动运行因此失败，用户从未收到报告）。当前正确形态是 **LLM 模式（no_agent=False）**：报告作为 agent 最终回复投递，不存在 exit code 问题。不要再切回 no_agent script 模式，除非先补一个真正吞掉非零退出码的 wrapper。

To change delivery later: `cronjob(action='update', job_id='<id>', deliver='local')`.

## Pitfalls

- **Don't auto-fix on red.** The script outputs a report, not a cleanup. Red means "investigate", not "delete". `hermes-skill-curation` handles actual cleanup.
- **Autonomous cron mode is opt-in only.** The user explicitly activated it ("只扫任务不解决问题？应该自主解决..."). Don't assume it's universal — document the opt-in for other users.
- **Thresholds are personal.** The script reads thresholds from a config file (`scripts/metabolism_thresholds.yaml`); adjust to your setup. 25KB inject / 160 skills are starting points, not universal truths.
- **Check 11 (task ledger parity) requires kanban enabled.** If you don't use kanban, skip that check (set `enabled: false` in thresholds).
- **Check 14 (plaintext secrets) is heuristic.** It greps for `sk-`, `aws_`, `ghp_`, `xoxb-`, `Bearer ` — these can false-positive on test fixtures. Review before rotating.
- **Cron sessions pass `skip_memory=True`.** Results don't pollute your main memory.
- **Self-update blindness.** If you set thresholds too loose, you'll see all-green while bloat grows. Tighten thresholds quarterly.
- **YAML key names MUST match the CHECKS list keys.** The script dispatches via `thresholds.get(key, {})` where `key` comes from the CHECKS tuple. If your yaml section is named `backup_tmp_pile` but CHECKS says `"backup_tmp"`, the check runs on **empty cfg** and silently falls back to function defaults — you'll see GREEN when the real threshold isn't loaded. Always grep CHECKS keys against yaml top-level keys after editing either side (see `references/yaml-checks-key-parity.md`).
- **The no-PyYAML fallback parser must handle the full thresholds dialect.** When PyYAML is absent, `load_thresholds()` falls back to `_yaml_fallback`, which needs three things the original didn't have: inline-comment stripping (`max_kb: 30 # comment` → int, not str), flow lists (`[name, description]`), and block lists (`patterns:` + `- item`). Without them every numeric comparison crashes with `'<=' not supported between instances of 'float' and 'str'`, `required_fields` becomes a string and check 5 flags every file as missing fields, and `patterns` becomes `{}` so check 12 is a permanent fake GREEN. The fixed parser is in the script — don't regress it.
- **`_glob_match` uses `fnmatch`, whose `*` matches `/` but whose pattern is anchored at the start.** `references/**` and `node_modules/**` only match paths *starting* with that prefix — nested `.../hermes-agent/references/native-mcp.md` is NOT excluded, and doc examples with `sk-xxx` placeholders show up as check 14 hits. Use `**/references/**` style (leading `**/`) for any pattern that must match at any depth.
- **Check 9 counts a rolling window, not all history.** `window_days: 7` (default) means a fixed root cause stops counting as soon as it ages out — the signal is "problems active NOW". Long-lived external failures (weixin poll errors, QQ token fetch) will keep the check RED week after week under the old all-history scan even after they're fixed; with the window they self-resolve. Retry counters `(1/3)(2/3)(3/3)` are normalized to `(n/3)` — three retries of one connection failure are one problem.
- **Don't trust injected-size estimates.** Real inject is `sum(description field bytes)`, NOT `sum(SKILL.md file bytes) ÷ 5` (that's a ~7× over-estimate). When reading SKILL.md frontmatter, read **at least 4 KB** (not 600 bytes) — the 600-byte truncation silently broke 2 SKILL.md in this user's setup whose descriptions were 700-18000 bytes.
- **Don't trust raw error counts.** A literal grep `ERROR\|Traceback` over all logs surfaces N independent problems when in reality it's 1 repeating failure (the same cron import error ×2626 looks like 2626 issues but is one root cause). **Group by `(file:module:msg_prefix)` signature** before comparing to threshold — the metabolic signal is "how many unique problems", not "how many log lines".
- **Never `read_text()[:N]` then `write_text()` to modify a single field.** This silently truncates files whose content exceeds the slice. During the originating session, this exact pattern wiped the body of 3 SKILL.md files (emacs-config-debugging 19.6KB → 477 bytes, narrated-video-alignment 13.3KB → 590 bytes, guix-configs-workflow 51.5KB → 10.3KB) — all because the patch_desc helper sliced `[:800]` to find the `description:` line and then wrote back only the head. **Correct pattern for single-field edits**: use `patch_file` (or `patch()` tool) with unique `old_string` / `new_string`, never `write_file` after a head-slice. If you must use `write_file`, read the **full** file first, then verify byte count matches before AND after.

## Verification

After setup, run once and confirm:

```bash
python3 $HERMES_HOME/skills/hermes-agent-ops/agent-config-metabolism/scripts/metabolism_check.py | tee /tmp/metab-test.log
```

Expected output: 14 lines, each tagged `[GREEN]` or `[RED]`. If you see `[ERROR]` or fewer than 14 lines, the script failed — check `$HERMES_HOME/cron/output/agent-config-metabolism-<ts>.log` for stderr.

**Exit code is always 0** — the report IS the signal. A non-zero exit would mark the cron job as "error" in the Hermes UI, which is exactly what we don't want even when there are REDs. 注意：实际部署中**并不存在 wrapper 脚本**兜底——早期 script 模式（no_agent=True）下脚本在 RED 时以 exit 1 结束，cron 直接标记 failed 且报告投递异常（2026-07-19、07-25、07-26 三次自动运行因此失败，用户从未收到报告）。当前正确形态是 **LLM 模式（no_agent=False）**：报告作为 agent 最终回复投递，不存在 exit code 问题。不要再切回 no_agent script 模式，除非先补一个真正吞掉非零退出码的 wrapper。

Then run the cross-validation probes from **Step 4** to confirm the script's numbers match ground truth.

## References

- `references/methodology.md` — why these 14 checks, the three structural failure modes, and the "monitor monitors" problem in depth.
- `references/threshold-tuning.md` — how to set thresholds for your own setup (smaller agent / larger team / heavy automation).
- `references/yaml-checks-key-parity.md` — the one-liner that catches the silent "yaml key drifted from CHECKS key" bug (the script runs but every check gets empty cfg).
- `references/parsers-and-extractors.md` — reusable Python patterns: JSONC lenient parser, Traceback tail extractor, yaml/CHECKS parity guard, cross-validation probes. Distilled from real bugs found while developing this skill.
- `scripts/metabolism_check.py` — the runnable audit (14 checks).
- `scripts/metabolism_thresholds.yaml` — editable thresholds.

## Appendix — Merged from agent-config-audit (zombie skills / injection-budget)

> 来源 `agent-config-audit` 独有、metabolism 原版未覆盖的 2 条检测，已以附录并入。

### A. Zombie skills — 僵尸镜像检测
- 勿信 `hermes skills list` 清单；以 `find $HERMES_HOME/skills -name SKILL.md | wc -l` 为准。
- 僵尸镜像：`find $HERMES_HOME/skills -type l ! -exec test -e {} \; -print` 找出指向已删除目标的 symlink。

### B. Injection-budget — 重复注入 / 预算
- 查重：`diff $HERMES_HOME/memories/MEMORY.md $HERMES_HOME/memories/USER.md`；多位置：`find $HERMES_HOME -name MEMORY.md`。
- Guix stow 下 MEMORY.md 为 symlink，必须 `stat -Lc%s` 跟随取真实体积，`stat -c%s` 只得 ~100B 导致假绿。