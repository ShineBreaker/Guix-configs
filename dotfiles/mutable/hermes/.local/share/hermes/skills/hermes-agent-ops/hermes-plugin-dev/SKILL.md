---
name: hermes-plugin-dev
description: "Use when writing Hermes plugins or porting pi extensions."
version: 0.1.0
license: MIT
metadata:
  hermes:
    tags: [hermes, plugin, hooks, slash-commands, agenote]
---

# Hermes Plugin Dev

把 pi/omp 的 TypeScript 扩展以最小成本移植到 hermes。

## 目录契约（最小）

```
~/.local/share/hermes/plugins/<name>/
├── plugin.yaml        # manifest 必需
└── __init__.py        # register(ctx) 必需
```

`plugin.yaml` 例：

```yaml
name: agenote
version: 0.1.0
provides_hooks: [pre_llm_call]
provides_commands: [agenote-health, agenote-curate, agenote-summarize]
```

备份源：`dotfiles/mutable/hermes/.local/share/hermes/plugins/<name>/`（hermes 包是 folding，`~/.local/share/hermes` 指向源）。

## 注册面

```python
def register(ctx):
    ctx.register_hook("pre_llm_call", _pre_llm_call)
    ctx.register_command("agenote-health", _handle_health, description="...")
```

- `VALID_HOOKS` 见 `hermes_cli/plugins.py`：`pre_llm_call`, `pre_gateway_dispatch`, `on_session_start` 等。
- `pre_llm_call` 回调签名：`fn(session_id, user_message, platform, **_) -> {"context": str} | None`。返回的 `context` 会拼到当轮 `user_message` 的 api 侧。
- `register_command(name, handler)` 的 handler 签名 `fn(raw_args: str) -> str`，可同步或 async；用 `ctx.inject_message(prompt)` 把提示注入下一轮。
- 插件启用白名单：`hermes config set plugins.enabled '["ponytail","<name>"]'`。`plugins.enabled` 为 allowlist，非空时未列名的插件 `enabled=False`。

详见 `references/hook-payloads.md` 与 `references/pi-to-hermes-mapping.md`。

## agenote 移植坑位（浓缩）

- 完成信号检测：复用 `agenote-base/curator/review` 的信号表（`搞定/完成/测试通过/done./ship it` 等），见 `references/completion-signals.md`。
- 自触发阻断：检查 `HOOK_MARKER = "<agenote-hook>" in user_message` 直接跳过。
- 子会话降噪：`platform in ("subagent","cron")` 跳过，避免污染 `delegate_task` handoff。
- 5 分钟防抖：`time.time()*1000 - _last_trigger_ms < 5*60*1000` 跳过。
- CLI 路径：`~/.guix-home/profile/bin/agenote` 优先，fallback `PATH`；`AGENOTE_AGENT=hermes` 归因。
- Skills 复用：`~/.agents/skills/agenote-*` 已通过 `skills.external_dirs` 对 hermes 可见，无需重装。

## 验证

```bash
~/.local/share/hermes/hermes-agent/venv/bin/python -c "
import sys; sys.path.insert(0,'~/.local/share/hermes/hermes-agent')
import hermes_cli.plugins as pm; pm._plugin_managers_by_home.clear(); pm._plugin_manager=None
m=pm._ensure_plugins_discovered()
print(sorted(m._plugin_commands)); print(m._plugins['agenote'].enabled)
print(m.invoke_hook('pre_llm_call', session_id='t', user_message='搞定了', platform='cli'))
"
hermes skills list | grep agenote
```

新增钩子/命令后重启 gateway。

## 刻意不做

- `agent_end` 后的 5 分钟空闲兜底 timer：hermes 无常驻 timer，跳过；见 `references/pi-to-hermes-mapping.md` 升级路径。
- `session_start` 健康摘要注入：与 `external_dirs` 的 skill 已覆盖，重复即噪音。
