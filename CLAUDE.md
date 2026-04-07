<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

本文件为在本仓库中工作的 AI 助手提供统一指引。

## 概述

这是一个以 Guix 为核心的个人系统配置仓库：

- `source/`：Guix System / Guix Home 的 Scheme 源配置和 org 文档。
- `dotfiles/`：通过 Home 服务分发到用户目录的配置文件集合。
- `tmp/`：`maak` 生成的完整配置（临时目录，不应手动编辑）。

## 工作优先级

1. 先看当前目录是否存在更近的 `AGENT.md`。
2. 若修改 `dotfiles/emacs/.config/emacs/`，遵循其局部 `AGENT.md`。
3. 若 README 与实际文件不一致，以实际仓库结构和源码为准。

## 文件路由表

| 任务类型   | 优先读取位置                                         |
| ---------- | ---------------------------------------------------- |
| 系统配置   | `source/configs/system-config.org` 头部的 Agent 专区 |
| 用户配置   | `source/configs/home-config.org` 头部的 Agent 专区   |
| Emacs 配置 | `dotfiles/emacs/.config/emacs/AGENT.md`              |
| 全局变量   | `source/information.scm`                             |
| 频道定义   | `source/channel.scm`                                 |
| 静态模板   | `source/files/`                                      |
| dotfiles   | `dotfiles/<app>/`                                    |

**路由指令**：遇到 Home/System 配置任务时，优先读取对应 org 文件头部的 Agent 专区。

## 常用任务

```bash
maak init      # 安装系统到 /mnt
maak system    # guix system reconfigure
maak home      # guix home reconfigure
maak rebuild   # 先 system 再 home
```

## 全局 Do/Don't

**Do**：在最具体的模块中修改；保持 `(load ...)` 风格；必要时修正 README。

**Don't**：不要把 `tmp/*.scm` 当源码；不要直接编辑子模块；不要假设 README 文件名存在。

## 风险点

- `dotfiles/fcitx5/.local/share/fcitx5/rime` 是子模块。
- 不要手动编辑 `tmp/` 目录中的文件。
- 优先修改 `source/` 中的源文件。

## 验证建议

检查变量名、`load` 路径和括号层级一致；确认 dotfiles 路径与目标家目录一致。
