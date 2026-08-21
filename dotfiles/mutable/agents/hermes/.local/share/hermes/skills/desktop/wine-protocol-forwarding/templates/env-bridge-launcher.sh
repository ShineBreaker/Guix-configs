#!/usr/bin/env bash
# Wine → Linux browser environment bridge
# Fixes DBus/Display/Wayland address mismatch when Wine apps try to open URLs
#
# Problem: compositor (niri, sway, etc.) launched via `dbus-run-session` creates
# a private DBus bus. Wine children may inherit a different DBus address, causing
# the browser to not find the running instance → profile lock → "already running".
#
# Usage: Set Wine registry http/https handler to this script:
#   wine reg add "HKCR\https\shell\open\command" /ve /t REG_SZ \
#     /d "\"Z:\\home\\<user>\\.local\\bin\\env-bridge-launcher.sh\" \"%1\"" /f
#
# The script scans /proc for the running browser main process, extracts its
# environment variables, then delegates to xdg-open with corrected env.

LOG="/tmp/wine-browser-launcher.log"

echo "$(date): Called with args: $*" >> "$LOG"
echo "$(date): Incoming DBUS=$DBUS_SESSION_BUS_ADDRESS DISPLAY=$DISPLAY WAYLAND=$WAYLAND_DISPLAY" >> "$LOG"

# --- Find browser main process by scanning /proc ---
# Reliable across sandboxed environments where pgrep may not see all processes.
# Supports: zen, firefox, chrome/chromium, brave, vivaldi
BROWSER_PID=""
for pid in /proc/[0-9]*; do
    p="${pid##*/}"
    if [ -r "$pid/comm" ]; then
        comm=$(cat "$pid/comm" 2>/dev/null)
        case "$comm" in
            .zen-real|firefox|chrome|chromium|brave|vivaldi)
                cmdline=$(tr '\0' ' ' < "$pid/cmdline" 2>/dev/null)
                # Main process: no "-contentproc"/"--type=" child flags
                if ! echo "$cmdline" | grep -q -- "-contentproc\|--type=renderer\|--type=zygote\|parentPid"; then
                    BROWSER_PID="$p"
                    break
                fi
                ;;
        esac
    fi
done

if [ -n "$BROWSER_PID" ]; then
    echo "$(date): Found browser main process PID $BROWSER_PID" >> "$LOG"
    ENV_FILE="/proc/$BROWSER_PID/environ"

    # Extract and fix DBus address
    CORRECT_DBUS=$(tr '\0' '\n' < "$ENV_FILE" 2>/dev/null | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
    if [ -n "$CORRECT_DBUS" ] && [ "$CORRECT_DBUS" != "$DBUS_SESSION_BUS_ADDRESS" ]; then
        echo "$(date): Fixing DBUS: $DBUS_SESSION_BUS_ADDRESS → $CORRECT_DBUS" >> "$LOG"
        export DBUS_SESSION_BUS_ADDRESS="$CORRECT_DBUS"
    fi

    # Extract and fix DISPLAY
    CORRECT_DISPLAY=$(tr '\0' '\n' < "$ENV_FILE" 2>/dev/null | grep '^DISPLAY=' | cut -d= -f2-)
    if [ -n "$CORRECT_DISPLAY" ] && [ "$CORRECT_DISPLAY" != "$DISPLAY" ]; then
        echo "$(date): Fixing DISPLAY: $DISPLAY → $CORRECT_DISPLAY" >> "$LOG"
        export DISPLAY="$CORRECT_DISPLAY"
    fi

    # Extract and fix WAYLAND_DISPLAY
    CORRECT_WAYLAND=$(tr '\0' '\n' < "$ENV_FILE" 2>/dev/null | grep '^WAYLAND_DISPLAY=' | cut -d= -f2-)
    if [ -n "$CORRECT_WAYLAND" ] && [ "$CORRECT_WAYLAND" != "$WAYLAND_DISPLAY" ]; then
        echo "$(date): Fixing WAYLAND: $WAYLAND_DISPLAY → $CORRECT_WAYLAND" >> "$LOG"
        export WAYLAND_DISPLAY="$CORRECT_WAYLAND"
    fi

    # Extract and fix XDG_RUNTIME_DIR
    CORRECT_XDG_RUNTIME=$(tr '\0' '\n' < "$ENV_FILE" 2>/dev/null | grep '^XDG_RUNTIME_DIR=' | cut -d= -f2-)
    if [ -n "$CORRECT_XDG_RUNTIME" ] && [ "$CORRECT_XDG_RUNTIME" != "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR="$CORRECT_XDG_RUNTIME"
    fi
else
    echo "$(date): WARNING: No running browser found, using current env" >> "$LOG"
fi

URL="$1"
echo "$(date): Opening URL: $URL" >> "$LOG"
exec xdg-open "$URL"
