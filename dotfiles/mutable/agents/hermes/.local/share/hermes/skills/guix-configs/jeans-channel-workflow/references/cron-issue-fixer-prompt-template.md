# `jeans-issue-fixer` cron prompt 设计参考（2026-08-01 更新）

对应 cron job: `job_id=3ba1524b02f2`，schedule `0 11 * * 2,4,6`（周二/四/六 11:00 北京时间），
workdir `~/Projects/Config/jeans`。**注意：当前 job 不带 skill（skills=[]），prompt 自包含**；
model 固定 `deepseek-v4-flash`。此前版本（2026-07-06）曾挂 `guix-configs-workflow` skill +
retry-guard 设计，已被 2026-07-11+ 的重写取代（当前部署版 = "自动修复 + 更新助手"）。

> ⚠️ **此文件是设计参考，不是可直接覆盖的模板全文**。改 prompt 前先 `cronjob action=list`
> 读当前部署的 prompt，在其基础上增量修改，不要整段替换回旧版。

## 当前部署版 prompt 的核心结构（2026-08-01 实测）

1. **开头**：声明"自动修复 + 更新助手"，要求先 `read_file` 加载 `.agents/skills/pack-guix/SKILL.md`
   获取打包规范，再动手。
2. **核心原则（2026-08-01 新增，最重要）**：先判定 CI 失败类型，再决定要不要修：
   - **基础设施失败（无需修复）**：run 创建后几十秒内 completed+failure，卡 `Install Guix` /
     `Checkout` / `Set up job` 等早期步骤，`Build test updated packages` 从未开始，且无新 issue。
     → 直接 `gh workflow run auto-update.yml` 重跑，不修任何包。
   - **真实构建失败（需要修复）**：CI 跑到 `Build test updated packages` 步骤后失败，
     `test_updated_packages.py` 创建 `❌ Updated package build failures — <sha>` issue。
     **只有看到这种 issue 才修包。**
3. **执行流程**：git pull → 查 CI 状态（gh api runs + issue list）→ 按判定分支处理 →
   修包（如需要）→ `blue build` 验证 → `blue upgrade` 全量更新检查 → 改动只留本地工作树。
4. **边界（硬性）**：❌ 不 commit / push / add；❌ 不改 CI workflow、AGENTS.md、blueprint.scm；
   ❌ 不碰 `~/.config/agents/skills/`；❌ 不跑 sudo / reconfigure；✅ 可改 `modules/**/*.scm`、
   可跑 `blue build` / `blue upgrade` / `guix refresh -u`。
5. **最终交付**：判定结论 + 改动摘要表 + gitmessage（供用户复制提交）+ 待决策项。

## 判定命令（gh 绝对路径）

```bash
GH=/home/brokenshine/.local/state/nix/profile/bin/gh   # ⚠️ ~/.nix-profile 已废弃（2026-08-01 确认）
$GH api 'repos/ShineBreaker/jeans/actions/runs?per_page=5' \
  --jq '.workflow_runs[] | select(.name=="Auto Update Packages") | {id, status, conclusion, event, created_at, updated_at}'
$GH issue list --repo ShineBreaker/jeans --state open --json number,title,labels,createdAt
```

- run 的 `conclusion: failure` + `updated_at - created_at < 60s` → 基础设施失败 → 重跑
- `updated_at - created_at > 几分钟` + 有 `❌` issue → 构建失败 → 修复流程

## 2026-08-01 关键失败模式：Install Guix 秒挂（ftpmirror 502）

**症状**：run 创建后 ~5 秒 failure，卡 `Install Guix` 步骤（4-5 秒内），后续全部 skipped。
2026-07-30（run 30535193381）与 2026-08-01（run 30685995735）各发生一次。

**根因**（从 actions job logs 确认）：

```
https://ftpmirror.gnu.org/gnu/guix/:
2026-08-01 05:31:48 ERROR 502: Bad Gateway.
##[error]Process completed with exit code 8.
```

install.sh 从 `ftpmirror.gnu.org` 动态重定向到镜像池（wayne.edu / ibiblio 等），
选中坏镜像时 502 → install.sh 下载 guix 安装包失败 → exit 8。**跟 jeans 代码无关。**

**处理**：直接重跑 action。镜像通常几分钟内恢复（实测重跑后 Install Guix 正常 20+ 分钟跑完）。

**注意**：`gh api .../actions/runs?workflow=auto-update.yml` 参数**不生效**（会返回所有
workflow 的 run，包括 mirror-codeberg.yml），必须在 client 端按
`select(.name=="Auto Update Packages")` 过滤。

## gh 二进制路径变更史

- 旧：`/home/brokenshine/.nix-profile/bin/gh`（Nix 旧式 home symlink）
- 新（2026-08-01 确认）：`/home/brokenshine/.local/state/nix/profile/bin/gh`（Nix 新式 profile，
  实测 gh 2.96.0）。`~/.nix-profile` 目录已不存在。改 prompt / 脚本时用新路径。

## 分支决策表（当前部署版）

| last run 状态 | 判定 | 动作 | 修包? |
|---|---|---|---|
| `in_progress`/`queued` | 还在跑 | 报告等待，不修 | ❌ |
| `completed` + `success` | 成功 | 查 issue，有 ❌ issue 则修复 | 仅当有 issue |
| `completed` + `failure` 且 <60s 卡早期步骤 | 基础设施失败 | 重跑 action，不修 | ❌ |
| `completed` + `failure` 且跑到 Build test 步骤 | 构建失败 | 修复 issue 对应包 | ✅ |
| 无最近 run | 未跑 | 重跑 action | ❌ |

## 调试路径（下次 cron 出问题怎么查）

1. **检查最近一次 cron 跑的产物**：

   ```bash
   ls -lt ~/.local/share/hermes/cron/output/ | head -5
   ```

2. **检查 jobs.json 现状**：

   ```bash
   cat ~/.local/share/hermes/cron/jobs.json | python3 -c "import json,sys; [print(j['id'], j['name'], j.get('last_status'), j.get('last_run_at')) for j in json.load(sys.stdin)['jobs']]"
   ```

3. **检查最近 action run 实况**：

   ```bash
   $GH api 'repos/ShineBreaker/jeans/actions/runs?per_page=5' \
     --jq '.workflow_runs[] | select(.name=="Auto Update Packages") | {id, status, conclusion, created_at}'
   ```

4. **拉 action job 日志看 Install Guix 失败原因**：

   ```bash
   JOBID=$($GH api 'repos/ShineBreaker/jeans/actions/runs/<run_id>/jobs' --jq '.jobs[0].id')
   $GH api "repos/ShineBreaker/jeans/actions/jobs/$JOBID/logs" | grep -i "error\|502\|exit code"
   ```

## 注意事项（更新此 prompt 之前确认）

- 改 jeans CI workflow 文件 (`.github/workflows/auto-update.yml`) 后，prompt 的
  失败类型判定逻辑可能漂移（新增 step 改了 conclusion 语义）。要重新跑 gh api 确认。
- 当前 prompt 假设"CI 失败 = 有 issue 才修"，**不要**改回旧的"失败即修"逻辑。
- job 当前不带 skill；若未来恢复挂 skill，注意 prompt 里的流程要与 skill 内容一致，
  避免双源漂移。
