# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

function termide --description "Open the tmux-based terminal IDE workspace"
    if not command -q tmuxifier
        echo "tmuxifier 不存在，请确认系统已通过 Guix 安装 tmuxifier。" >&2
        return 127
    end

    if not command -q tmux
        echo "tmux 不存在，请确认系统已通过 Guix 安装 tmux。" >&2
        return 127
    end

    set -gx TERMINAL_IDE_ROOT (pwd)

    tmuxifier load-session termide
end
