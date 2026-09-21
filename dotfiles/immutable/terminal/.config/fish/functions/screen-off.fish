# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function screen-off -d "倒计时后关闭显示器（niri）"
    if test (count $argv) -gt 1
        echo "用法: screen-off [秒数]（默认 5）" >&2
        return 1
    end

    set -l seconds 5
    test (count $argv) -eq 1; and set seconds $argv[1]

    echo "$seconds 秒后关闭显示器，Ctrl-C 取消"
    # sleep 失败（如秒数非法）时不应继续熄屏，把状态透传给调用方
    sleep $seconds; or return $status
    niri msg action power-off-monitors
end
