# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# Foot 中自动进入 herdr（2026-07 从 tmux 迁移）。
#
# herdr 默认所有窗口连到同一个 default server，操作会同步。为复刻 tmux 多
# server 的隔离体验，这里调用 herdr-session-selector 让用户选择会话：
# 命名 session（herdr --session <name>）各有独立 server/socket，互不同步。
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

        set -l selector ~/.config/herdr/scripts/herdr-session-selector

        # 选择器未部署时的 fallback：直接进 default 共享会话
        if not test -x "$selector"
            exec herdr
        end

        set -l choice ("$selector")

        # 选择器异常（无输出）→ 留在普通 shell
        if test -z "$choice"
            return
        end

        switch "$choice"
            case ESC
                # 用户取消 → 留在普通 shell
                return
            case NEW
                # 新建独立会话（唯一名，互不同步）
                exec herdr --session "term_$fish_pid"
            case DEFAULT
                # 进入 default 共享会话（多窗口同步）
                exec herdr
            case '*'
                # attach 已有命名会话
                exec herdr --session "$choice"
        end
    end
end
