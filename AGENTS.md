<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

本文件为在本仓库中工作的 AI 助手提供统一指引

## 概述

这是一个以 Guix 为核心的个人系统配置仓库：

- `source/`：Guix System / Guix Home 的 Scheme 源配置和 org 文档
- `dotfiles/`：通过 Home 服务分发到用户目录的配置文件集合，目录使用 `stow` 规范
- `tmp/`：`maak` 生成的完整配置（临时目录，不应手动编辑）

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

- Org 文件使用 Noweb 语法（`<<ref>>`）将代码块命名和引用，最终拼合为完整 .scm
- `maak` 是基于 Scheme 的任务运行器，定义在 `maak.scm`
- 所有 guix 命令通过 `guix time-machine --channels=channel.lock` 锁定频道版本

## 工作优先级

1. 先看当前目录是否存在更近的 `AGENTS.md`
2. 若修改 `dotfiles/emacs/.config/emacs/`，遵循其局部 `AGENTS.md`
3. 若 README 与实际文件不一致，以实际仓库结构和源码为准

## 文件路由表

| 任务类型   | 优先读取位置                                         | 子目录 AGENTS.md |
| ---------- | ---------------------------------------------------- | ---------------- |
| 系统配置   | `source/configs/system-config.org` 头部的 Agent 专区 | `source/`        |
| 用户配置   | `source/configs/home-config.org` 头部的 Agent 专区   | `source/`        |
| Emacs 配置 | `dotfiles/emacs/.config/emacs/AGENTS.md`             | —                |
| 全局变量   | `source/information.scm`                             | —                |
| 频道定义   | `source/channel.scm`                                 | —                |
| 静态模板   | `source/files/`                                      | —                |
| dotfiles   | `dotfiles/<app>/`                                    | —                |

<critical> 
**路由指令**：
1. 遇到 Home/System 配置任务时，优先读取对应 org 文件头部的 Agent 专区
2. 遇到 修改软件配置的任务时，优先修改 `dotfiles` 内的软件配置，再提醒用户运行 `maak home`
</critical>

## 频道架构

| 频道      | 分支   | 职责                                           |
| --------- | ------ | ---------------------------------------------- |
| guix      | master | 官方包集合和构建工具                           |
| jeans     | main   | 个人自定义包（codeberg.org/BrokenShine/jeans） |
| nonguix   | master | 非自由软件（主线内核、固件等）                 |
| rosenthal | trunk  | 窗口管理器增强（Limine 引导器等）              |

频道版本锁定在 `source/channel.lock`，通过 `maak upgrade` 更新

## 文件系统架构

- **根目录**：tmpfs（重启后清空）
- **持久化**：Btrfs 子卷挂载到 `/var/lib`、`/gnu`、`/var/cache` 等
- **用户数据**：`/data` 分区通过 bind-mount 映射到用户目录（Documents、Downloads 等）
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

## maak 命令

<critical> 
请务必优先使用已经包装好了的 `maak` 相关指令，
如果已有指令满足不了需求，并且需要大量反复使用的话，
可以写入到该文件中，方便后续调用
</critical>

```bash
maak init      # 安装系统到 /mnt
maak system    # guix system reconfigure（自动 tangle + time-machine）
maak home      # guix home reconfigure
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

## Git 子模块

| 路径                                       | 说明                |
| ------------------------------------------ | ------------------- |
| `dotfiles/fcitx5/.local/share/fcitx5/rime` | Rime 输入法配置     |
| `dotfiles/termide/`                        | tmux/tmuxifier 配置 |
| `dotfiles/emacs/.config/emacs/`            | Emacs 配置          |

不要直接编辑子模块内容。

## 风险点

- 不要手动编辑 `tmp/` 目录中的文件。
- 优先修改 `source/` 中的源文件，修改顺序为 `home-config.org -> system-config.org`。
