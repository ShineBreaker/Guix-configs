# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function fish_command_not_found
    set -l cmd $argv[1]

    echo "fish: '$cmd' not found. Searching in Guix..." >&2

    set -l pkg (guix locate "$cmd" 2>/dev/null | grep /bin/ | head -1 | cut -d@ -f1)

    if test -z "$pkg"
        __fish_default_command_not_found_handler $cmd
        return $status
    end

    # 关键 hack：fish 的 not-found handler 拿不到原始参数，只能从 $history[1]
    # 取回整条命令行重拆 —— 复杂引号参数会被二次拆分（已知限制）
    set -l full_cmd_str $history[1]
    set -l full_cmd_list (string split " " -- $full_cmd_str)

    echo "Found '$cmd' in package '$pkg'. Executing..." >&2

    # -- 分界防止参数被 guix 吞掉
    guix shell $pkg -- $full_cmd_list
end

function try
    set -l cmd $argv[1]
    set -l pkg (guix locate "$cmd" 2>/dev/null | grep /bin/ | head -1 | cut -d@ -f1)

    if test -n "$pkg"
        echo "Running via guix shell $pkg..." >&2
        guix shell $pkg -- $argv
    else
        echo "Guix: Package for '$cmd' not found." >&2
        return 127
    end
end
