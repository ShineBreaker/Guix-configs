<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# 脚本文档索引

本仓库自研脚本的手册索引。编写与维护规范（注释与文档的分工、单篇模板、同族归并规则、排版要求）：[`CONVENTIONS.md`](CONVENTIONS.md)。

同一族同构脚本合并为一篇，族文档用 `## <脚本名>` 分节；脚本头注释的文档指针相应写成 `docs/scripts/<族文档>.md §<脚本名>`。

## blue 本体与仓库工具

| 脚本                            | 源码                                     | 部署                      | 手册                                     |
| ------------------------------- | ---------------------------------------- | ------------------------- | ---------------------------------------- |
| blueprint.scm                   | `blueprint.scm`                          | 仓库根（blue 本体加载）   | [blueprint.md](blueprint.md)             |
| bootstrap.sh                    | `tools/bootstrap.sh`                     | 不部署                    | [blue-helpers.md](blue-helpers.md)       |
| build-image.scm                 | `tools/build-image.scm`                  | 不部署                    | [blue-helpers.md](blue-helpers.md)       |
| gen-partial.scm                 | `tools/gen-partial.scm`                  | 不部署                    | [blue-helpers.md](blue-helpers.md)       |
| doc-format.sh                   | `tools/doc-format.sh`                    | 不部署（format 编排）     | [doc-format.md](doc-format.md)           |
| doc-punct.py                    | `tools/doc-punct.py`                     | 不部署（format 标点一级） | [doc-punct.md](doc-punct.md)             |
| block-{list,extract,replace}.el | `tools/`                                 | 不部署（blueprint 调用）  | [org-block-tools.md](org-block-tools.md) |
| toolbox                         | `dotfiles/mutable/tools/toolbox/.local/` | mutable                   | [toolbox.md](toolbox.md)                 |

## agent 入口（`~/.local/bin`）

| 脚本                                                 | 源码                                               | 部署    | 手册                               |
| ---------------------------------------------------- | -------------------------------------------------- | ------- | ---------------------------------- |
| pi / pi-acp / pi-update                              | `dotfiles/mutable/agents/pi/.local/bin/`           | mutable | [pi.md](pi.md)                     |
| dsh / dsh-web / dsh-update / dsh-tui                 | `dotfiles/mutable/agents/dsh/.local/`              | mutable | [dsh.md](dsh.md)                   |
| hermes / hermes-acp / hermes-update / hermes-desktop | `dotfiles/mutable/agents/hermes/.local/`           | mutable | [hermes.md](hermes.md)             |
| mcode                                                | `dotfiles/mutable/agents/minimax-code/.local/bin/` | mutable | [minimax-code.md](minimax-code.md) |
| askill                                               | `dotfiles/mutable/agents/skills/.local/bin/`       | mutable | [askill.md](askill.md)             |

## 第三方二进制（`~/.local/bin`）

上游发行、无线仓库源码，手动落盘并按需在 `source/config.org` 声明常驻服务。

| 二进制          | 部署目标                                                              | 手册                       |
| --------------- | --------------------------------------------------------------------- | -------------------------- |
| quicktui-server | `~/.local/bin/` + `~/.config/quicktui-server-v2/`，home shepherd 常驻 | [quicktui.md](quicktui.md) |

## agent 闸门与钩子

| 脚本                          | 源码                                          | 部署                                              | 手册                                   |
| ----------------------------- | --------------------------------------------- | ------------------------------------------------- | -------------------------------------- |
| gate-core.sh + anchors-lib.sh | `dotfiles/immutable/agents/.config/agents/`   | immutable → `~/.config/agents/`（须 `blue home`） | [gate-core.md](gate-core.md)           |
| context-select.sh             | 同上                                          | 同上                                              | [context-select.md](context-select.md) |
| zcode hooks（3 个）           | `dotfiles/mutable/agents/zcode/.zcode/hooks/` | mutable → `~/.zcode/hooks/`                       | [zcode-hooks.md](zcode-hooks.md)       |

## 终端：fish

| 脚本                                                                      | 源码                                                    | 部署                            | 手册                                         |
| ------------------------------------------------------------------------- | ------------------------------------------------------- | ------------------------------- | -------------------------------------------- |
| 自定义函数（run/retry/screen-off/git-resign/jdk·jbuild·jrun/fish_prompt） | `dotfiles/immutable/terminal/.config/fish/functions/`   | immutable（须 `blue home`）     | [fish-functions.md](fish-functions.md)       |
| denv                                                                      | 同上                                                    | 同上                            | [denv.md](denv.md)                           |
| conf.d/*.fish（9 个启动碎片）                                             | `dotfiles/immutable/terminal/.config/fish/conf.d/`      | 同上                            | [fish-conf-d.md](fish-conf-d.md)             |
| completions/*.fish（17 个补全）                                           | `dotfiles/immutable/terminal/.config/fish/completions/` | 同上                            | [fish-completions.md](fish-completions.md)   |
| livecd fish_greeting / fish_prompt                                        | `source/files/livecd/.config/fish/functions/`           | Live ISO 内经 `local-file` 引用 | [misc-scripts.md](misc-scripts.md) §Live ISO |

## 终端：tmux

| 脚本                                                      | 源码                                                     | 部署                                       | 手册                                   |
| --------------------------------------------------------- | -------------------------------------------------------- | ------------------------------------------ | -------------------------------------- |
| session-selector / attach-entry / window-jump / which-key | `dotfiles/immutable/terminal/.config/tmux/scripts/`      | immutable（须 `blue home`）                | [tmux-scripts.md](tmux-scripts.md)     |
| sidebar-toggle                                            | 同上                                                     | 同上                                       | [sidebar-toggle.md](sidebar-toggle.md) |
| sidebar-render.scm + sidebar/*.scm                        | 同上                                                     | 同上                                       | [tmux-sidebar.md](tmux-sidebar.md)     |
| termide.session.sh                                        | `dotfiles/immutable/terminal/.config/tmuxifier/layouts/` | immutable → `~/.config/tmuxifier/layouts/` | [termide-layout.md](termide-layout.md) |

## 主题

| 脚本                                                     | 源码                                                        | 部署                       | 手册                                 |
| -------------------------------------------------------- | ----------------------------------------------------------- | -------------------------- | ------------------------------------ |
| `{dark,light}-mode.d/0-apply-theme.sh` + theme-common.sh | `dotfiles/immutable/noctalia-suite/.local/{libexec,share}/` | immutable → darkman mode.d | [darkman-theme.md](darkman-theme.md) |
| set-theme.sh                                             | `dotfiles/immutable/noctalia-suite/.config/darkman/script/` | immutable                  | [set-theme.md](set-theme.md)         |

## 桌面与系统零散脚本

niri 窗口切换与面板、非 NixOS GPU 链接、KeePassXC 凭据、ALSA 解静音兜底、Live ISO 的 fish 载荷合成一篇：[misc-scripts.md](misc-scripts.md)。全部在 `dotfiles/immutable/`，改源后须 `blue home`。

## emacs

| 脚本                     | 源码                                            | 部署    | 手册                                     |
| ------------------------ | ----------------------------------------------- | ------- | ---------------------------------------- |
| configctl + configctl.el | `dotfiles/mutable/emacs/.config/emacs/scripts/` | mutable | [emacs-configctl.md](emacs-configctl.md) |

配置本身的工作手册在 `dotfiles/mutable/emacs/.config/emacs/AGENTS.md`。

## 专题手册（不在本目录）

| 主题                                        | 手册                                             |
| ------------------------------------------- | ------------------------------------------------ |
| blue 不可用时的应急部署与纯手动命令序列     | [`docs/emergency-blue.md`](../emergency-blue.md) |
| Live ISO 自主打包                           | [`docs/iso-build.md`](../iso-build.md)           |
| Chroot 救援（tmpfs 根 + LUKS + Btrfs 子卷） | [`docs/rescue-chroot.md`](../rescue-chroot.md)   |
| 加密入仓配置管理                            | [`docs/secrets.md`](../secrets.md)               |

## 子模块

`tools/linux-setup/` 为子模块，文档在其自身 `docs/`（保持子模块自包含）：索引见 [`tools/linux-setup/docs/README.md`](../../tools/linux-setup/docs/README.md)（justfile 全 recipe、六个 scripts/ 脚本、AI 容器专题）。其余子模块的文档同理，父仓库索引链接过去，不复制内容。

## config.org 内嵌脚本

内嵌脚本不进 `docs/`：按 CONVENTIONS §5 写在 `source/config.org` 代码块旁的 org 正文里。按 `#+NAME:` 块名检索（`blue block-show <块名>` 可单独提取）：

| 块名                                                | 内容                                                               |
| --------------------------------------------------- | ------------------------------------------------------------------ |
| `maint-check` / `maint-dry-rebuild` / `maint-build` | 文件头的维护操作 Babel 块                                          |
| `flatpak-service-helpers`                           | `%flatpak-update-script`：flatpak 定时更新的启动脚本               |
| `mihomo-run`                                        | 解密订阅、渲染模板并 exec mihomo                                   |
| `nm-dispatcher-trusted-connection`                  | NetworkManager dispatcher：可信 WiFi 接口进出 nftables 集合        |
| `ac-power-services`                                 | `ac-power-profile` 电源档位脚本与 `ac-power-init`                  |
| `usb-power-services`                                | USB `power/control` 权限 udev 规则                                 |
| `root-services`                                     | `beesd-run` 启动包装                                               |
| `50-hibernate.rules`                                | polkit 休眠授权规则（JavaScript）                                  |
| `fish-cfg`                                          | fish 交互 shell 集成模板                                           |
| `usb-power-watch`                                   | 熄屏 USB 挂起守护                                                  |
| `clipsync`                                          | X11 与 Wayland CLIPBOARD 双向同步守护（Guile）                     |
| `kb-backup-script`                                  | hermes 与 Org 知识库每日自动 commit                                |
| `gnupg-home-fixup-script`                           | `tmp/gnupg-home-fixup`：GNUPGHOME 收敛 700 + 清外主机 dotlock 残留 |
