# Hook Payloads

`pre_llm_call` 是本插件唯一的常驻钩子。hermes 在 `agent/turn_context.py:build_turn_context` 每轮调用：

```python
_invoke_hook("pre_llm_call",
    session_id, task_id, turn_id,
    user_message, conversation_history,
    is_first_turn, model, platform,
    parent_session_id, sender_id)
```

回调返回 `{"context": str}` 或 `str` 即注入到 `user_message` 的 api 侧；`None`/空串表示不注入。返回内容会过 `hook_output_spill`（超长落盘）。

有效 `VALID_HOOKS` 定义在 `hermes_cli/plugins.py:VALID_HOOKS`，含 `pre_llm_call`, `pre_gateway_dispatch`, `on_session_start` 等。`register_hook` 需与 `plugin.yaml:provides_hooks` 一致，否则校验报错。

`register_command(name, handler, description, args_hint)`：`handler(raw_args: str) -> str`，handler 内可用 `ctx.inject_message(prompt) -> bool` 把提示注入下一轮（gateway 与 CLI 均处理 async handler 的 30s 超时包装，见 `resolve_plugin_command_result`）。
