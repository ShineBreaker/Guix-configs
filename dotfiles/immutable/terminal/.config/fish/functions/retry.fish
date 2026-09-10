# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function retry -d "命令失败时自动重试"
    set -l max_retries 5
    set -l attempt 0

    # sudo 保活：后台非交互续期，耗时重试只输一次密码；随登录 shell 退出自灭
    # ponytail: 60s 轮询（sudo 默认 5min 过期）；Ctrl-C 强行中断会残留，可 jobs/kill 清理
    set -l keeper 0
    if command -q sudo
        fish -c "while kill -0 $fish_pid 2>/dev/null; sudo -n true 2>/dev/null; sleep 60; end" &
        set keeper $last_pid
    end

    while true
        eval $argv
        if test $status -eq 0
            test $keeper -ne 0; and kill $keeper 2>/dev/null
            return 0
        end

        set attempt (math $attempt + 1)

        if test $attempt -ge $max_retries
            echo "已重试 $max_retries 次失败。是否继续重试？(y/n)"
            read -l response
            if test "$response" != "y"
                test $keeper -ne 0; and kill $keeper 2>/dev/null
                return 1
            end
            set attempt 0
        else
            echo "命令失败，正在重试 (第 $attempt 次)..."
        end
    end
end
