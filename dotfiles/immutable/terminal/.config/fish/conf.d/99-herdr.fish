# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# Foot 中自动进入 herdr（2026-07 从 tmux 迁移）。
# herdr 是独立 TUI 复用器，`herdr` 命令自带 attach/create 持久会话逻辑，
# 无需 tmux 时代的 session-selector fzf 选择器。
#
# 防护条件：
#   - 仅交互式 shell
#   - 仅 foot 终端（$TERM = foot）
#   - 不在 herdr 管理的 pane 内（HERDR_ENV=1，herdr 注入；防无限嵌套）
#   - 不在已有 tmux pane 内（$TMUX；过渡期避免干扰残留 tmux 会话）
#   - 不在容器内（$CONTAINER_ID）
if status is-interactive
    if test "$TERM" = foot
        and not set -q HERDR_ENV
        and not set -q TMUX
        and not set -q CONTAINER_ID
        exec herdr
    end
end
