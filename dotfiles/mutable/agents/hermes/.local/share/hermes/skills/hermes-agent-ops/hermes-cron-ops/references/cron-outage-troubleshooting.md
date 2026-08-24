# Cron 任务罢工排查实录（2026-08-24 会话）

三个任务同时 `HTTP 401` 罢工的完整排查路径与修复，补充 SKILL.md 未展开的细节。

## 案例：custom provider pin 失效（LongCat）

**症状**：`hermes cron list` 全部任务 `last_status: error: RuntimeError: HTTP 401: incorrect api key`；`.env` 里根本没有该 provider 的 key。

**时间线特征**：executions.db 里先出现 `[blocked_config] provider credential missing`（预检拦下阶段），之后变成运行期 401——说明中途有人把任务 pin 到了某个 custom 端点。

**修复步骤**：
1. 备份 `$HERMES_HOME/cron/jobs.json`
2. 把失效任务的 `model`/`provider`/`base_url` 三字段置 null（CLI 清 pin 会死结，见下）
3. `hermes cron edit <id> --model <当前模型> --provider openrouter` 显式 pin
4. 验证：`python3 -c` 读回 jobs.json 确认三字段；等 1-2 个 ticker 心跳周期确认没被写回

## CLI 清 pin 死结（双向校验卡死）

残留 custom base_url 时：
- `hermes cron edit <id> --model "" --provider ""` → `Failed: base_url override requires an explicit provider`
- `hermes cron edit <id> --model X --provider openrouter` → `Failed: base_url '...' is not allowed for provider 'openrouter'`

CLI 无清除 base_url 的参数 → 只能直接编辑 jobs.json。调度器是 gateway 内 ticker（心跳文件 `$HERMES_HOME/cron/ticker_heartbeat`），实测不会覆盖外部编辑。

## 手动触发的坑

- **必须 background 跑**：`hermes cron run <id>` 同步等待，前台命令超时（默认 180s）会杀掉执行进程，executions.db 留下 `Scheduler restarted after this execution's owner exited ... marked unknown`
- 后台 shell 不继承交互 PATH，要 `export PATH="$HOME/.local/bin:$PATH"`，否则 `hermes: 未找到命令`（exit 127）
- 多任务并发触发会挤兑模型限流，全部「Empty response」重试耗尽——逐个跑

## 空响应排查路径

cron 持续空响应但同模型交互正常时：
1. `hermes -z "只回复两个字：好的"` —— 通则凭证没问题
2. workdir 下用真实 prompt 交互跑：`cd <workdir> && hermes --cli -z "$(cat prompt.txt)"` —— 通则内容/prompt 没问题
3. 都通 → gateway 常驻进程内部状态陈旧。日志特征（agent.log）：cron 会话每次 API 调用空响应重试耗尽，同时段交互 session 同模型正常出 token
4. 解法：gateway 外独立 shell 执行 `hermes gateway restart`（gateway 内的 agent 发起重启会被安全机制拦截：SIGTERM 会连带杀死自身）
5. 重启后重新逐个 `cron run` 补跑失败的任务

## 附带发现

- `/proc/<gateway-pid>/environ` 看不到运行时加载的 API key（Python dotenv 不进 environ）——不能用它断言凭证缺失
- `hermes gateway restart` 不能从 gateway 进程内部发起（会自杀）；本会话 agent 就活在 gateway 里
- jeans 任务手动验证结果（2026-08-24）：CI run 32632747170 success、无 open issue、无需修包，CI 已自动提交 df2dfe8→ee6a2c4
