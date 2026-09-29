<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# window-jump — fzf 跨 session 窗口跳转

- 源码：`dotfiles/immutable/terminal/.config/tmux/scripts/window-jump`
- 部署：`~/.config/tmux/scripts/window-jump`（immutable，改后需 `blue home`）
- 调用方：`tmux.conf` `bind f display-popup -E -w 80% -h 60% -b rounded "~/.config/tmux/scripts/window-jump"`

## 用法

在 popup 内运行：`tmux list-windows -a` 收集所有 session 的窗口 → fzf 选择 → 选中项与当前 session 不同则 `switch-client`，同 session 则 `select-window`。ESC 取消无动作。

## 依赖

`tmux`、`fzf`（popup 环境内）。

## 设计决策与不变量

- 列表格式含 session 名与 window 名，fzf 输出解析回 window id 后跳转。
- 必须经 `display-popup` 运行（需要交互 TTY）；独立调用会阻塞等待输入。

## 变更记录

- 2026-09-29：仅头部注释精简（行为不变）。
