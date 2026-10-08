#!/usr/bin/env sh
# -*- mode: sh -*-
# Run a Quickshell shell inside a NESTED niri (a window on the user's live
# session) under a fully isolated HOME/XDG/dbus/runtime root, then grab and
# burst screenshots from it. For when acceptance depends on real-compositor
# behaviour that headless sway cannot show. The live session is attached to
# only: the target shell never runs in it and nothing is written to it.
#
# Usage:
#   nested-niri-verify.sh env      > $ISO/env.sh      # source this next
#   nested-niri-verify.sh boot     "$REPO"            # nested niri + readiness
#   nested-niri-verify.sh grab     "$ISO/shots/x.png" # one frame
#   nested-niri-verify.sh burst    "$ISO/shots" cold 30
#   nested-niri-verify.sh shell    start|"$QS_BIN" "$REPO"   # start/replace shell
#   nested-niri-verify.sh layers
#   nested-niri-verify.sh stop
#
# A foreground terminal call that needs `&` is rejected, and a half-lost session
# orphans compositors. Drive the whole sequence from one script and source the
# env file before every later call.

set -u

ISO=${ISO:-/tmp/nosd-niri-verify}
INCOMING="$ISO/shots/incoming"

iso_env() {
    # Unexport the live compositor fingerprint so a compositor service in the
    # shell cannot connect to the real one and read its windows.
    unset NIRI_SOCKET HYPRLAND_INSTANCE_SIGNATURE LABWC_PID
    HOME="$ISO/home"
    XDG_CONFIG_HOME="$ISO/config"
    XDG_CACHE_HOME="$ISO/cache"
    XDG_STATE_HOME="$ISO/state"
    XDG_DATA_HOME="$ISO/data"
    XDG_RUNTIME_DIR="$ISO/runtime"
    export HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME XDG_DATA_HOME \
           XDG_RUNTIME_DIR
}

mkcfg() {
    # The three settings that cost an afternoon if missed:
    #  - transform normal: winit outputs default to flipped vertically, so
    #    every screenshot comes out mirrored.
    #  - hotkey-overlay skip-at-startup: a fresh instance otherwise opens the
    #    "Important Hotkeys" window, and under winit `niri msg windows` returns
    #    [] so it cannot be closed over IPC.
    #  - screenshot-path into the isolated root, so nothing lands in the live
    #    Pictures dir (and so frames are easy to move out of the way).
    mkdir -p "$ISO/config/niri" "$ISO/shots/incoming"
    cat > "$ISO/config/niri/config.kdl" <<CFG
output "HEADLESS-1" {
    mode "1280x800"
    transform "normal"
}
layout {
    background-color "transparent"
}
prefer-no-csd
hotkey-overlay {
    skip-at-startup
}
screenshot-path "$INCOMING/%Y-%m-%d_%H-%M-%S.png"
CFG
}

boot() {
    REPO=${1:?usage: boot <repo path>}
    mkdir -p "$ISO"/{home,config/niri,config/nosdshell,cache/nosdshell,state,data,log,shots}
    chmod 700 "$ISO/runtime"

    # Pass the LIVE compositor socket as an absolute path: with
    # XDG_RUNTIME_DIR redirected, a relative WAYLAND_DISPLAY resolves in the
    # new runtime dir and the nested niri dies with NoCompositor.
    LIVE_WL=$(readlink -f /run/user/$(id -u)/wayland-1)

    mkcfg

    DBUSENV=$(ls -d /tmp/dbus-* 2>/dev/null | head -1)

    dbus-run-session -- sh -c "
        set -eu
        unset NIRI_SOCKET HYPRLAND_INSTANCE_SIGNATURE LABWC_PID
        export HOME='$ISO/home' XDG_CONFIG_HOME='$ISO/config' \
               XDG_CACHE_HOME='$ISO/cache' XDG_STATE_HOME='$ISO/state' \
               XDG_DATA_HOME='$ISO/data' XDG_RUNTIME_DIR='$ISO/runtime' \
               XDG_CURRENT_DESKTOP=niri WLR_BACKENDS=wayland \
               WAYLAND_DISPLAY='$LIVE_WL' DBUS_SESSION_BUS_ADDRESS='$DBUSENV'
        niri > '$ISO/log/niri.log' 2>&1 &
        echo \$! > '$ISO/runtime/niri.pid'
        i=0
        while [ \$i -lt 100 ]; do
            ls \$XDG_RUNTIME_DIR/niri.*.sock >/dev/null 2>&1 && exit 0
            kill -0 \$(cat '$ISO/runtime/niri.pid') 2>/dev/null || exit 1
            i=\$((i+1)); sleep 0.2
        done
        exit 1
    " || { echo "BOOT FAILED — see $ISO/log/niri.log"; tail -20 "$ISO/log/niri.log"; exit 1; }
    echo "nested niri: $(ls -1t "$ISO/runtime"/niri.*.sock | head -1)"
}

niritool() {
    # Talk to the NESTED instance only. Never the live one.
    NIRI_SOCKET=$(ls -1t "$ISO/runtime"/niri.*.sock 2>/dev/null | head -1)
    WAYLAND_DISPLAY=$(ls -1 "$ISO/runtime" 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)
    XDG_RUNTIME_DIR="$ISO/runtime"
    HOME="$ISO/home"
    NIRI_SOCKET="$NIRI_SOCKET" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" niri "$@"
}

# Take one frame and move it out of the landing dir immediately: the format
# resolves to seconds only, so a burst on the same second collapses to one file.
_grab_once() {
    niritool msg action screenshot-screen >/dev/null 2>&1
    i=0
    while [ $i -lt 40 ]; do
        for f in "$INCOMING"/*.png; do
            [ -f "$f" ] || continue
            sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
            # >2KB: a truncated/in-flight capture is smaller than a real frame
            if [ "$sz" -gt 2048 ]; then mv -f "$f" "$1" && return 0; fi
        done
        i=$((i+1)); sleep 0.05
    done
    echo "grab: no new frame in $INCOMING" >&2; return 1
}

case "${1:-}" in
  env)   # print an env source line; source it before every later call
      NIRI_SOCKET=$(ls -1t "$ISO/runtime"/niri.*.sock 2>/dev/null | head -1)
      WL=$(ls -1 "$ISO/runtime" 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)
      cat <<ENV
unset NIRI_SOCKET HYPRLAND_INSTANCE_SIGNATURE LABWC_PID
export HOME='$ISO/home' XDG_CONFIG_HOME='$ISO/config' XDG_CACHE_HOME='$ISO/cache'
export XDG_STATE_HOME='$ISO/state' XDG_DATA_HOME='$ISO/data' XDG_RUNTIME_DIR='$ISO/runtime'
export XDG_CURRENT_DESKTOP=niri WAYLAND_DISPLAY='$WL' NIRI_SOCKET='$NIRI_SOCKET'
ENV
      ;;
  boot)  boot "${2:-}" ;;
  layers)
      niritool msg --json layers | grep -o '"namespace":"[^"]*"' | sort -u
      ;;
  grab)  mkdir -p "$(dirname "$2")"; _grab_once "$2" && echo "ok $2 ($(stat -c%s "$2")B)" ;;
  burst) # burst <outdir> <prefix> <count>
      OUT=$2; PRE=$3; N=${4:-30}
      mkdir -p "$OUT" "$INCOMING"
      i=1
      while [ $i -le "$N" ]; do
          t="$OUT/$PRE-$(printf '%03d' $i).png"
          _grab_once "$t" || break
          i=$((i+1))
      done
      echo "$((i-1))/$N frames -> $OUT"
      ;;
  shell) # shell <qs-bin> <repo>  — start (or replace) the shell
      QS=${2:?usage: shell <qs-bin> <repo>}; REPO=${3:?usage: shell <qs-bin> <repo>}
      NIRI_SOCKET=$(ls -1t "$ISO/runtime"/niri.*.sock | head -1)
      WL=$(ls -1 "$ISO/runtime" | grep -E '^wayland-[0-9]+$' | head -1)
      kill "$(cat "$ISO/runtime/shell.pid" 2>/dev/null)" 2>/dev/null
      sleep 3
      env HOME="$ISO/home" XDG_CONFIG_HOME="$ISO/config" XDG_CACHE_HOME="$ISO/cache" \
        XDG_STATE_HOME="$ISO/state" XDG_DATA_HOME="$ISO/data" \
        XDG_RUNTIME_DIR="$ISO/runtime" NOSD_CONFIG_DIR="$ISO/config/nosdshell/" \
        XDG_CURRENT_DESKTOP=niri WAYLAND_DISPLAY="$WL" NIRI_SOCKET="$NIRI_SOCKET" \
        "$QS" -p "$REPO" > "$ISO/log/shell.log" 2>&1 &
      echo $! > "$ISO/runtime/shell.pid"
      i=0
      while [ $i -lt 120 ]; do
          "$QS" -p "$REPO" ipc call state all >/dev/null 2>&1 && { echo "shell ready (pid $(cat "$ISO/runtime/shell.pid"))"; exit 0; }
          kill -0 "$(cat "$ISO/runtime/shell.pid")" 2>/dev/null || { echo "shell died"; tail -25 "$ISO/log/shell.log"; exit 1; }
          i=$((i+1)); sleep 0.5
      done
      echo "shell timeout" >&2; exit 1
      ;;
  stop)
      kill "$(cat "$ISO/runtime/shell.pid" 2>/dev/null)" 2>/dev/null
      niritool msg action quit >/dev/null 2>&1
      kill "$(cat "$ISO/runtime/niri.pid" 2>/dev/null)" 2>/dev/null
      echo stopped
      ;;
  *)  sed -n '2,20p' "$0"; exit 2 ;;
esac
