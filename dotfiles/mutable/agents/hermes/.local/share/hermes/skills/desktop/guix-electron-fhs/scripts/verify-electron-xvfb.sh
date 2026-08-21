#!/usr/bin/env bash
# verify-electron-xvfb.sh — headless startup-path verifier for an Electron
# launcher that uses guix shell --container --emulate-fhs.
#
# Proves the binary: (a) finds its FHS libs, (b) doesn't SIGILL its GPU
# process, (c) reaches window creation without early-crash.
# It CANNOT prove a window is visible — Xvfb is a virtual framebuffer.
# Always tell the user the real-desktop window still needs their eye.
set -u
LAUNCHER="${1:-/home/brokenshine/.local/bin/hermes-desktop}"   # pass your launcher as $1
LOG="$(mktemp /tmp/hermes-verify-desktop-xvfb-XXXXXX.log)"
trap 'rm -f "$LOG"' EXIT

echo "=== Xvfb(:99) + launcher, 35s ==="
HERMES_DESKTOP=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  timeout 35 "$LAUNCHER" >"$LOG" 2>&1 &
PID=$!
sleep 25
if kill -0 $PID 2>/dev/null; then
  echo "  RUNNING -> container up, Electron alive (no early-crash)"
else
  echo "  EXITED -> see below for fatal near createWindow"
fi

echo "=== criteria ==="
grep -q "libglib-2.0.so.0: cannot open shared object file" "$LOG" \
  && echo "  FAIL: libglib missing" || echo "  PASS: libglib injected"
grep -qiE "GPUProcessTerminationStatus2.*mean = 4|SIGILL" "$LOG" \
  && echo "  WARN: GPU SIGILL (--disable-gpu not effective?)" \
  || echo "  PASS: no GPU SIGILL"
grep -qiE "createWindow|BrowserWindow|loadURL|app ready|install stamp" "$LOG" \
  && echo "  PASS: reached window creation / app-ready" \
  || echo "  WARN: no window-creation sign"

echo "=== tail ==="
tail -15 "$LOG" | sed 's/^/  /'
echo "=== done (Xvfb only; real window needs user desktop test) ==="
