#!/usr/bin/env sh

## Apply dark theme
set -eu
"${HOME}/.config/darkman/script/set-theme.sh" light

## Restart foot
pkill -u "$USER" --signal=SIGUSR2 ^foot$

## Restart waybar
herd restart waybar

## Set GNOME settings
guix shell glib:bin -- gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
guix shell glib:bin -- gsettings set org.gnome.desktop.interface gtk-theme 'Orchis-Teal'
guix shell glib:bin -- gsettings set org.gnome.desktop.interface icon-theme 'Papirus'
