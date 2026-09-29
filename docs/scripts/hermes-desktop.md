<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# hermes-desktop — `hermes desktop` 子命令实体（FHS 容器）

- 源码：`dotfiles/mutable/agents/hermes/.local/libexec/hermes-desktop`
- 部署：`~/.local/libexec/hermes-desktop`（mutable；经 `hermes desktop` 分发或绝对路径直调）
- 调用方：`hermes desktop`、desktop 文件

## 用法

```bash
hermes desktop                 # 容器内启动 Electron 壳
hermes desktop --build-only    # 直调 venv 原生子命令打 release/linux-unpacked（不经本脚本）
```

## 依赖

`guix shell`（`--container --emulate-fhs`，复用 appimage-run 的 electron 库集）、`npm`/`electron-builder`（build-only，经 venv 原生）、`curl`（远程 session token 提取）、`dbus-launch`（宿主 bus 不可达时兜底）、hicolor 图标经 lib 安装。

## 工作原理

- **背景**：Pi 式 editable-checkout 方案下纯 checkout + uv 安装不含 build 过的 Electron 二进制；先 `hermes desktop --build-only` 用仓库内 npm + vite + electron-builder 打出 `release/linux-unpacked/Hermes`，再用 `guix shell --container --emulate-fhs` 补 Guix 缺的 FHS 系统库（libglib-2.0 等）跑起来。
- 流程：确保已 build（首跑 npm install 约 1300 包，几分钟；之后 node_modules 留在 checkout 内重 build 很快）→ 装 1024 px 图标 → `hermes_session_env_init` → `hermes_gui_env_resolve` → `hermes_build_share_flags`（**顺序不可换**：session init 提供 `WAYLAND_DISPLAY` 默认值，GUI 解析依赖它定 Ozone，share 旗标依赖 `RT_DIR`/`WAYLAND_DISPLAY`）。
- 容器内执行串（`EXEC_STRING`，单引号内 `${...}` 留给容器 bash 展开）：
  - Wayland 原生协议直连 compositor（`WAYLAND_DISPLAY` + RT_DIR socket 已 expose，不经 XWayland）。
  - 硬件 GPU：`/dev/dri` 读写挂入 + `--ignore-gpu-blocklist`（容器内 GPU 探测不全，Chromium 可能回退软件渲染）；崩时可 `LIBGL_ALWAYS_SOFTWARE=1 hermes desktop` 临时回退（变量已在 PRESERVE 正则透传）。
  - `--no-sandbox --disable-gpu-sandbox`：嵌套 guix shell 容器里 Chromium 沙箱起不来（渲染进程 crash loop），必需。
  - `--enable-wayland-ime`：Wayland text-input 协议，fcitx5 的 `libwaylandim.so` 经此与 Chromium 通信（Wayland 下必须显式开）。
  - `--gtk-version=3`：GTK3 初始化（原生文件对话框 + 主题集成）。
  - dbus：优先复用宿主 session bus（`DBUS_SESSION_BUS_ADDRESS` preserve + RT_DIR expose），不可达才 `dbus-launch`——dconf/GSettings 暗色偏好与 fcitx5 D-Bus frontend 依赖它。
- 远程 gateway：从远端 backend 页面提取 `__HERMES_SESSION_TOKEN__`（`curl` + grep），失败时告警并退回本地模式。

## 设计决策与不变量

- **`HERMES_CLI_BIN desktop --build-only` 直调 venv**：走 `bin/hermes` 会分发回本脚本造成死循环。
- **`curl | grep | sed` 管道须 `|| true`**：`pipefail` 下 token 缺失（后端可达但页面无 token）会让整个命令替换返回非零、脚本中途退出，到不了 fallback 告警（本次修复）。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 窗口起不来、渲染 crash | 容器沙箱或 GPU 探测 | 确认 `--no-sandbox` 等旗标在；试 `LIBGL_ALWAYS_SOFTWARE=1` |
| 中文输入无效 | 缺 `--enable-wayland-ime` | 检查 EXEC_STRING |
| 远程模式退回本地 | token 提取失败 | 查 backend 是否可达、页面是否含 session token |

## 变更记录

- 2026-09-29（修复）：远程 session token 提取管道补 `|| true`——旧代码在后端可达但页面无 token 时因 `pipefail` 直接退出，走不到「告警并退回本地」的预期 fallback。
