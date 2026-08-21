# Pi → Hermes Mapping

| pi `agenote-hooks/index.ts` | hermes 等价 | 备注 |
|---|---|---|
| `session_start` 注入 health 摘要 | `on_session_start` 钩子 | 未实现：与 `skills.external_dirs` 重复，刻意跳过 |
| `agent_end` 检测完成信号 + 注入 review | `pre_llm_call` 检测 `user_message` | hermes 无 `agent_end`；`pre_llm_call` 每轮都有 `user_message`，等效 |
| `agent_start` 取消 idle timer | — | 见下 |
| 5 分钟 idle 兜底 timer | —（未移植） | hermes 钩子是同步 per-turn，无常驻 timer；升级路径：gateway 常驻任务或 cron 轮询 `sessions` 空闲时间 |
| `/agenote-summarize` `/agenote-health` `/agenote-curate` | `register_command` 同名 | 行为一致，curate 120s 超时 |

`pi→hermes` 的核心差异：pi 扩展在宿主进程常驻（可 `setTimeout`），hermes 插件是每轮钩子。需要跨轮状态时用模块级变量 + `ctx.state`，需要定时器时走 gateway/cron 外部调度。
