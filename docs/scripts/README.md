<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# 脚本文档索引

本仓库所有自研脚本的文档索引。编写与维护规范（注释/文档分工、模板、可靠性要求）：[`docs/scripts/CONVENTIONS.md`](CONVENTIONS.md)。

## 构建与运维

| 脚本 | 源码路径 | 部署方式 | 文档 |
| --- | --- | --- | --- |
| bootstrap.sh | `tools/bootstrap.sh` | 不部署（仓库内直接运行） | [bootstrap.md](bootstrap.md) |
| emergency-blue.sh | `tools/emergency-blue.sh` | 自建 ISO 系统 PATH + 仓库内 | [`docs/emergency-blue.md`](../emergency-blue.md) |
| rescue-chroot.sh | `tools/rescue-chroot.sh` | 自建 ISO 系统 PATH + 仓库内 | [`docs/rescue-chroot.md`](../rescue-chroot.md) |
| block-list.el / block-extract.el / block-replace.el | `tools/` | 不部署（blueprint.scm 调用） | [org-block-tools.md](org-block-tools.md) |
| build-image.scm | `tools/build-image.scm` | 不部署（blueprint.scm 调用） | [build-image.md](build-image.md) |
| gen-partial.scm | `tools/gen-partial.scm` | 不部署（blueprint.scm 调用） | [gen-partial.md](gen-partial.md) |
| doc-punct.py | `tools/doc-punct.py` | 不部署（blue format 后端） | [doc-punct.md](doc-punct.md) |
| blueprint.scm | `blueprint.scm` | 仓库根（blue 本体加载） | [blueprint.md](blueprint.md) |

## ~/.local/bin 入口

| 脚本 | 源码路径 | 部署方式 | 文档 |
| --- | --- | --- | --- |
| secrets | `dotfiles/mutable/tools/secrets/.local/bin/` | mutable → `~/.local/bin/`（改源即时生效） | [`docs/secrets.md`](../secrets.md) |
| toolbox（+ tools.yaml） | `dotfiles/mutable/tools/toolbox/.local/` | mutable | [toolbox.md](toolbox.md) |
| hermes / hermes-acp / hermes-lib.sh | `dotfiles/mutable/agents/hermes/.local/` | mutable | [hermes.md](hermes.md) |
| hermes-update | `dotfiles/mutable/agents/hermes/.local/libexec/` | mutable（经 `hermes update` 分发） | [hermes-update.md](hermes-update.md) |
| hermes-desktop | 同上 | mutable（经 `hermes desktop` 分发） | [hermes-desktop.md](hermes-desktop.md) |
| pi / pi-acp | `dotfiles/mutable/agents/pi/.local/bin/` | mutable | [pi.md](pi.md) |
| pi-update | 同上 | mutable（`.bin-entries-allow` 声明的第二入口） | [pi-update.md](pi-update.md) |
| dsh（+ dsh-tui） | `dotfiles/mutable/agents/dsh/.local/` | mutable | [dsh.md](dsh.md) |
| dsh-web | `dotfiles/mutable/agents/dsh/.local/libexec/` | mutable（经 `dsh web` 分发） | [dsh-web.md](dsh-web.md) |
| dsh-update | 同上 | mutable（经 `dsh update` 分发） | [dsh-update.md](dsh-update.md) |
| askill | `dotfiles/mutable/agents/skills/.local/bin/` | mutable | [askill.md](askill.md) |
| niri-app-switcher | `dotfiles/immutable/desktop/.local/bin/` | immutable → `~/.local/bin/`（须 `blue home`） | [niri-app-switcher.md](niri-app-switcher.md) |
| niri-quake-toggle | 同上 | 同上 | [niri-quake-toggle.md](niri-quake-toggle.md) |
| keepassxc-credential-setup | `dotfiles/immutable/utilities/.local/bin/` | immutable | [keepassxc-credential-setup.md](keepassxc-credential-setup.md) |
| nixgpu-update | 同上 | 同上 | [nixgpu-update.md](nixgpu-update.md) |

## agent 闸门与钩子

| 脚本 | 源码路径 | 部署方式 | 文档 |
| --- | --- | --- | --- |
| gate-core.sh | `dotfiles/immutable/agents/.config/agents/` | immutable → `~/.config/agents/`（须 `blue home`） | [gate-core.md](gate-core.md) |
| anchors-lib.sh | 同上 | 同上 | [anchors-lib.md](anchors-lib.md) |
| context-select.sh | 同上 | 同上 | [context-select.md](context-select.md) |
| crush bash-gate.sh | `dotfiles/immutable/agents/.config/crush/hooks/` | immutable → `~/.config/crush/hooks/` | [crush-bash-gate.md](crush-bash-gate.md) |
| crush edit-gate.sh | 同上 | 同上 | [crush-edit-gate.md](crush-edit-gate.md) |
| crush LSP/MCP 转发器（11 个） | `dotfiles/immutable/agents/.config/crush/bin/` | immutable → `~/.config/crush/bin/` | [crush-bin-wrappers.md](crush-bin-wrappers.md) |
| zcode bash-gate.sh | `dotfiles/mutable/agents/zcode/.zcode/hooks/` | mutable → `~/.zcode/hooks/`（改源即时生效） | [zcode-bash-gate.md](zcode-bash-gate.md) |
| zcode edit-gate.sh | 同上 | 同上 | [zcode-edit-gate.md](zcode-edit-gate.md) |
| zcode session-start.sh | 同上 | 同上 | [zcode-session-start.md](zcode-session-start.md) |

## 主题

| 脚本 | 源码路径 | 部署方式 | 文档 |
| --- | --- | --- | --- |
| theme-common.sh | `dotfiles/immutable/noctalia-suite/.local/libexec/` | immutable → `~/.local/libexec/` | [theme-common.md](theme-common.md) |
| set-theme.sh | `dotfiles/immutable/noctalia-suite/.config/darkman/script/` | immutable → `~/.config/darkman/script/` | [set-theme.md](set-theme.md) |
| dark/light 0-apply-theme.sh | `dotfiles/immutable/noctalia-suite/.local/share/{dark,light}-mode.d/` | immutable → mode.d 路径 | [darkman-mode-hooks.md](darkman-mode-hooks.md) |

## fish

| 脚本 | 源码路径 | 部署方式 | 文档 |
| --- | --- | --- | --- |
| denv.fish | `dotfiles/immutable/terminal/.config/fish/functions/` | immutable → `~/.config/fish/`（须 `blue home`） | [denv.md](denv.md) |
| fish_prompt.fish | 同上 | 同上 | [fish-prompt.md](fish-prompt.md) |
| git-resign.fish | 同上 | 同上 | [git-resign.md](git-resign.md) |
| java_tools.fish（jdk/jbuild/jrun） | 同上 | 同上 | [java-tools.md](java-tools.md) |
| retry.fish | 同上 | 同上 | [retry.md](retry.md) |
| run.fish | 同上 | 同上 | [run.md](run.md) |
| screen-off.fish | 同上 | 同上 | [screen-off.md](screen-off.md) |
| conf.d/*.fish（9 个启动碎片） | `dotfiles/immutable/terminal/.config/fish/conf.d/` | 同上 | [fish-conf-d.md](fish-conf-d.md) |
| completions/*.fish（16 个补全） | `dotfiles/immutable/terminal/.config/fish/completions/` | 同上 | [fish-completions.md](fish-completions.md) |

## tmux

| 脚本 | 源码路径 | 部署方式 | 文档 |
| --- | --- | --- | --- |
| which-key | `dotfiles/immutable/terminal/.config/tmux/scripts/` | immutable → `~/.config/tmux/scripts/`（须 `blue home`） | [which-key.md](which-key.md) |
| window-jump | 同上 | 同上 | [window-jump.md](window-jump.md) |
| attach-entry | 同上 | 同上 | [attach-entry.md](attach-entry.md) |
| session-selector | 同上 | 同上 | [session-selector.md](session-selector.md) |
| sidebar-toggle | 同上 | 同上 | [sidebar-toggle.md](sidebar-toggle.md) |
| sidebar-render.scm + sidebar/*.scm | 同上 | 同上 | [tmux-sidebar.md](tmux-sidebar.md) |
| termide.session.sh | `dotfiles/immutable/terminal/.config/tmuxifier/layouts/` | immutable → `~/.config/tmuxifier/layouts/` | [termide-layout.md](termide-layout.md) |

## emacs

| 脚本 | 源码路径 | 部署方式 | 文档 |
| --- | --- | --- | --- |
| configctl + configctl.el | `dotfiles/mutable/emacs/.config/emacs/scripts/` | mutable → `~/.config/emacs/scripts/`（改源即时生效） | [emacs-configctl.md](emacs-configctl.md) |

## 其他

| 脚本 | 源码路径 | 部署方式 | 文档 |
| --- | --- | --- | --- |
| 40-force-unmute.lua | `dotfiles/immutable/system/.config/wireplumber/scripts/40-alsa/` | immutable → WirePlumber scripts（须 `blue home`） | [wireplumber-force-unmute.md](wireplumber-force-unmute.md) |
| livecd fish_greeting/fish_prompt | `source/files/livecd/.config/fish/functions/` | Live ISO 内经 `local-file` 引用 | [livecd-fish.md](livecd-fish.md) |

## linux-setup

`tools/linux-setup/` 为子模块，文档在其自身 `docs/`（保持子模块自包含）：索引见 [`tools/linux-setup/docs/README.md`](../../tools/linux-setup/docs/README.md)（justfile 全 recipe、六个 scripts/ 脚本、AI 容器专题）。

## config.org 内嵌脚本

内嵌脚本不进 `docs/`：按 CONVENTIONS §5 写在 `source/config.org` 代码块旁的 org 正文里。按 `#+NAME:` 块名检索（`blue block-show <块名>` 可单独提取）：

| 块名 | 内容 |
| --- | --- |
| `maint-check` / `maint-dry-rebuild` / `maint-build` | 文件头的维护操作 Babel 块 |
| `flatpak-service-helpers` | `%flatpak-update-script`：flatpak 定时更新的启动脚本 |
| `mihomo-run` | 解密订阅、渲染模板并 exec mihomo |
| `nm-dispatcher-trusted-connection` | NetworkManager dispatcher：可信 WiFi 接口进出 nftables 集合 |
| `ac-power-services` | `ac-power-profile` 电源档位脚本与 `ac-power-init` |
| `usb-power-services` | USB `power/control` 权限 udev 规则 |
| `root-services` | `beesd-run` 启动包装 |
| `50-hibernate.rules` | polkit 休眠授权规则（JavaScript） |
| `fish-cfg` | fish 交互 shell 集成模板 |
| `usb-power-watch` | 熄屏 USB 挂起守护 |
| `kb-backup-script` | hermes 与 Org 知识库每日自动 commit |
