#!/usr/bin/env sh

set -eu

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG_DIR="${STATE_HOME}/darkman"
LOG_FILE="${LOG_DIR}/hook.log"

mkdir -p "$LOG_DIR"

log() {
	printf '[%s] [light] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_FILE"
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

if command -v kitty >/dev/null 2>&1; then
	run_optional "kitty config reload" pkill -u "$USER" --signal=SIGUSR1 ^kitty$
else
	log "kitty theme reload: skipped (kitty not found)"
fi

pkill -u "$USER" --signal=SIGHUP ^waybar$ || true
log "waybar reload signal sent"

makoctl reload || true
log "mako reload requested"

if command -v guix >/dev/null 2>&1; then
	run_optional "gsettings color-scheme" guix shell glib:bin -- gsettings set org.gnome.desktop.interface color-scheme prefer-light
	run_optional "gsettings gtk-theme" guix shell glib:bin -- gsettings set org.gnome.desktop.interface gtk-theme Orchis-Teal
	run_optional "gsettings icon-theme" guix shell glib:bin -- gsettings set org.gnome.desktop.interface icon-theme Papirus-Light
else
	log "gsettings: skipped (guix not found)"
fi

log "hook end"
