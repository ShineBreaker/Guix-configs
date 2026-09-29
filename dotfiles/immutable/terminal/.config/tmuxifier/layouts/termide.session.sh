#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# termide — VSCode 风格 tmuxifier 会话布局（Explorer | Editor / Terminal）
# 布局图与 TERMIDE_* 环境变量见 docs/scripts/termide-layout.md

set -eo pipefail

window="main"
termide_session="${TERMIDE_SESSION_NAME:-${session:-termide}}"
root="${TERMINAL_IDE_ROOT:-$PWD}"
sidebar_size_raw="${TERMIDE_SIDEBAR_WIDTH:-24}"
terminal_size_raw="${TERMIDE_TERMINAL_HEIGHT:-12}"
editor_cmd="${TERMIDE_EDITOR:-hx}"
file_manager_cmd="${TERMIDE_FILE_MANAGER:-broot}"
shell_cmd="${TERMIDE_SHELL:-${SHELL:-/bin/sh}}"
debug="${TERMIDE_DEBUG:-}"

log_debug() {
  if [[ -n "$debug" ]]; then
    printf '[termide] %s\n' "$*" >&2
  fi
}

warn() {
  printf 'termide: %s\n' "$*" >&2
}

sanitize_size() {
  local value="$1"
  local default="$2"
  local name="$3"

  if [[ "$value" =~ ^([0-9]+)%$ ]]; then
    if ((BASH_REMATCH[1] >= 1 && BASH_REMATCH[1] <= 99)); then
      printf '%s' "$value"
      return
    fi
    warn "$name percentage must be between 1 and 99, using $default"
    printf '%s' "$default"
    return
  fi

  if [[ "$value" =~ ^[0-9]+$ ]] && ((value >= 1)); then
    printf '%s' "$value"
    return
  fi

  warn "invalid $name value \"$value\", using $default"
  printf '%s' "$default"
}

split_pane() {
  local direction="$1"
  local size="$2"
  local target="$3"

  if [[ "$size" =~ ^([0-9]+)%$ ]]; then
    tmux split-window "-$direction" -p "${BASH_REMATCH[1]}" -P -F '#{pane_id}' -t "$target"
  else
    tmux split-window "-$direction" -l "$size" -P -F '#{pane_id}' -t "$target"
  fi
}

run_if_exists() {
  local command_text="$1"
  local pane="$2"
  local command_name="${command_text%% *}"

  if command -v "$command_name" >/dev/null 2>&1; then
    log_debug "starting in pane $pane: $command_text"
    run_cmd "$command_text" "$pane"
  else
    warn "\"$command_name\" not found; pane $pane left idle"
  fi
}

sidebar_size="$(sanitize_size "$sidebar_size_raw" '25%' 'sidebar width')"
terminal_size="$(sanitize_size "$terminal_size_raw" '20%' 'terminal height')"

if [[ ! -d "$root" ]]; then
  warn "root directory \"$root\" does not exist, using $PWD"
  root="$PWD"
fi

log_debug "root=$root sidebar=$sidebar_size terminal=$terminal_size"

session_root "$root"

if initialize_session "$termide_session"; then
  # 绕过 tmuxifier new_window 的 bug：其内部 set-option -t 缺 session 前缀，
  # client 不在目标 session 时报 "no such window" —— 原生命令须带 session:
  tmux new-window -t "$session:" -n "$window" -c "$root" \; set-window-option -t "$session:$window" @no_sidebar 1 >/dev/null
  tmux set-option -t "$session:$window" allow-rename off >/dev/null
  window="$(tmux list-windows -t "$session:" -F '#{window_active}:#{window_index}' | grep '^1:' | cut -d: -f2)"

  editor_pane="$(tmux display-message -p -t "$session:$window" '#{pane_id}')"

  if [[ "$sidebar_size" =~ ^([0-9]+)%$ ]]; then
    sidebar_pane="$(tmux split-window -h -b -p "${BASH_REMATCH[1]}" -P -F '#{pane_id}' -t "$editor_pane")"
  else
    sidebar_pane="$(tmux split-window -h -b -l "$sidebar_size" -P -F '#{pane_id}' -t "$editor_pane")"
  fi

  terminal_pane="$(split_pane v "$terminal_size" "$editor_pane")"

  run_if_exists "$file_manager_cmd" "$sidebar_pane"
  run_if_exists "$editor_cmd ." "$editor_pane"

  if [[ "$shell_cmd" != "${SHELL:-/bin/sh}" ]]; then
    log_debug "replacing terminal shell in pane $terminal_pane: $shell_cmd"
    run_cmd "exec $shell_cmd" "$terminal_pane"
  fi

  tmux set-window-option -t "$session:$window" @termide_root "$root" >/dev/null
  tmux set-window-option -t "$session:$window" @termide_sidebar_pane "$sidebar_pane" >/dev/null
  tmux set-window-option -t "$session:$window" @termide_editor_pane "$editor_pane" >/dev/null
  tmux set-window-option -t "$session:$window" @termide_terminal_pane "$terminal_pane" >/dev/null
  tmux set-window-option -t "$session:$window" pane-border-status top >/dev/null

  tmux select-pane -t "$sidebar_pane" -T "Explorer"
  tmux select-pane -t "$editor_pane" -T "Editor"
  tmux select-pane -t "$terminal_pane" -T "Terminal"

  tmux select-pane -t "$editor_pane"
fi

finalize_and_go_to_session
