# Hermes Desktop Remote gateway 模式 — 详细机制

2026-08-01 实战（Guix-configs 仓库，hermes v0.19.0 / release 2026.7.20）。
症状：desktop 里 agent 的工具环境残缺（没有 guix/git/blue 等）。根因与完整解法
见 SKILL.md 对应 section；本文件沉淀源码级细节，供再排查时免去重新翻源码。

## 架构：desktop 壳与后端的关系

- desktop 壳（Electron main process）默认 spawn 自己的 headless 后端：
  `apps/desktop/electron/backend-command.ts` 的 `serveBackendArgs()` 生成
  `hermes serve --host 127.0.0.1 --port 0`（端口 0 = OS 随机分配）。
- `hermes serve` 与 `hermes dashboard --no-open` **是同一个 headless gateway**：
  backend-command.ts 注释明确 "Both produce the exact same headless gateway;
  serve is just the decoupled name"。旧 runtime 无 `serve` 子命令时自动回退
  dashboard 形态，所以宿主上已有的 dashboard(9119) shepherd 服务可直接复用。
- 容器（guix shell --container --emulate-fhs --network）内 spawn 的 serve 继承
  容器环境 → 残缺。容器与宿主共享网络栈 → 容器内访问宿主 127.0.0.1 直连。

## env override 路径（main.ts，v0.19.0）

`resolveRemoteBackend(profile)` 优先级（main.ts:6367 起）：

1. per-profile override（connection.json `profiles[name]`）
2. **env override**（main.ts:6381-6394）：
   - `HERMES_DESKTOP_REMOTE_URL` + `HERMES_DESKTOP_REMOTE_TOKEN` 必须成对出现，
     只设 URL 会 throw "Both must be provided to connect to a remote Hermes backend"
   - 只作用于全局/主连接，per-profile scope 不会被 env override
3. global remote（connection.json `mode: 'remote'`）

env override 生效后返回 `buildRemoteConnection(url, 'token', token, 'env')`，
desktop 不再启动本地 serve。auth 模式由 `/api/status` 的 `auth_required` 字段
判定（`connection-config.ts` `authModeFromStatus`）：false → token，true → oauth。

## token 认证机制（hermes_cli/web_server.py）

- `_SESSION_TOKEN = os.environ.get("HERMES_DASHBOARD_SESSION_TOKEN") or secrets.token_urlsafe(32)`
  —— 不显式设置则每次进程启动随机生成；进程退出即失效。
- 注入首页 HTML：`window.__HERMES_SESSION_TOKEN__ = "<token>"`
  （desktop 侧解析逻辑见 `apps/desktop/electron/dashboard-token.ts`）。
- REST 认证：`X-Hermes-Session-Token` 头（或 legacy `Authorization: Bearer`）。
- WS 认证：`?token=` query param。
- 历史坑：issue #38412（2026-06）——packaged Electron 连远程 gateway 的 WS 被
  4403 拒，根因是 `_ws_request_is_allowed` 的 loopback-peer 检查与 file:///null
  Origin 检查互斥。修复 PR #40408 "bypass Host/Origin guard for authenticated
  WS connections" 已合入 v0.19.0，本方案（loopback bind + token）不受影响。

## 启动脚本实现（hermes-desktop launcher，dotfiles/mutable）

```bash
REMOTE_BASE="http://127.0.0.1:9119"
if curl -sf -m 2 -o /dev/null "${REMOTE_BASE}/api/status"; then
  _session_token="$(curl -sf -m 2 "${REMOTE_BASE}/" \
    | grep -oE '__HERMES_SESSION_TOKEN__="[^"]+"' | head -1 \
    | sed -E 's/.*="([^"]+)"/\1/')"
  if [[ -n "${_session_token}" ]]; then
    export HERMES_DESKTOP_REMOTE_URL="${REMOTE_BASE}"
    export HERMES_DESKTOP_REMOTE_TOKEN="${_session_token}"
  fi
fi
```

要点：
- grep 匹配 `__HERMES_SESSION_TOKEN__="..."` 子串即可（带不带 `window.` 前缀都中）。
- 两个 env 必须加入 `--preserve` 正则（guix shell 只透传匹配的变量）。
- `set -euo pipefail` 下 `curl -sf` 在 if 条件里失败不会退出，安全。
- 抓 token 前先探测 `/api/status`，避免首页 404 时误报。

## 验证（无 GUI 也能证明逻辑）

探测段逻辑（非整个容器）可用 mock server 覆盖四条路径：
1. `/api/status` 200 + 首页含 token → env 正确注入
2. `/api/status` 200 + 首页无 token → env 不设置（回退）
3. `/api/status` 不可达 → env 不设置（回退）
4. `bash -n` 语法

mock：`python3 -m http.server` 不行（响应不可控），用内联
`http.server.BaseHTTPRequestHandler` 按 path 分发（/api/status 与 /）。验证后清理
临时目录。WS 握手可用 `curl -H "X-Hermes-Session-Token: $TOKEN" .../api/ws`：
404=token 有效（非 upgrade 请求过了 auth gate），401=被拦。

## 遗留边界

- hermes-backend 重启 → token 变 → 正在跑的 desktop 断连，重开 desktop 即恢复。
- 若想彻底消除：config.org 的 hermes-backend 服务里固定
  `HERMES_DASHBOARD_SESSION_TOKEN`（涉及 secret 管理，未做）。
- 用户工作流约定：Guix-configs 仓库中**新服务必须加进 config.org 纳管**
  （shepherd service），不能随手 nohup/tmux 起；动手前先查现有服务是否已覆盖。
