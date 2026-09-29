<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# which-key — 快捷键速查 popup

- 源码：`dotfiles/immutable/terminal/.config/tmux/scripts/which-key`
- 部署：`~/.config/tmux/scripts/which-key`（immutable，改后需 `blue home`）
- 调用方：`tmux.conf` `bind ? run-shell "bash ~/.config/tmux/scripts/which-key"`

## 工作原理

纯静态文案：单条 `tmux display-popup -E -w 70% -h 64% -b rounded`，内容用一串 `printf` 拼出快捷键表。无参数、无状态、无副作用。

## 设计决策与不变量

- 文案与 `tmux.conf` 实际绑定是**手工同步**关系——改键位时要同时改这里的速查表（无自动对账）。
- `-E` 使 popup 内命令结束后自动关闭。

## 变更记录

- 2026-09-29：仅头部注释精简（行为不变）。
