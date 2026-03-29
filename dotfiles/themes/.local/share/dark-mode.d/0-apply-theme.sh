#!/usr/bin/env sh

## Apply dark theme
set -eu
"${HOME}/.config/darkman/script/set-theme.sh" dark

## Restart foot
pkill -u "$USER" --signal=SIGUSR1 ^foot$

## Restart waybar
herd restart waybar

## Set GNOME settings
guix shell glib:bin -- gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
guix shell glib:bin -- gsettings set org.gnome.desktop.interface gtk-theme 'Orchis-Teal-Dark'
guix shell glib:bin -- gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
