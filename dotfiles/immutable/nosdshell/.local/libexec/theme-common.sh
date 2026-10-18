#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# theme-common.sh — nosd-helpers portal 的 dark/light mode.d hook 共享实现
#（0-apply-theme.sh 薄 shim exec 本脚本并传模式；mode.d 目录语义与 darkman
# 兼容）。用法、部署形态与失败降级见 docs/scripts/darkman-theme.md。
#
# 覆盖范围边界：kitty/foot 主题由 nosdshell 模板管线 + `nosd-helpers apply`
# 全权负责（文件先写、reload 后发信号），本脚本不碰；Electron/GTK4 走
# portal SettingChanged；nosdshell 内部状态由 daemon 侧 ipc 前推。这里只管
# 模板不覆盖的散件：set-theme.sh（GTK/qt 配置文件渲染）、mako、gsettings
# 名称项与 NotifyThemeChange。

set -eu

if [ "$#" -ne 1 ] || { [ "$1" != dark ] && [ "$1" != light ]; }; then
  printf 'Usage: %s <dark|light>\n' "${0##*/}" >&2
  exit 1
fi
mode=$1

case "$mode" in
  dark)
    log_tag=dark
    color_scheme=prefer-dark
    gtk_theme=adw-gtk3-dark
    icon_theme=Papirus-Dark
    ;;
  light)
    log_tag=light
    color_scheme=prefer-light
    gtk_theme=adw-gtk3
    icon_theme=Papirus-Light
    ;;
esac

# nosd-helpers portal 可经 D-Bus activation 启动，会话变量随激活者环境
# 而定；wayland socket 自取兜底。
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

makoctl reload || true
log "mako reload requested"

# gsettings 由 home profile 的 glib:bin 提供，直调；不要再包 guix shell（每次
# 调用都触发 profile 解析，慢且多一层 guix-daemon 失败面）。
if command -v gsettings >/dev/null 2>&1; then
  run_optional "gsettings color-scheme" gsettings set org.gnome.desktop.interface color-scheme "$color_scheme"
  run_optional "gsettings gtk-theme" gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
  run_optional "gsettings icon-theme" gsettings set org.gnome.desktop.interface icon-theme "$icon_theme"
else
  log "gsettings: skipped (gsettings not found)"
fi

# 通知运行中的 GTK 应用刷新主题
if command -v dbus-send >/dev/null 2>&1; then
  run_optional "gtk notify theme change" dbus-send --session --dest=org.gtk.Settings --type=method_call /org/gtk/Settings org.gtk.Settings.NotifyThemeChange
else
  log "gtk theme notify: skipped (dbus-send not found)"
fi

log "hook end"
