<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# termide — VSCode 风格 tmuxifier 会话布局（Explorer | Editor / Terminal）

- 源码：`dotfiles/immutable/terminal/.config/tmuxifier/layouts/termide.session.sh`
- 部署：`~/.config/tmuxifier/layouts/termide.session.sh`（immutable，改后需 `blue home`）
- 调用方：`tmuxifier load-session termide`（或等价入口）

## 环境变量

| 变量 | 默认 | 含义 |
| ---- | ---- | ---- |
| `TERMIDE_SESSION_NAME` | `${session:-termide}` | 会话名 |
| `TERMINAL_IDE_ROOT` | `$PWD` | 工作根目录 |
| `TERMIDE_SIDEBAR_WIDTH` | `24` | Explorer 栏宽 |
| `TERMIDE_TERMINAL_HEIGHT` | `12` | 底部终端高 |
| `TERMIDE_EDITOR` | `hx` | 编辑器命令 |
| `TERMIDE_FILE_MANAGER` | `broot` | Explorer 命令 |
| `TERMIDE_SHELL` | `${SHELL:-/bin/sh}` | 终端 shell |
| `TERMIDE_DEBUG` | 空 | 非空时 `[termide] …` 调试输出到 stderr |

## 工作原理

tmuxifier `session.sh` 协议：建 `main` window → 按 `sidebar_size_raw` 拆出 Explorer pane → 主区纵向拆出 Editor / Terminal → 各 pane `send-keys` 启动 `broot`/`hx`/shell。`broot`/`hx` 不可用时 pane 留空 idle，不报错。

## 设计决策与不变量

- 宽高是原始数字，`split-window -l/-p` 语义由 tmuxifier 上下文决定。
- 命令缺失走 `command -v` 探测降级，保证最小环境也能起布局。

## 变更记录

- 2026-09-29：头部注释精简、变量表外移到本文件（行为不变）。
