<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# dsh web — Web UI 启动实体

- 源码：`dotfiles/mutable/agents/dsh/.local/libexec/dsh-web`
- 部署：`~/.local/libexec/dsh-web`（mutable，改源即时生效；经 `dsh web` 分发触达，不占独立 bin 入口）
- 调用方：`dsh web` 子命令分发 + 桌面入口（stdin 是 `/dev/null`）

## 用法

```bash
dsh web                # 起服务（默认带远程信任）并开本机窗口
dsh web --reauth       # 强制重启服务换新 token（cookie 失效时用）
dsh web --remote-url   # 只打印手机首次握手的 https://<尾网主机名>/?token=... URL
dsh web --lan-off      # 本次不带 --trusted-host（DSH_TS_HOST= 的显式等价）
```

## 依赖

`ss`（端口/进程探测）、`setsid`（服务脱离会话）、`chromium`（或 `~/.guix-home/profile/bin/chromium`）、`notify-send`（可选，desktop 失败可见化）、CLI 本体 `$_cli_bin`（起服务直调，不经公共入口防递归）。

## 工作原理

- `DSH_HOME` 自行注入（niri 会话环境不经 fish conf.d，desktop 入口拿不到 export）。
- 窗口走 chromium `--app` 模式：无标签栏/地址栏，只留内容区；**不装 PWA**——dsh 自带 manifest 声明 `display=fullscreen`，装出来是全屏而非窗口。
- **认证**：launch token 按进程随机且一个 token 只换一次 cookie，只有本脚本亲自起的实例拿得到 token URL；「已在监听但不是本脚本起的」实例只能用 `--reauth` 重启换新。cookie 由 `DSH_HOME` 里持久化密钥签名（30 天，跨重启有效），之后直接开干净 URL。
- **远程（默认开启）**：实例永远带 `--trusted-host <尾网主机名>` 启动，配合 tailscale serve 反代（`https://<主机名>` → `127.0.0.1:$DSH_WEB_PORT`），尾网设备可远程操控同一实例（会话共享；cookie 按 authority 分离）。`DSH_TS_HOST=` 空串关闭。
- **窗口 app_id**：Wayland 下只由 profile 目录名决定（`chrome-<host>__-<profile>`），`--class` 对 app 窗口无效。定死 `--profile-directory=dsh` 得 `chrome-127.0.0.1__-dsh`，与 `dsh.desktop` 的 `StartupWMClass` 成对绑定（改名须两处同改）；该 profile 顺带隔离 dsh 会话 cookie 与日常浏览。
- **环境覆盖**：`DSH_WEB_PORT`（端口，改了 authority 也变）、`DSH_WEB_LOG`（服务 stdout，含一次性 token URL）、`DSH_BIN`（测试用；**默认必须指 CLI 本体**，指公共入口会经 `dsh web` 分发回本脚本造成递归）、`DSH_TS_HOST`。
- 服务以 `setsid -w` 脱离 desktop 会话；`kill -0` 轮询让子进程刚死就快速失败而不必等满超时。起服务失败时 `notify-send` critical 通知让 desktop 场景可见。
- `stop_server` 只终止 `/proc/<pid>/cmdline` 含 `@deepseek-ai/dsh` 的监听进程，拒绝杀第三方占端口的进程。

## 设计决策与不变量

- **`usage()` 不得回读自身注释**（历史实现 `sed -n 's/^# dsh web — //p' "$0"`——精简注释即自毁帮助；现为 heredoc）。
- **`--remote-url` 要求实例已带信任参数**：若监听中的实例缺 `--trusted-host`，须 `--reauth` 重启（服务端只认启动参数）。
- profile 断链自愈与 `bin/dsh` 同款，起服务前检测（dsh web 是长驻服务，UI 改完设置重启时才经过这里）。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 窗口打开要求重新登录 | token 已被消耗/换设备 | `dsh web --reauth` |
| 手机无法连 | 服务未带 `--trusted-host` | `dsh web --reauth`（或检查 `DSH_TS_HOST`） |
| 窗口出现非 dsh 的 app_id/图标串 | profile 目录名或 StartupWMClass 不一致 | 保持 `--profile-directory=dsh` 与 desktop 文件成对 |

## 变更记录

- 2026-09-29：`usage()` 从「`sed` 回读自身头注释」改为独立 heredoc（文本不变）；修复 `set -e` 下帮助输出依赖注释格式的隐患。
