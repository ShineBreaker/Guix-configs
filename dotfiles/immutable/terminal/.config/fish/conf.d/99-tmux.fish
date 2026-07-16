# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

if status is-interactive
    # Foot 中自动进入 tmux；容器和已有 tmux pane 保持普通 shell。
    if test "$TERM" = foot; and not set -q TMUX; and not set -q CONTAINER_ID
        set -l cwd (pwd)
        set -l window_name (path basename "$cwd" | string replace -r '[^a-zA-Z0-9_-]' '_')

        if test -z "$window_name"
            set window_name default
        else if test (string length "$window_name") -gt 20
            set window_name (string sub -l 20 "$window_name")
        end

        if tmux has-session 2>/dev/null
            set -l choice (~/.config/tmux/scripts/session-selector)
            switch "$choice"
                case ESC
                    return
                case NEW
                    exec tmux new-session -s "term_$fish_pid" -n "$window_name" -c "$cwd"
                case '*'
                    exec tmux attach-session -t "$choice"
            end
        else
            exec tmux new-session -s main -n "$window_name" -c "$cwd"
        end
    end
end
