#!/usr/bin/env bash
# run-electron.sh — launch a prebuilt Electron binary inside a Guix FHS container.
# Template: copy, set APP_BIN / MANIFEST, optionally prepend a build step.
#
# Why this shape (the three Electron-specific fixes baked in):
#   1. Real WAYLAND_DISPLAY (no hardcode wayland-0) — else expose a dead socket,
#      Electron can't reach compositor, window hangs.
#   2. GPU hardware rendering: --share=/dev/dri (READ-WRITE; a read-only --expose
#      makes the GPU process SIGILL on write ioctls) + --expose=/sys (mesa's
#      drmGetDevice needs sysfs) + --expose=/gnu/store (Guix mesa's DRI drivers
#      live at hardcoded store paths) + --ignore-gpu-blocklist. Verified: glxinfo
#      in-container shows the real GPU; Electron GPU process stable.
#      Emergency software fallback: run with LIBGL_ALWAYS_SOFTWARE=1 (preserved).
#   3. --expose=/etc/machine-id — FHS container /var /etc are read-only, so
#      dbus-uuidgen can't write; expose host's instead (cosmetic).
# Backend: X11/xwayland (stable in-container); needs DISPLAY + /tmp/.X11-unix.
set -euo pipefail

APP_BIN="${APP_BIN:-/path/to/release/linux-unpacked/AppName}"   # EDIT ME
MANIFEST="${MANIFEST:-./references/manifest.scm}"               # EDIT ME

RT_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

PRESERVE='^(DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|XDG_SESSION_TYPE|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|QT_QPA_PLATFORM|ELECTRON_OZONE_PLATFORM_HINT|PULSE_SERVER|PULSE_COOKIE|LANG|LC_[A-Z]+|LD_LIBRARY_PATH|NODE_OPTIONS|LIBGL_ALWAYS_SOFTWARE)$'

SHARE_FLAGS=(
  "--share=/tmp"
  "--share=${HOME}"
  "--expose=${RT_DIR}"
  "--expose=${RT_DIR}/${WAYLAND_DISPLAY}"
)
PULSE_DIR="${RT_DIR}/pulse/native"
[[ -S "${PULSE_DIR}" ]] && SHARE_FLAGS+=("--expose=${PULSE_DIR}")
[[ -e /etc/machine-id ]] && SHARE_FLAGS+=("--expose=/etc/machine-id")
[[ -n "${DISPLAY:-}" ]] && SHARE_FLAGS+=("--share=/tmp/.X11-unix")
# GPU 硬件渲染三件套（缺一回退软件渲染或崩）
[[ -d /dev/dri ]] && SHARE_FLAGS+=("--share=/dev/dri")     # 读写！只读 expose → SIGILL
[[ -d /sys ]] && SHARE_FLAGS+=("--expose=/sys")            # drmGetDevice 需 sysfs
[[ -d /gnu/store ]] && SHARE_FLAGS+=("--expose=/gnu/store") # mesa DRI 驱动在 store

EXEC_STRING='cd /appimage-root && \
export APPDIR=/appimage-root && \
export LD_LIBRARY_PATH=/appimage-root:${LD_LIBRARY_PATH} && \
export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-xcb} && \
export ELECTRON_OZONE_PLATFORM_HINT=${ELECTRON_OZONE_PLATFORM_HINT:-x11} && \
if command -v dbus-launch >/dev/null 2>&1; then \
  eval "$(dbus-launch --sh-syntax)"; \
fi && \
exec /appimage-root/AppName --no-sandbox --disable-gpu-sandbox --ozone-platform=x11 --ignore-gpu-blocklist --disable-dev-shm-usage "$@"'

exec guix shell --container --emulate-fhs --network \
  --manifest="${MANIFEST}" \
  --preserve="${PRESERVE}" \
  "${SHARE_FLAGS[@]}" \
  --share="$(dirname "${APP_BIN}")=/appimage-root" \
  -- bash -c "${EXEC_STRING}" bash "$@"
