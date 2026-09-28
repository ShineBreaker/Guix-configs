#!/usr/bin/env bash
# 一体化分镜执行器：启动 Xvfb+应用 → 并行录制 → 执行驱动脚本 → 优雅停止
# 用法：run-shot.sh <shot-name> <driver-script>
set -u
NAME="$1"; DRIVER="$2"
DISP=${DISP:-120}
SHOTS=${SHOTS:-$HOME/Videos/emacs-demo/shots}
mkdir -p "$SHOTS"
OUT="$SHOTS/$NAME.mp4"

# ── 应用环境（按目标应用修改本段；store 路径随升级漂移，
#    readlink -f ~/.guix-home/profile/bin/emacs 找 profile，真实二进制在
#    emacs-next-pgtk store 目录 bin/.emacs-*-real）──
EMACS_PROFILE=/gnu/store/xmmcdkprqfvkg5k7kn6bf6v6fpi920lz-home-emacs-profile
EMACS_REAL=/gnu/store/4b9h2a80gxczn40iwl1w8lr1hbg83j0x-emacs-next-pgtk-32.0.50-1.2b02641/bin/.emacs-32.0.50-real

export DISPLAY=:$DISP
export PATH="$EMACS_PROFILE/bin:$PATH"
export EMACSLOADPATH="$EMACS_PROFILE/share/emacs/site-lisp:"
export EMACSNATIVELOADPATH="$EMACS_PROFILE/lib/emacs/native-site-lisp:"
export TREE_SITTER_GRAMMAR_PATH="$EMACS_PROFILE/lib/tree-sitter"
export ASPELL_DICT_DIR="$EMACS_PROFILE/lib/aspell"
export GIT_SSL_CAINFO="$EMACS_PROFILE/etc/ssl/certs/ca-certificates.crt"
export GIT_EXEC_PATH="$EMACS_PROFILE/libexec/git-core"
unset WAYLAND_DISPLAY

Xvfb :$DISP -screen 0 1920x1080x24 -nolisten tcp >/dev/null 2>&1 &
XPID=$!
cleanup() {
  kill -9 $XPID 2>/dev/null
  pkill -9 -f "Xvfb :$DISP" 2>/dev/null
  pkill -9 -f 'ffmpeg.*x11grab.*:12' 2>/dev/null
}
trap cleanup EXIT
sleep 3

# 录制模式补丁（templates/demo-inject.el）+ frame 拉满画布
setsid "$EMACS_REAL" \
  --load "$HOME/Videos/emacs-demo/work/demo-inject.el" \
  --eval '(progn (set-frame-position (selected-frame) 0 0) (set-frame-size (selected-frame) 215 54) (set-frame-position (selected-frame) 0 0))' \
  >/tmp/emacs-demo-emacs.log 2>&1 &
EPID=$!

# 等主窗口出现
for i in $(seq 1 40); do
  sleep 1
  xdotool search --name '^[A-Za-z*]' 2>/dev/null | grep -q . && break
done
W=$(xdotool search --name '^[A-Za-z*]' 2>/dev/null | tail -1)
xdotool windowsize "$W" 1920 1080
xdotool windowmove "$W" 0 0
xdotool windowfocus --sync "$W" 2>/dev/null
sleep 3

# 启动录制（后台，SIGINT 优雅收尾）
ffmpeg -y -hide_banner -loglevel error \
  -f x11grab -video_size 1920x1080 -framerate 30 -i :$DISP \
  -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
  "$OUT" >/tmp/ffmpeg-demo.log 2>&1 &
FPID=$!
sleep 2

# ── 执行分镜 ──
[ -f "$DRIVER" ] || { echo "driver not found"; kill -9 $FPID 2>/dev/null; exit 1; }
source "$(dirname "$0")/lib.sh"

START=$(date +%s)
mark "SHOT_START"
source "$DRIVER"
mark "SHOT_END"
END=$(date +%s)

# 停止录制（SIGINT 让 ffmpeg 正常写 moov）
kill -INT $FPID 2>/dev/null
for i in $(seq 1 20); do kill -0 $FPID 2>/dev/null || break; sleep 0.5; done
kill -9 $FPID 2>/dev/null
kill -9 $EPID 2>/dev/null

echo "SHOT $NAME duration=$((END-START))s -> $OUT"
ls -la "$OUT"
