<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# darkman 主题切换链路 — mode.d 入口 shim 与共享刷新实现

`dotfiles/immutable/noctalia-suite/` · immutable → `~/.local/libexec/` 与 `~/.local/share/{dark,light}-mode.d/`（改后须 `blue home`） · darkman daemon 按 mode.d 约定扫描执行

系统主题切换（darkman 事件驱动）时刷新整套桌面外观。两个 mode.d 入口各是一行 `exec` 的薄壳，真正的刷新逻辑集中在共享脚本里，两者共用同一套流程，只在开头的一个 `case` 分支上分叉。模板渲染器 `set-theme.sh` 是另一支，自成一篇见 [set-theme.md](set-theme.md)。

## {dark,light}-mode.d/0-apply-theme.sh

两个文件互为镜像，各一行实质内容：

```bash
exec "${HOME}/.local/libexec/theme-common.sh" dark   # light-mode.d 里是 light
```

### 部署约束

- **不能用 symlink**：immutable 包经 Guix Home 把**每个文件**复制成独立 store 项再软链到 `$HOME`——mode.d 目录里放 symlink 时，目标在 store 布局下解析不可靠，所以复制一份实体 shim 用 `exec` 转发。
- **必须绝对路径**：`$0` 的相对关系在部署形态下不存在（各文件是独立 store 项，包内相对层级不成立），故引用部署位置的绝对路径 `~/.local/libexec/theme-common.sh`。
- **住 libexec 不住 share**：共享实现是内部脚本，统一放 `libexec`；mode.d 下只留 darkman 约定必须存在的入口。
- darkman 约定该路径下的文件**必须存在且可执行**，缺了整个 hook 静默失效。

## theme-common.sh

```bash
theme-common.sh <dark|light>   # 参数不对 → usage + exit 1
```

**它是 `exec` 的可执行入口，不是被 `source` 的库**（自带 shebang 与 `set -eu`），因此不受 CONVENTIONS §4「被 source 的库文件不修改调用方 shell 选项、也不 `exit`」的约束。`set -eu` 保留：hook 作为独立进程运行，`exit` 与 shell 选项都不影响调用方——调用方已经 `exec` 进本进程了。

### dark / light 对照

| 步骤                    | dark            | light           | 取值来源             |
| ----------------------- | --------------- | --------------- | -------------------- |
| 日志标签 `log_tag`      | `dark`          | `light`         | `case` 分支          |
| `set-theme.sh` 渲染模板 | dark 变量组     | light 变量组    | 参数 `$mode`         |
| foot 重载信号           | `SIGUSR1`       | `SIGUSR2`       | `case` 分支          |
| noctalia 主题模式       | `dark`          | `light`         | 参数 `$mode`         |
| kitty 重载              | `SIGUSR1`       | `SIGUSR1`       | 字面量（两模式相同） |
| gsettings color-scheme  | `prefer-dark`   | `prefer-light`  | `case` 分支          |
| gsettings gtk-theme     | `adw-gtk3-dark` | `adw-gtk3`      | `case` 分支          |
| gsettings icon-theme    | `Papirus-Dark`  | `Papirus-Light` | `case` 分支          |
| GTK NotifyThemeChange   | `dbus-send`     | `dbus-send`     | 字面量（两模式相同） |

这张对照表只能从本节读：源码是分散的 `case` 分支加若干字面量调用，不存在集中的模式配置。全部输出（含各子命令的 stdout/stderr）追加记到 `$XDG_STATE_HOME/darkman/hook.log`，缺省 `~/.local/state/darkman/hook.log`。

### 失败降级

桌面刷新 hook 是「尽力而为」的刷新动作，不是构建管线——单步失败只记一行 `failed (exit N)`，不中断后续步骤。分三档：

| 调用                                     | 降级方式                                 |
| ---------------------------------------- | ---------------------------------------- |
| `set-theme.sh`（渲染模板）               | 裸调用；失败在 `set -eu` 下直接终止 hook |
| `pkill`（foot）、`makoctl reload`        | `\|\| true`，允许无目标                  |
| noctalia / kitty / gsettings / dbus 通知 | `run_optional` 包装，失败只记日志        |

`run_optional` 还会把「命令不存在」当降级：`kitty`、`guix`、`dbus-send` 各自 `command -v` 探测后写一条 `skipped` 日志。`gsettings` 经 `guix shell glib:bin --` 调用，所以连 guix 都没有时整段 gsettings 跳过。

### 时序与环境

- **wayland socket 必须自取**：darkman daemon 由 home-shepherd 启动，**未继承会话变量**，hook 里的 wayland 客户端（noctalia）拿不到 `WAYLAND_DISPLAY`，需从 `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wayland-*` 里扫描自取——跳过 `.lock`，只取 `-S` 的 socket。
- **kitty 信号必须在 noctalia 之后**：noctalia-shell 负责写 kitty 的主题文件 `themes/noctalia.conf`，而 kitty 的配置监控不追踪 include 文件，只能靠 `SIGUSR1` 重载。先发信号会读到上一个模式。noctalia 那步带 `timeout 5`，避免客户端卡死拖住整条 hook。
