<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# theme-common.sh — darkman dark/light 两个 mode.d hook 的共享实现

- 源码：`dotfiles/immutable/noctalia-suite/.local/libexec/theme-common.sh`
- 部署：`~/.local/libexec/theme-common.sh`（immutable，改后须 `blue home`）
- 调用方：`~/.local/share/{dark,light}-mode.d/0-apply-theme.sh` 薄 shim `exec` 本脚本并传模式（见 [darkman-mode-hooks.md](darkman-mode-hooks.md)）

## 用途

系统主题切换（darkman 事件驱动）时执行一整套桌面刷新：渲染模板 → 终端重载 → GTK 设置 → GTK 通知。两个模式的差异集中在开头的 `case`（log 标签、foot 信号、color-scheme、gtk-theme、icon-theme），其余逻辑与模式无关。

## 用法

```bash
theme-common.sh <dark|light>   # 参数不对 → usage + exit 1
```

## 依赖

`pkill`、`noctalia`（可选）、`kitty`（可选）、`makoctl`、`guix`（可选，`gsettings` 经 `guix shell glib:bin` 调用）、`dbus-send`（可选）、`set-theme.sh`（必需）。

## 工作原理（dark/light 对照）

| 步骤                     | dark         | light        |
| ------------------------ | ------------ | ------------ |
| `set-theme.sh` 渲染模板  | dark 变量组   | light 变量组  |
| foot 重载信号            | `SIGUSR1`    | `SIGUSR2`    |
| noctalia 主题模式        | `dark`       | `light`      |
| kitty 重载               | `SIGUSR1`    | `SIGUSR1`    |
| gsettings color-scheme   | `prefer-dark`| `prefer-light`|
| gsettings gtk-theme      | `adw-gtk3-dark` | `adw-gtk3` |
| gsettings icon-theme     | `Papirus-Dark` | `Papirus-Light` |
| GTK NotifyThemeChange    | dbus-send    | dbus-send    |

全部输出记 `$XDG_STATE_HOME/darkman/hook.log`（默认 `~/.local/state/darkman/hook.log`）。

## 设计决策与不变量

- **可执行入口而非 source 库**：本脚本被 shim `exec`（自带 shebang 与 `set -eu`），不是被 source 的库——CONVENTIONS §4 把
  `theme-common.sh` 列进「被 source 的库文件」是名单级误列，实际形态与 `anchors-lib.sh` 不同（它确是被 source）。
  `set -eu` 保留：hook 作为独立进程运行，`exit`/选项不影响调用方（调用方已 exec 进本进程）。
- **wayland socket 自取**：home-shepherd 启动的 darkman daemon 未继承会话变量，hook 里的 wayland 客户端
  （noctalia）需从 `XDG_RUNTIME_DIR/wayland-*` 自取 socket（跳过 `.lock`、只取 `-S` socket）。
- **kitty 信号在 noctalia 之后**：noctalia-shell 负责写 kitty 主题文件（`themes/noctalia.conf`），而 kitty 的
  配置监控不追踪 include 文件，只能靠 `SIGUSR1` 重载；信号必须等 noctalia 写完再发，否则 kitty 读到上一个模式。
- **失败不阻断**：`run_optional` 包住一切外部调用——单步失败只记 `failed (exit N)` 不中断后续步骤；
  `pkill`/`makoctl` 等允许无目标的调用加 `|| true`。hook 面向「尽力而为」的桌面刷新，不是构建管线。

## 变更记录

- 2026-10：重构——模式对照表与 wayland/kitty 时序说明迁入本文档，注释压缩；行为不变（静态审查，未执行——桌面副作用环境）。
