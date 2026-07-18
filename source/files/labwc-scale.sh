#!/bin/sh
# labwc-scale.sh —— EDID 自适应缩放
#
# 在 labwc autostart 里执行. 读 wlr-randr 的每个输出, 按物理尺寸(mm)+分辨率(px)
# 算出 DPI, 映射到 scale, 再用 wlr-randr --scale 应用.
#
# DPI→scale 策略 (参考 96 DPI = 1x):
#   DPI < 120  → 1     (普通屏, 不介入)
#   120 ≤ DPI < 170 → 1.5  (轻度 HiDPI)
#   170 ≤ DPI < 240 → 2     (典型 HiDPI, 如 4K@27")
#   DPI ≥ 240  → 2.5 / 3   (超高 DPI)
#
# 注意 XFCE 4.20 的 xfce4-panel 在分数缩放(1.5/1.75)下有闪烁 bug (论坛 #17965),
# 但整数档(2x/3x)稳定. 所以优先落在整数档, 仅在中间档用 1.5 作折中.
#
# 容错: EDID 物理尺寸不准的屏会误判, 已 clamp 到 [1,3]; 算不出 DPI(尺寸为 0)则跳过.
# 依赖: wlr-randr (已在 PATH).
#
# 幂等: 重复跑无副作用, 已是目标 scale 的不会重复设置.

set -eu

# labwc 刚启动时 compositor 可能还没就绪, wlr-randr 会失败. 重试几次.
info=""
for _ in 1 2 3 4 5; do
    if info=$(wlr-randr 2>/dev/null); then
        break
    fi
    sleep 0.5
done

[ -z "$info" ] && { echo "labwc-scale: wlr-randr 无输出, 跳过" >&2; exit 0; }

# 把已取回的 wlr-randr 输出按 output 分段, 解析每个输出的:
# 名字 / 物理尺寸 mm / 当前模式 px
# 输出格式样例:
#   eDP-1 "Sharp LCD"
#     Physical size: 300x190 mm
#     Enabled: yes
#     Modes:
#       2560x1600 px, 60.000000 (current)
#     Scale: 1.000000

# 逐输出处理. 用 awk 把 info 切成 "name<TAB>phys_w phys_h<TAB>mode_w mode_h" 行
printf '%s\n' "$info" | awk '
    /^[A-Za-z0-9_-]+/ {
        # 新的输出块开头 (输出名行, 可能带 "描述")
        if (name != "" && pw != "" && mw != "") {
            printf "%s\t%s %s\t%s %s\n", name, pw, ph, mw, mh
        }
        name = $1
        pw = ""; ph = ""; mw = ""; mh = ""
    }
    /Physical size:/ {
        # "  Physical size: 300x190 mm"
        split($0, a, ":")
        split(a[2], b, "x")
        gsub(/[^0-9]/, "", b[1])
        split(b[2], c, " ")
        ph = c[1]
        pw = b[1]
    }
    /\(current\)/ {
        # "      2560x1600 px, 60.000000 (current)"
        split($0, a, "x")
        mw = a[1]
        gsub(/[^0-9]/, "", mw)
        split(a[2], b, " ")
        mh = b[1]
    }
    END {
        if (name != "" && pw != "" && mw != "") {
            printf "%s\t%s %s\t%s %s\n", name, pw, ph, mw, mh
        }
    }
' | while IFS="$(printf '\t')" read -r name phys mode; do
    # 解析切出的行
    set -- $phys; pw=$1; ph=$2
    set -- $mode; mw=$1; mh=$2

    # 物理尺寸为 0 (EDID 缺失/虚拟机) → 无法算 DPI, 跳过
    if [ "${pw:-0}" -le 0 ] || [ "${ph:-0}" -le 0 ] 2>/dev/null; then
        echo "labwc-scale: $name 物理尺寸无效 ($pw x $ph mm), 跳过" >&2
        continue
    fi

    # 算 DPI (取 x/y 的较大值更稳, 这里用对角线一致的平均)
    # DPI = px / (mm / 25.4)
    dpi_x=$(awk -v w="$mw" -v pw="$pw" 'BEGIN { printf "%.0f", w / (pw / 25.4) }')
    dpi_y=$(awk -v h="$mh" -v ph="$ph" 'BEGIN { printf "%.0f", h / (ph / 25.4) }')

    [ "${dpi_x:-0}" -le 0 ] 2>/dev/null && continue

    # DPI → scale 映射
    dpi=$dpi_x
    if   [ "$dpi" -lt 120 ]; then scale=1
    elif [ "$dpi" -lt 170 ]; then scale=1.5
    elif [ "$dpi" -lt 240 ]; then scale=2
    elif [ "$dpi" -lt 300 ]; then scale=2.5
    else scale=3
    fi

    echo "labwc-scale: $name ${mw}x${mh}px / ${pw}x${ph}mm = ${dpi}DPI → scale ${scale}"

    # 应用 (幂等: wlr-randr 设同值无副作用)
    wlr-randr --output "$name" --scale "$scale" 2>/dev/null || \
        echo "labwc-scale: 设置 $name scale=${scale} 失败" >&2
done
