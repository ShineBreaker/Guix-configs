#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# darkman dark-mode.d / light-mode.d hook 的共享实现。
# 两个 0-apply-theme.sh 只是薄 shim，exec 到本脚本并传入模式。
# 模式差异集中在下方 case，其余逻辑与模式无关。

set -eu

if [ "$#" -ne 1 ] || { [ "$1" != dark ] && [ "$1" != light ]; }; then
	printf 'Usage: %s <dark|light>\n' "${0##*/}" >&2
	exit 1
fi
mode=$1

case "$mode" in
	dark)
		log_tag=dark
		foot_signal=SIGUSR1
		color_scheme=prefer-dark
		gtk_theme=adw-gtk3-dark
		icon_theme=Papirus-Dark
		;;
	light)
		log_tag=light
		foot_signal=SIGUSR2
		color_scheme=prefer-light
		gtk_theme=adw-gtk3
		icon_theme=Papirus-Light
		;;
esac

# home-shepherd 启动的 darkman daemon 未继承会话变量；hook 调 noctalia
# 等 wayland 客户端需自取当前用户的 wayland socket。
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -d "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" ]; then
	for _d in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/wayland-*; do
		case "$_d" in *\.lock) continue ;; esac
		[ -S "$_d" ] || continue
		WAYLAND_DISPLAY="${_d##*/}"
		break
	done
fi
export WAYLAND_DISPLAY
unset _d

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG_DIR="${STATE_HOME}/darkman"
LOG_FILE="${LOG_DIR}/hook.log"

mkdir -p "$LOG_DIR"

log() {
	printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$log_tag" "$1" >>"$LOG_FILE"
}

run_optional() {
	description="$1"
	shift

	if "$@" >>"$LOG_FILE" 2>&1; then
		log "$description: ok"
	else
		status=$?
		log "$description: failed (exit $status)"
	fi
}

log "hook start"

"${HOME}/.config/darkman/script/set-theme.sh" "$mode" >>"$LOG_FILE" 2>&1
log "set-theme: ok"

pkill -u "$USER" --signal="$foot_signal" ^foot$ || true
log "foot reload signal sent"

if command -v kitty >/dev/null 2>&1; then
	run_optional "kitty config reload" pkill -u "$USER" --signal=SIGUSR1 ^kitty$
else
	log "kitty theme reload: skipped (kitty not found)"
fi

run_optional "noctalia-shell ${mode}Mode" timeout 5 noctalia msg theme-mode-set "$mode"

makoctl reload || true
log "mako reload requested"

if command -v guix >/dev/null 2>&1; then
	run_optional "gsettings color-scheme" guix shell glib:bin -- gsettings set org.gnome.desktop.interface color-scheme "$color_scheme"
	run_optional "gsettings gtk-theme" guix shell glib:bin -- gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
	run_optional "gsettings icon-theme" guix shell glib:bin -- gsettings set org.gnome.desktop.interface icon-theme "$icon_theme"
else
	log "gsettings: skipped (guix not found)"
fi

# 通知所有运行中的 GTK 应用刷新主题设置
if command -v dbus-send >/dev/null 2>&1; then
	run_optional "gtk notify theme change" dbus-send --session --dest=org.gtk.Settings --type=method_call /org/gtk/Settings org.gtk.Settings.NotifyThemeChange
else
	log "gtk theme notify: skipped (dbus-send not found)"
fi

log "hook end"
