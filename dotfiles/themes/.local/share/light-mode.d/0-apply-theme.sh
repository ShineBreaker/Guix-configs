#!/usr/bin/env sh

## Apply dark theme
set -eu
"${HOME}/.config/darkman/script/set-theme.sh" light

## Restart foot
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/foot/initial-color-theme.ini"
rm -f "$CONFIG"
touch "$CONFIG"
echo 'initial-color-theme=light' > "$CONFIG"
pkill -u "$USER" --signal=SIGUSR2 ^foot$ || true

## Restart kitty
pkill -u "$USER" --signal=SIGUSR1 ^kitty$ || true

## Restart waybar
pkill -u "$USER" --signal=SIGHUP ^waybar$ || true

## Restart mako
makoctl reload || true

## Set GNOME settings
guix shell glib:bin -- gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
guix shell glib:bin -- gsettings set org.gnome.desktop.interface gtk-theme 'Orchis-Teal'
guix shell glib:bin -- gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Light'
