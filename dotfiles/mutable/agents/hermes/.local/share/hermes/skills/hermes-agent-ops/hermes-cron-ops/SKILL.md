---
name: hermes-cron-ops
description: "Create/debug Hermes cron jobs; deliver reports to QQ/WeChat."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [hermes, cron, scheduling, qqbot, delivery, ops]
---

# Hermes Cron Ops

Hermes cron 定时任务的创建、诊断与投递配置。覆盖：把用户给的巡检/报告计划转成 cron job 的完整流程、模型 pin 铁律（#44585 漂移防护）、QQ/微信平台投递的确认方法、报告格式适配。

## When to Use

- 用户说"设置定时任务 / 每周X跑一次 / 依照计划设置 cron / 定时巡检 / 按这个计划定时执行"
- cron job 报了 `last_status: error` 但没有任何可见输出（很可能被漂移防护跳过）
- 用户手动触发 cron 后说"用不了 / 没反应"
- 需要把 cron 报告投递到 QQ（qqbot）、微信（weixin）等消息平台

## 触发信号

- 用户说"设置定时任务 / 每周X跑一次 / 依照计划设置 cron / 定时巡检"
- cron job 报了 `last_status: error` 但没有任何可见输出（很可能被漂移防护跳过）
- 用户手动触发 cron 后说"用不了 / 没反应"
- 需要把 cron 报告投递到 QQ（qqbot）、微信（weixin）等消息平台

## 创建 cron job 的最佳实践

1. **deliver 机制**：cron 的 agent 最终回复会被自动投递到 `deliver` 目标——agent **不需要**调用任何发消息工具，也不要把报告写文件（除非用户明确要双写）。prompt 里写清楚「报告作为最终回复输出即可」。
2. **prompt 必须自包含**：cron 在全新 session 运行，无对话上下文。把用户给的完整计划（环境路径、API、步骤、约束、容错规则）原样打包进 prompt，不要精简到看不懂。
3. **workdir**：设到仓库根（如 `/home/brokenshine/Projects/Config/Guix-configs`），该目录的 AGENTS.md / CLAUDE.md 会自动注入 system prompt，agent 能拿到仓库约定。
4. **enabled_toolsets**：按任务实际需要收窄工具集（如 `["web", "terminal", "file"]`），省 token 开销。**不要**给 cron 加 `messaging`（投递由框架做）、`cronjob`（cron 内禁止递归建 cron）、`clarify`（无人可问）。
5. **3 分钟硬中断限制**：复杂任务（guix refresh、批量 API 抓取）可能跑不完。prompt 里要设计优先级兜底：「时间紧张时优先保证核心步骤（如频道活动+上游版本），changelog 抓多少算多少」。
6. **格式适配**：投递到 IM 平台（QQ 等）时，报告用 markdown（emoji 分区 + 表格 + 加粗），不要用 org 格式的竖线表格（手机上难读）。详见 `references/qqbot-delivery.md`。

## 模型 pin 铁律（最重要的坑）

**背景**：`cronjob` 工具的 schema **没有** model/provider 参数——inference pins 是 user-owned，agent 无法自设。未 pin 的任务跟随全局默认模型，并在创建时**快照**当时的全局配置。

**症状**：任务创建后，用户改了全局默认模型（`hermes model` / /model）→ 任务下次运行被 #44585 漂移防护直接跳过执行：`Skipped to prevent unintended spend: global inference config drifted since this job was created ... and this job is unpinned. No inference call was made.` 表现为「手动触发没反应 / 用不了」，last_status=error 但无输出文件。

**诊断**：
```bash
hermes cron runs <job_id> --limit 5   # 看 executions.db 里的具体错误
```
常见错误两类：
- `global inference config drifted ... unpinned` → 未 pin + 全局模型变更
- `[blocked_config] provider credential missing` → 创建时快照的 provider 无有效 key（如 Nous Portal 未登录），预检直接拦下

**修复**（必须用 CLI，cronjob 工具做不到）：
```bash
hermes cron edit <job_id> --model <model> --provider <provider>
```
选一个 .env 里有 key 的稳定 provider（如 `deepseek-v4-flash` / `deepseek`，与现有任务一致）。**创建后立即 pin，别等用户手动触发才发现**。pin 后漂移防护不再对任务生效。

## 投递平台确认

投递前先确认目标平台真的在线，否则任务跑完 delivery 静默失败：

- **QQ**：`.env` 里有 `QQ_APP_ID` / `QQ_CLIENT_SECRET` / `QQBOT_HOME_CHANNEL` → 配置存在；再看 gateway.log 确认 WebSocket 活着。细节见 `references/qqbot-delivery.md`。
- **微信**：`.env` 里有 `WEIXIN_BASE_URL` 等 → 配置存在。已知坑：iLink 发消息有 rate limit，cooldown 期间 delivery 报 `rate limited; cooldown active for 30.0s`（不致命，下次 tick 重试）。
- 日志位置：`$HERMES_HOME/logs/gateway.log`（不要硬编码 `~/.hermes/`，HERMES_HOME 可能已重定向）。

## 诊断命令速查

```bash
hermes cron list                     # 所有任务 + last_status / last_delivery_error
hermes cron runs <id> --limit 5      # 执行历史（executions.db，含具体错误）
ls $HERMES_HOME/cron/output/         # 本地投递的输出文件
hermes gateway status                # gateway 是否在跑（不显示各平台连接详情）
```

## Pitfalls

- 用户改全局默认模型后，**所有未 pin 的 cron 任务都会静默罢工**——不只新建的那个。巡检现有任务时先看有没有 `model: null`。
- `last_delivery_error` 里的 rate limit / 连接错误 ≠ 任务失败：看 `last_status` 区分（ok + delivery error = 报告生成了但没送到；error = 没跑）。
- cron 报告里要求「可追溯、不臆造」（版本号/hash 必须有来源，抓不到标未获取）——复杂巡检类任务的通用约束，直接写进 prompt。
