#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

# termide - A VSCode-like tmuxifier session layout
#
# Layout structure:
# ┌─────────────┬──────────────────────────┐
# │             │         editor           │
# │   sidebar   │          (hx)            │
# │   (broot)   │                          │
# │             ├──────────────────────────┤
# │             │         terminal         │
# │             │                          │
# └─────────────┴──────────────────────────┘
#
# Environment variables:
#   TERMIDE_SESSION_NAME     - Session name override (default: layout name)
#   TERMINAL_IDE_ROOT        - Working directory (default: $PWD)
#   TERMIDE_SIDEBAR_WIDTH    - Sidebar width: "25%" or "30" (default: 25%)
#   TERMIDE_TERMINAL_HEIGHT  - Terminal height: "20%" or "10" (default: 20%)
#   TERMIDE_EDITOR           - Editor command (default: hx)
#   TERMIDE_FILE_MANAGER     - File manager command (default: broot)
#   TERMIDE_SHELL            - Shell for terminal pane (default: $SHELL)
#   TERMIDE_DEBUG            - If set, print debug information

set -eo pipefail

window="main"
termide_session="${TERMIDE_SESSION_NAME:-${session:-termide}}"
root="${TERMINAL_IDE_ROOT:-$PWD}"
sidebar_size_raw="${TERMIDE_SIDEBAR_WIDTH:-25%}"
terminal_size_raw="${TERMIDE_TERMINAL_HEIGHT:-20%}"
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
    if (( BASH_REMATCH[1] >= 1 && BASH_REMATCH[1] <= 99 )); then
      printf '%s' "$value"
      return
    fi
    warn "$name percentage must be between 1 and 99, using $default"
    printf '%s' "$default"
    return
  fi

  if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 )); then
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
  new_window "$window"

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

  tmux select-pane -t "$editor_pane"
fi

finalize_and_go_to_session
