<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

本文件为在本仓库中工作的 AI 助手提供统一指引。`CLAUDE.md` 是本文件的符号链接。

## 概述

以 Guix 为核心的个人系统配置仓库：

- `source/`：Guix System / Guix Home 的 Scheme 源配置和 org 文档
- `dotfiles/`：通过 Home 服务分发到用户目录的配置文件集合
- `tmp/`：`maak` 生成的完整配置（临时目录，不应手动编辑）
- `tools/`：辅助工具（含 crush-superpowers 子模块）

## 构建管线

```
source/configs/*.org
        │
        ▼  maak → Emacs org-babel-tangle（Noweb 拼合）
tmp/*.scm
        │
        ▼  guix time-machine --channels=channel.lock reconfigure
系统 / 用户环境
```

- Org 文件使用 Noweb `<<ref>>` 语法拼合代码块为完整 .scm
- `maak` 基于 Scheme 定义在 `maak.scm` 中，所有 guix 命令通过 `guix time-machine --channels=channel.lock` 锁定频道版本

## 工作优先级

1. 先看当前目录是否存在更近的 `AGENTS.md`（如 `source/AGENTS.md`）
2. 若修改 `dotfiles/mutable/emacs/.config/emacs/`，遵循其局部 `AGENTS.md`
3. 若 README 与实际文件不一致，以实际仓库结构和源码为准

## 文件路由表

| 任务类型   | 优先读取位置                                         | 子目录指引         |
| ---------- | ---------------------------------------------------- | ------------------ |
| 系统配置   | `source/configs/system-config.org` 头部的 Agent 专区 | `source/AGENTS.md` |
| 用户配置   | `source/configs/home-config.org` 头部的 Agent 专区   | `source/AGENTS.md` |
| Emacs 配置 | `dotfiles/mutable/emacs/.config/emacs/AGENTS.md`     | —                  |
| 全局变量   | `source/information.scm`                             | —                  |
| 频道定义   | `source/channel.scm`                                 | —                  |
| 静态模板   | `source/files/`                                      | `source/AGENTS.md` |
| dotfiles   | `dotfiles/<app>/`                                    | —                  |

<critical>
**路由指令**：
1. 遇到 Home/System 配置任务时，优先读取对应 org 文件头部的 Agent 专区 + `source/AGENTS.md`
2. 修改软件配置时，优先修改 `dotfiles/` 内的文件，再提醒用户运行 `maak home`
</critical>

## dotfiles 三层结构

```
dotfiles/
├── immutable/   # Guix Home 管理（只读，maak home 时自动部署）
│   ├── darkman/     desktop/     system/     terminal/     utilities/
├── mutable/     # GNU Stow 管理（可直接调试修改，maak home 时重链）
│   ├── emacs/   tmux/   zed/   noctalia/   ssh/
└── disable/     # 已禁用的旧配置（.config/ 下含 darkman/fuzzel/mako/niri/swayidle/swaylock/waybar）
```

- `immutable/`：通过 Guix Home 的 `home-dotfiles-service-type` 管理，构建时复制到 store
- `mutable/`：通过 `maak home` 中的 `stow-dotfiles` 函数用 GNU Stow 链接到 `$HOME`
- `disable/`：不再启用的配置文件，保留供参考

## 频道架构

| 频道      | 分支   | 职责         | URL（以 channel.scm 为准）                  |
| --------- | ------ | ------------ | ------------------------------------------- |
| guix      | master | 官方包集合   | `https://git.guix.gnu.org/guix.git`         |
| jeans     | main   | 个人自定义包 | `https://github.com/ShineBreaker/jeans.git` |
| nonguix   | master | 非自由软件   | `https://gitlab.com/nonguix/nonguix`        |
| pantherx  | master | 工具包       | `https://codeberg.org/gofranz/panther.git`  |
| rosenthal | trunk  | WM 增强组件  | `https://codeberg.org/hako/rosenthal.git`   |

频道版本锁定在 `source/channel.lock`，由 `maak upgrade` 自动更新并 git commit。**不要手动编辑 channel.lock。**

## 文件系统架构

- **根目录**：tmpfs（重启后清空）
- **持久化**：Btrfs 子卷挂载到 `/var/lib`、`/gnu`、`/var/cache` 等
- **用户数据**：`/data` 分区通过 bind-mount 映射到用户目录
- 子卷映射定义在 `source/information.scm` 的 `%btrfs-subvolumes`
- 用户数据目录列表定义在 `%data-dirs`

## 全局变量速查（information.scm）

| 变量                 | 类型   | 说明                             |
| -------------------- | ------ | -------------------------------- |
| `username`           | string | `"brokenshine"`                  |
| `fixed-machine-id`   | string | 基于 username 的 MD5 生成        |
| `%data-dirs`         | list   | 需要持久化的用户数据目录         |
| `%btrfs-subvol-data` | string | 数据分区子卷路径 `"DATA/Share"`  |
| `%btrfs-subvolumes`  | alist  | 子卷 → 挂载点映射                |
| `guix-channels`      | list   | 从 `channel.lock` 加载的频道列表 |

`information.scm` 被 `system-config.org` 和 `home-config.org` 通过 `(load "../source/information.scm")` 加载。

## maak 命令

<critical>
优先使用 `maak` 打包的命令。如果已有指令不满足需要且需大量反复使用，写入 `maak.scm`。
</critical>

```bash
maak init      # 安装系统到 /mnt
maak system    # guix system reconfigure（自动 tangle + time-machine + 括号检查）
maak home      # guix home reconfigure（自动括号检查 + stow mutable dotfiles）
maak rebuild   # system + home + locate --update
maak upgrade   # 更新 channel.lock + git commit -S
maak pull      # guix pull --allow-downgrades --fallback
maak clean     # 删除旧的系统/用户 generations
maak gc        # clean + guix gc + 清理旧 EFI
maak reuse     # 为所有文件添加 SPDX 版权头
maak nix       # 应用 Nix home-manager 配置
maak nix-init  # 初始化 Nix home-manager
maak nix-update # 更新 Nix flake
```

### 配置验证

<critical>
修改 `.org` 配置后，务必先用 dry-run 验证再实际应用。
</critical>

```bash
# Dry-run：tangle + 括号检查 + guix build --dry-run
MAAK_DRY_RUN=1 maak system   # 验证系统配置
MAAK_DRY_RUN=1 maak home     # 验证用户配置

# 单独括号平衡检查（不触发 guix）
maak check          # 检查 system + home
maak check-system   # 仅检查 system
maak check-home     # 仅检查 home
```

## Git 子模块

| 路径                                                    | 说明                                                        |
| ------------------------------------------------------- | ----------------------------------------------------------- |
| `dotfiles/mutable/emacs/.config/emacs`                  | Emacs 配置（codeberg.org/BrokenShine/.emacs.d）             |
| `dotfiles/immutable/utilities/.local/share/fcitx5/rime` | Rime 输入法配置（github.com/iDvel/rime-ice）                |
| `tools/crush-superpowers/main`                          | Crush superpowers 工作流工具（github.com/obra/superpowers） |

不要直接编辑子模块内容。

## Org Noweb 机制

`source/configs/*.org` 使用 Org Mode 的 Noweb 功能：

- `#+NAME: ref` 命名代码块
- `<<ref>>` 在其他代码块中引用（这**不是** Scheme 原生语法，是 Org Mode 功能）
- 最终由 `emacs --batch org-babel-tangle` 展开为完整 .scm 到 `tmp/`

## 风险点

- 不要手动编辑 `tmp/` 目录中的文件
- 优先修改 `source/` 中的源文件，修改顺序为 `home-config.org → system-config.org`
- **禁止直接修改 `~/.config/`、`~/.local/` 等安装位置的文件。** 所有配置必须修改 `dotfiles/` 中的源文件，再通过 `maak home` 生效
- `CLAUDE.md` 是 `AGENTS.md` 的符号链接，修改其中一个即同步修改另一个
- README 中的频道 URL 等信息可能滞后于 `channel.scm`，以 `.scm` 源码为准
