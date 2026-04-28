#!/usr/bin/env sh

set -eu

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG_DIR="${STATE_HOME}/darkman"
LOG_FILE="${LOG_DIR}/hook.log"

mkdir -p "$LOG_DIR"

log() {
	printf '[%s] [dark] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_FILE"
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

"${HOME}/.config/darkman/script/set-theme.sh" dark >>"$LOG_FILE" 2>&1
log "set-theme: ok"

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/foot/initial-color-theme.ini"
rm -f "$CONFIG"
touch "$CONFIG"
echo 'initial-color-theme=dark' >"$CONFIG"
log "foot config updated"

pkill -u "$USER" --signal=SIGUSR1 ^foot$ || true
log "foot reload signal sent"

if command -v kitty >/dev/null 2>&1; then
	run_optional "kitty config reload" pkill -u "$USER" --signal=SIGUSR1 ^kitty$
else
	log "kitty theme reload: skipped (kitty not found)"
fi

run_optional "noctalia-shell darkMode" timeout 5 noctalia-shell ipc --any-display call darkMode setDark

makoctl reload || true
log "mako reload requested"

if command -v guix >/dev/null 2>&1; then
	run_optional "gsettings color-scheme" guix shell glib:bin -- gsettings set org.gnome.desktop.interface color-scheme prefer-dark
	run_optional "gsettings gtk-theme" guix shell glib:bin -- gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
	run_optional "gsettings icon-theme" guix shell glib:bin -- gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark
else
	log "gsettings: skipped (guix not found)"
fi

log "hook end"
