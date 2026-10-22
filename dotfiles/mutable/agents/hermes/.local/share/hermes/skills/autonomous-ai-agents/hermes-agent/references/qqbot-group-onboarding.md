# QQ 官方机器人：接入群聊与取 group_openid

适用对象：Hermes 的 `qqbot` 平台（QQ 开放平台官方机器人，适配器在 `plugins/platforms/qqbot/`），目标是把 bot 放进一个 QQ 群对话。

## 核心事实

- 群的标识是 `group_openid`，不是 QQ 群号。它按「AppID × 群」生成，不透明，无法从群号换算。
- 没有「列出机器人所在群」的接口：`GET /v2/users/@me/groups` 返回 `11001 不支持的调用`。能用的只有 `GET /v2/groups/{group_openid}/info`，前提是已经拿到 openid。
- 因此 openid 只能从**该群发来的一条事件**里取。

## 平台侧前置（q.qq.com，必须人工完成）

1. 沙箱配置 → 添加群：只能选自己当群主/管理员的群，沙箱群成员上限 20 人。
2. 群设置 → 群机器人 → 添加测试机器人。
3. 事件订阅勾选群@机器人消息（`GROUP_AT_MESSAGE_CREATE`）。
4. 群聊只有 @ 机器人时才触发，普通群消息不会到达 bot。

个人主体只能把机器人加到自己管理的群；公开加群能力只对企业主体开放。

## Hermes 侧配置键

```yaml
platforms:
  qqbot:
    extra:
      group_policy: allowlist        # open | allowlist | disabled | pairing(默认)
      group_allow_from: ["<group_openid>"]
```

- `group_allow_from` 可由环境变量 `QQ_GROUP_ALLOWED_USERS`（逗号分隔）注入。
- `group_policy` 没有环境变量（插件声明 `own_policy_env: ("", "")`），只能写 YAML。
- allowlist 匹配的是**群 openid**（`_entry_matches(self._group_allow_from, chat_id)`），不是成员 → 群内任何成员 @ 都能触发 agent。需要限制发话人时得另加 ACL，不要指望 group_allow_from。

## 取 group_openid 的路径

> `group_policy: pairing`（默认）会静默丢弃群消息，日志里不留任何痕迹，所以必须先临时放行。

1. 临时配置 `group_policy: open`，同时在 `.env` 加 `QQ_ALLOW_ALL_USERS=true`（缺这一条 gateway 会拒绝启动）。
2. `hermes gateway restart`。
3. 群里 @ 机器人发一条消息。
4. 从日志取 chat 字段：
   ```bash
   grep "inbound message: platform=qqbot" ~/.local/share/hermes/logs/gateway.log | tail -3
   # inbound message: platform=qqbot user=<member_openid> chat=<group_openid> ...
   ```
5. 立刻改回 `group_policy: allowlist` + `group_allow_from: ["<group_openid>"]`，删掉 `QQ_ALLOW_ALL_USERS`，再 `hermes gateway restart`。

上述机制（无列群接口、pairing 丢弃、open 需 allow-all 才可启动、日志字段位置）均来自源码与官方文档；完整流程未在本机端到端跑通，因为要先在开放平台把群加进沙箱。

## 备选：不改策略，加一行日志

在 `plugins/platforms/qqbot/adapter.py::_handle_group_message` 的第一行（policy 检查之前）加：

```python
logger.info("[%s] Group message: group_openid=%s member=%s", self._log_tag, group_openid, member)
```

重启后群里 @ 一次即可从日志读到 openid，不需要 open 窗口。代价：改的是 Hermes 源码，升级时会被覆盖。

## 陷阱

- 不要为了抓事件另起一个 `botpy.Client` 或 WebSocket 监听器：同一个 AppID 的 gateway 连接互斥，新连接会把正在运行的 Hermes 挤下线。
- 「群里发了没反应」的排查顺序：是否 @ 了机器人 → 群是否在沙箱名单 → `group_policy` 是不是 `pairing` → 最后才怀疑网络与凭据。
- 改 `config.yaml` 前注意它可能是 stow 符号链接，改动会出现在 dotfiles 仓库的工作区里；按用户习惯不要顺手提交或推送。
