# QQ（qqbot）投递细节

## 配置确认（.env）

Hermes 的 QQ 平台适配器叫 `qqbot`（Tencent QQ 官方 Bot，sgroup.qq.com）。配置变量：

| 变量 | 说明 |
|------|------|
| `QQ_APP_ID` | Bot 应用 ID（本机：1904112724） |
| `QQ_CLIENT_SECRET` | Bot 密钥 |
| `QQ_ALLOW_ALL_USERS` | 是否放行所有用户（false = 白名单模式） |
| `QQ_ALLOWED_USERS` | 白名单 user id（逗号分隔） |
| `QQBOT_HOME_CHANNEL` | home channel user id——`deliver="qqbot"` 路由到这里 |

确认命令（注意 HERMES_HOME 可能已重定向，不要硬编码 ~/.hermes）：
```bash
grep -E "QQ_" "$HERMES_HOME/.env"
```

## 在线状态确认

`hermes gateway status` 只显示 gateway 进程本身，**不显示各平台连接详情**。看日志：

```bash
grep "QQBot" "$HERMES_HOME/logs/gateway.log" | tail -20
```

健康特征：`WebSocket connected to wss://api.sgroup.qq.com/websocket` + `Session resumed`。
每 30 分钟一次的 `Server requested reconnect (op 7)` + 重连成功是**正常现象**（QQ 服务端主动要求重连），不是故障。
`code=4009 Session timed out` 后自动重连也是正常的。

## deliver 取值

- `deliver="qqbot"` → 发到 `QQBOT_HOME_CHANNEL`
- cron 的 agent 最终回复自动投递，agent 不需要调用任何发送工具

## 用户偏好：报告格式（2026-08-13 明确）

用户原话：「设计更好的发送格式，QQ支持markdown语法」——即 **QQ 支持 markdown 渲染**，报告要按 markdown 设计，不要照搬 org 格式（`| 包名 | 版本 |` 竖线表格在手机上是一长串难读文本）。

本次定稿的巡检报告结构（可直接复用）：

```markdown
# 📦 软件包更新巡检
📅 <YYYY-MM-DD 星期>

> 摘要：<N 个频道有新活动 · M 个已声明包有上游新版本 · K 个 changelog 已抓取>

## 📡 频道活动

### guix (codeberg)
`<锁定短hash>` → `<HEAD短hash>`（+X commits, Y 开放 PR）

**命中已声明包的更新：**
- `<短hash>` gnu: mold: Update to 2.42.0 → 命中 **mold**
- PR #10511 ... → 命中 **sdl3**

## 🆙 已声明包的上游新版本

| 包名 | 当前版本 | 上游最新 | 来源 |
|------|---------|---------|------|
| **mold** | 2.41.0 | 2.42.0 | guix |

## 📝 值得关注的 changelog

### mold 2.41.0 → 2.42.0
- 新增 X feature
🔗 https://github.com/rui314/mold/releases
```

设计原则：
- emoji 分区标题（📦📡🆙📝）让手机扫读有锚点
- 表格只用短表格（4 列以内），包名加粗
- 每条结论附来源（commit hash / PR 号 / URL），抓不到标「未获取」，不臆造
- 频道活动/新版本/changelog 三层结构，B/C 层合并命中时去重
