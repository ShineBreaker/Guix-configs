#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

# termide - A VSCode-like tmuxifier session layout
#
# 布局结构：
# ┌─────────────┬──────────────────────────┐
# │             │         编辑器           │
# │   侧边栏    │          (hx)            │
# │  (broot)    │                          │
# │             ├──────────────────────────┤
# │             │         终端             │
# │             │                          │
# └─────────────┴──────────────────────────┘
#
# 环境变量：
#   TERMIDE_SESSION_NAME     - 会话名称覆盖（默认：布局名称）
#   TERMINAL_IDE_ROOT        - 工作目录（默认：$PWD）
#   TERMIDE_SIDEBAR_WIDTH    - 侧边栏宽度："25%" 或 "30"（默认：25%）
#   TERMIDE_TERMINAL_HEIGHT  - 终端高度："20%" 或 "10"（默认：14%）
#   TERMIDE_EDITOR           - 编辑器命令（默认：hx）
#   TERMIDE_FILE_MANAGER     - 文件管理器命令（默认：broot）
#   TERMIDE_SHELL            - 终端面板的 Shell（默认：$SHELL）
#   TERMIDE_DEBUG            - 如果设置，打印调试信息

set -eo pipefail

window="main"
termide_session="${TERMIDE_SESSION_NAME:-${session:-termide}}"
root="${TERMINAL_IDE_ROOT:-$PWD}"
sidebar_size_raw="${TERMIDE_SIDEBAR_WIDTH:-25%}"
terminal_size_raw="${TERMIDE_TERMINAL_HEIGHT:-14%}"
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
