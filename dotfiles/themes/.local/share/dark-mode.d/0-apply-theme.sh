#!/usr/bin/env sh

## Apply dark theme
set -eu
"${HOME}/.config/darkman/script/set-theme.sh" dark

## Restart foot
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/foot/initial-color-theme.ini"
rm -f "$CONFIG"
touch "$CONFIG"
echo 'initial-color-theme=dark' > "$CONFIG"
pkill -u "$USER" --signal=SIGUSR1 ^foot$

## Restart waybar
pkill -u "$USER" --signal=SIGHUP ^waybar$

## Set GNOME settings
guix shell glib:bin -- gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
guix shell glib:bin -- gsettings set org.gnome.desktop.interface gtk-theme 'Orchis-Teal-Dark'
guix shell glib:bin -- gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
