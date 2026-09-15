# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function hotspot -d "一键启停 WiFi 热点（hotspot-ap / hostapd 直管 uap0）"
    set -l cmd $argv[1]

    switch "$cmd"
        case on
            # enable 幂等：respawn? #f 下 hostapd 进程退出后 shepherd 会把
            # 服务标 disabled，此时直接 start 会被拒
            sudo herd enable hotspot-ap; and sudo herd start hotspot-ap
        case off
            sudo herd stop hotspot-ap
        case status ""
            sudo herd status hotspot-ap
        case '*'
            echo "用法: hotspot on|off|status" >&2
            return 1
    end
end
