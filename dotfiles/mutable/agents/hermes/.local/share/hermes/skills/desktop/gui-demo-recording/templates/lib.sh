#!/usr/bin/env bash
# 分镜驱动公共工具集：由 run-shot.sh source，driver 脚本直接使用。
# driver 脚本可用的变量：$W（应用主窗口 id）、$U（键内延时微秒）。

# ── 打点：绝对时间戳，供字幕对轴 ──
TIMELINE=${TIMELINE:-/tmp/emacs-demo-timeline.log}
: > "$TIMELINE" 2>/dev/null || true

mark() { echo "$(date +%s.%N) $1" >> "$TIMELINE"; }

# ── 按键辅助（XTEST；组合键键内间隔 U 微秒）──
U=${U:-100000}

key()    { xte "key $1"; }
ctrl()   { xte "keydown Control_L" "usleep $U" "key $1" "usleep $U" "keyup Control_L"; }
alt()    { xte "keydown Alt_L" "usleep $U" "key $1" "usleep $U" "keyup Alt_L"; }
shift()  { xte "keydown Shift_L" "usleep $U" "key $1" "usleep $U" "keyup Shift_L"; }
cshift() { xte "keydown Control_L" "keydown Shift_L" "usleep $U" "key $1" "usleep $U" "keyup Shift_L" "keyup Control_L"; }
calt()   { xte "keydown Control_L" "keydown Alt_L" "usleep $U" "key $1" "usleep $U" "keyup Alt_L" "keyup Control_L"; }
ret()    { xte "key Return"; }
esc()    { xte "key Escape"; }
tab()    { xte "key Tab"; }
spc()    { xte "key space"; }
type()   { xte "usleep 120000" "str $(printf '%q' "$1")" "usleep 120000"; }
wait()   { sleep "$1"; }

# 逐字符输入（真人打字观感）
type_slow() {
  local s="$1" c i
  for ((i=0;i<${#s};i++)); do
    c="${s:$i:1}"
    xte "str $(printf '%q' "$c")"
  done
}

# 带打点的等待：wait_mark <秒> <标签>
wait_mark() { mark "$2"; sleep "$1"; }

export W U TIMELINE
