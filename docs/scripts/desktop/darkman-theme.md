<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# 主题切换链路 — nosd-helpers portal 后端、mode.d 入口 shim 与共享刷新实现

`dotfiles/immutable/nosdshell/` · immutable → `~/.local/libexec/`、`~/.local/share/{dark,light}-mode.d/` 与 `~/.local/share/dbus-1/services/`（改后须 `blue home`） · 守护进程 `nosd-helpers portal run` 按 mode.d 约定扫描执行

系统主题切换（portal/darkman 事件驱动）时刷新整套桌面外观。两个 mode.d 入口各是一行 `exec` 的薄壳，真正的刷新逻辑集中在共享脚本里，两者共用同一套流程，只在开头的一个 `case` 分支上分叉。模板渲染器 `set-theme.sh` 是另一支，自成一篇见 [set-theme.md](set-theme.md)。

## nosd-helpers portal（daemon）

主题状态的权威进程，`nosd-helpers`（nosDshell 仓库 `tools/nosd-helpers`）的 `portal` 子命令。一个进程、一条会话总线连接同时持有三个名字：

| 总线名                                          | 接口                                                                                    | 消费方                                                                                     |
| ----------------------------------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `org.freedesktop.impl.portal.desktop.nosdshell` | `org.freedesktop.impl.portal.Settings`（`Read`/`ReadAll`/`Version=1`/`SettingChanged`） | xdg-desktop-portal → Electron/Chromium、GTK4/libadwaita 等 portal 跟随应用                 |
| `org.freedesktop.impl.portal.desktop.darkman`   | 同上（尽力持有的别名）                                                                  | 存量 `Settings=darkman` 的 portals.conf / `darkman.portal` 描述符                          |
| `nl.whynothugo.darkman`                         | `nl.whynothugo.darkman`（可写 `Mode` 属性 + `ModeChanged` 信号）                        | `self-theme.el` 等按 D-Bus 名订阅的 darkman 生态消费者（CLI 已迁至 `nosd-helpers portal`） |

状态真值持久化在 `~/.local/state/nosdshell/color-scheme`。一次切换固定四步：写盘 → `SettingChanged`/`ModeChanged`/`PropertiesChanged` 三信号 → 扫 `$XDG_DATA_HOME/{dark,light}-mode.d/` 跑全部可执行文件（darkman 钩子语义原样兼容，按文件名排序、逐串行）→ best-effort `nosdshell ipc call darkMode` 前推给 shell。对相同模式重复 `set` 会判重跳过，杜绝 shell↔daemon 回声环路。

**为什么要自研**：darkman 把 portal 后端名与 `nl.whynothugo.darkman` 注册成两个可独立激活的名字，并发 activation 会拉起两个 `darkman run` 各持一名、状态永久分裂（钩子双跑、toggle 与 portal 广播各认一个实例——「手动切换随机失灵」的根因，hook.log 实测同秒双份 `hook start` 持续数月）。内置 daemon 从结构上消除分裂：单实例靠 `$XDG_RUNTIME_DIR/nosd-portal.lock`（flock，后到者阻塞补位、兼作自动复活）+ 总线名占有检查双保险，并发 activation 收敛到一个进程。

**调度**：解析 `~/.config/darkman/config.yaml` 的 `lat`/`lng`（沿用 darkman 配置路径），NOAA 日出日落方程按本地时区计算边界，过界自动切换；`usegeoclue` 未实现（记一条日志，退回 `lat`/`lng`），`dbusserver`/`portal` 键分别控制 compat API 与 portal 后端的启停。

## nosd-portal-run

`~/.local/libexec/nosd-portal-run` 是 daemon 的唯一启动入口，本体只有两段：PATH 补齐 Guix profile bin → `exec nosd-helpers portal run`。单实例逻辑全在 daemon 内部，wrapper 只为解决 activation 环境缺 PATH 的问题（mode.d 钩子要调 gsettings/makoctl/dbus-send/jq）。

四处部署配合：

- `~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.nosdshell.service` 让 portal 后端名可激活。
- `…/{nl.whynothugo.darkman,org.freedesktop.impl.portal.desktop.darkman}.service` 提供 darkman 的两个兼容总线名（`darkman` 包已不再安装），旧 `Settings=darkman` 的 portals.conf 与按 D-Bus 名订阅的消费者零改动迁移。
- `~/.local/share/xdg-desktop-portal/portals/nosdshell.portal` 描述符（`UseIn=niri;`）配合 `portals.conf` 的 `Settings=nosdshell` 让 xdg-desktop-portal 找到后端。
- `~/.config/niri/config.kdl` 的 `spawn-sh-at-startup` 会话启动时提前拉起——否则没有任何应用查询 portal 或手动 toggle 的会话里，定时切换不会发生（daemon 尚未激活）。nosdshell 的 DarkModeService 在 helpers 就绪后也会幂等拉起一次（重复 spawn 由锁收敛）。

**`darkman` 包已不安装**（daemon 与 CLI 均已退役）：模式查询与切换用 `nosd-helpers portal get|set|toggle`；要手动拉起 daemon 就跑 `nosd-portal-run` 或 `nosd-helpers portal run`。

## {dark,light}-mode.d/0-apply-theme.sh

两个文件互为镜像，各一行实质内容：

```bash
exec "${HOME}/.local/libexec/theme-common.sh" dark   # light-mode.d 里是 light
```

### 部署约束

- **不能用 symlink**：immutable 包经 Guix Home 把**每个文件**复制成独立 store 项再软链到 `$HOME`——mode.d 目录里放 symlink 时，目标在 store 布局下解析不可靠，所以复制一份实体 shim 用 `exec` 转发。
- **必须绝对路径**：`$0` 的相对关系在部署形态下不存在（各文件是独立 store 项，包内相对层级不成立），故引用部署位置的绝对路径 `~/.local/libexec/theme-common.sh`。
- **住 libexec 不住 share**：共享实现是内部脚本，统一放 `libexec`；mode.d 下只留约定必须存在的入口。
- mode.d 目录语义与 darkman 相同：文件**必须存在且可执行**，缺了整个 hook 静默失效。

## theme-common.sh

```bash
theme-common.sh <dark|light>   # 参数不对 → usage + exit 1
```

**它是 `exec` 的可执行入口，不是被 `source` 的库**（自带 shebang 与 `set -eu`），因此不受 CONVENTIONS §4「被 source 的库文件不修改调用方 shell 选项、也不 `exit`」的约束。`set -eu` 保留：hook 作为独立进程运行，`exit` 与 shell 选项都不影响调用方——调用方已经 `exec` 进本进程了。

### 覆盖范围边界

本脚本只管模板管线与 portal 覆盖不到的散件：

| 步骤                    | dark             | light            | 取值来源     |
| ----------------------- | ---------------- | ---------------- | ------------ |
| 日志标签 `log_tag`      | `dark`           | `light`          | `case` 分支  |
| `set-theme.sh` 渲染模板 | dark 变量组      | light 变量组     | 参数 `$mode` |
| gsettings color-scheme  | `prefer-dark`    | `prefer-light`   | `case` 分支  |
| gsettings gtk-theme     | `adw-gtk3-dark`  | `adw-gtk3`       | `case` 分支  |
| gsettings icon-theme    | `Papirus-Dark`   | `Papirus-Light`  | `case` 分支  |
| mako 重载               | `makoctl reload` | `makoctl reload` | 字面量       |
| GTK NotifyThemeChange   | `dbus-send`      | `dbus-send`      | 字面量       |

全部输出（含各子命令的 stdout/stderr）追加记到 `$XDG_STATE_HOME/darkman/hook.log`，缺省 `~/.local/state/darkman/hook.log`。

**不再属于本脚本的职责**（改由 nosdshell 模板管线 + daemon 承担）：

- **kitty/foot**：主题文件由 nosdshell `activeTemplates` 渲染（`~/.config/{kitty/themes/nosdshell.conf,foot/themes/nosdshell}`），生成后 `nosd-helpers apply` 发信号——kitty `SIGUSR1` 全量重载；foot `SIGUSR1` 固定在 `[colors-dark]` 变体（生成的色板只写这一段，`initial-color-theme=dark` 与之配合）。不要对 foot 发 `SIGUSR2`：那会选中不存在的 `[colors-light]` 段导致配色失效。
- **nosdshell 内部状态**：daemon 每次切换后自行 `nosdshell ipc` 前推，hook 不再重复调。
- **Electron/GTK4**：portal `SettingChanged` 由 daemon 广播，`portals.conf` 指向 `Settings=nosdshell`。GTK3 应用只认 `settings.ini`/`gtk-theme`（set-theme.sh 渲染 + gsettings 写 + `NotifyThemeChange` 尽力通知），运行中进程能否重载取决于应用自身，多数要重启。

### 失败降级

桌面刷新 hook 是「尽力而为」的刷新动作，不是构建管线——单步失败只记一行 `failed (exit N)`，不中断后续步骤。分三档：

| 调用                       | 降级方式                                 |
| -------------------------- | ---------------------------------------- |
| `set-theme.sh`（渲染模板） | 裸调用；失败在 `set -eu` 下直接终止 hook |
| `makoctl reload`           | `\|\| true`，允许无目标                  |
| gsettings / dbus 通知      | `run_optional` 包装，失败只记日志        |

`run_optional` 还会把「命令不存在」当降级：`gsettings`、`dbus-send` 各自 `command -v` 探测后写一条 `skipped` 日志。`gsettings` 来自 home profile 的 `glib:bin`（直调，不包 `guix shell`——后者每次都要过一遍 profile 解析）。

### 时序与环境

- **wayland socket 自取兜底**：daemon 可经 D-Bus activation 拉起，会话变量取决于激活路径（`spawn-sh-at-startup`/`nosd-portal-run` 拉起时是规整后的环境），hook 里的 wayland 客户端不能依赖 `WAYLAND_DISPLAY` 在场——缺失时从 `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wayland-*` 扫一个 socket 出来，跳过 `.lock`、只取 `-S`。
- **shell→daemon 下推**：nosdshell `DarkModeService` 在任何 `darkMode` 变更（调度、IPC、设置 UI）时 `nosd-helpers portal set` 同步给 daemon，保证 portal 订阅者看到所有来源的切换；daemon 判重，不会回声。
