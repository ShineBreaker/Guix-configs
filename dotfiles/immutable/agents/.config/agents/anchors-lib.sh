#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# anchors-lib.sh — crush hook 共享的 anchors.json 加载 / 合并库
#
# 被 bash-gate.sh 与 edit-gate.sh source。语义对齐 pi-gate（dotfiles/mutable/agents/pi/
# .config/pi/extensions/pi-gate/index.ts）的分层 ratchet 模型：
#   - 全局 ~/.config/agents/anchors.json（meta-frozen，人工维护，承载 sudo 等不可削弱项）
#   - 项目级 <root>/.agents/anchors.json（从起点向上遍历到 git 根，收集每一层）
#   - 合并顺序：全局（底）→ 项目根 → … → 项目近；数组 unique 并集、映射近层覆盖远层
#   - 代码底层 DEFAULT：frozen_commands 恒含 "sudo"（agent 任何场景都不需要提权）
#
# 设计原则：本库只做「读 + 合并」，不做拦截决策——拦截语义在各 hook 里，规则源单一。

# 允许重复 source（幂等）
if [[ -n "${_ANCHORS_LIB_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
_ANCHORS_LIB_LOADED=1

# ─── 加载错误日志（对齐 pi-gate logLoadError：omp/crush 默认静默吞错误，显式留痕）──
log_gate_error() {
  local ext="$1" where="$2" msg="$3"
  local log_file="$HOME/.config/omp/extensions/.load-errors.log"
  mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
  printf '[%s] [%s] %s: %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ext" "$where" "$msg" \
    >>"$log_file" 2>/dev/null || true
}

# ─── 路径工具 ────────────────────────────────────────────────────────────────

# 展开 ~/ 前缀为 $HOME
expand_tilde() {
  local p="$1"
  case "$p" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "${HOME}${p:1}" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

# 从 dir 向上遍历找到第一个含 .git 的目录（git 根）；找不到则返回 dir 本身
find_git_root() {
  local d parent i
  d="$(readlink -f "$1" 2>/dev/null || printf '%s' "$1")"
  for ((i = 0; i < 64; i++)); do
    if [[ -d "$d/.git" ]]; then printf '%s\n' "$d"; return 0; fi
    parent="$(dirname "$d")"
    if [[ "$parent" == "$d" ]]; then break; fi
    d="$parent"
  done
  printf '%s\n' "$1"
}

# ─── anchors.json 分层收集与合并 ─────────────────────────────────────────────

# 收集项目级 anchors.json（近→根顺序），每行一个路径。含 git 根后停止。
_find_anchors_files_near_to_root() {
  local d parent i
  d="$(readlink -f "$1" 2>/dev/null || printf '%s' "$1")"
  for ((i = 0; i < 64; i++)); do
    if [[ -f "$d/.agents/anchors.json" ]]; then
      printf '%s\n' "$d/.agents/anchors.json"
    fi
    if [[ -d "$d/.git" ]]; then break; fi
    parent="$(dirname "$d")"
    if [[ "$parent" == "$d" ]]; then break; fi
    d="$parent"
  done
}

# ratchet 合并 jq 程序（输入 [全局raw, 项目根raw, ..., 项目近raw]）
# 数组字段 unique 并集；映射字段近层覆盖远层（对象 * 合并，一层 string 值等价浅合并）；
# builtin_rewrite 布尔由给出层覆盖；初始 = 代码底层 DEFAULT（sudo 恒在）。
_ANCHORS_MERGE_JQ='
reduce .[] as $raw (
  { "frozen_commands": ["sudo"], "frozen_paths": [], "frozen_globs": [],
    "interactive_commands": [], "bare_repl_commands": [], "sensitive_patterns": [],
    "redirect_conventions": {}, "rewrite": {}, "path_hints": {},
    "builtin_rewrite": true, "human_only_actions": [], "anchor_measurements": [] };
  .frozen_commands        = ((.frozen_commands   + ($raw.frozen_commands   // [])) | unique)
  | .frozen_paths         = ((.frozen_paths      + ($raw.frozen_paths      // [])) | unique)
  | .frozen_globs         = ((.frozen_globs      + ($raw.frozen_globs      // [])) | unique)
  | .interactive_commands = ((.interactive_commands + ($raw.interactive_commands // [])) | unique)
  | .bare_repl_commands   = ((.bare_repl_commands   + ($raw.bare_repl_commands   // [])) | unique)
  | .sensitive_patterns   = ((.sensitive_patterns   + ($raw.sensitive_patterns   // [])) | unique_by(.pattern))
  | .redirect_conventions = (.redirect_conventions * ($raw.redirect_conventions // {}))
  | .rewrite              = (.rewrite              * ($raw.rewrite              // {}))
  | .path_hints           = (.path_hints           * ($raw.path_hints           // {}))
  | .builtin_rewrite      = (if ($raw.builtin_rewrite | type) == "boolean" then $raw.builtin_rewrite else .builtin_rewrite end)
  | .human_only_actions   = ((.human_only_actions + ($raw.human_only_actions // [])) | unique)
  | .anchor_measurements  = ((.anchor_measurements + ($raw.anchor_measurements // [])) | unique)
)'

# 加载并合并所有层 anchors.json，输出合并 JSON 到 stdout。
# 顺序：全局（底）→ 项目根 → … → 项目近（近层覆盖远层）。
# 失败时回退到 DEFAULT（仅 sudo）并记日志，保证 hook 不因配置损坏而整体失效。
load_merged_anchors() {
  local start_dir="${1:-$PWD}"
  local global="$HOME/.config/agents/anchors.json"
  local default_json='{"frozen_commands":["sudo"],"frozen_paths":[],"frozen_globs":[],"interactive_commands":[],"bare_repl_commands":[],"sensitive_patterns":[],"redirect_conventions":{},"rewrite":{},"path_hints":{},"builtin_rewrite":true,"human_only_actions":[],"anchor_measurements":[]}'

  # 收集项目层（近→根），再反转为根→近
  # 用进程替换而非管道——管道右侧在子 shell 执行，mapfile 赋值会丢失
  local proj_files=()
  mapfile -t proj_files < <(_find_anchors_files_near_to_root "$start_dir")

  local all_files=()
  [[ -f "$global" ]] && all_files+=("$global")
  local idx
  for ((idx = ${#proj_files[@]} - 1; idx >= 0; idx--)); do
    all_files+=("${proj_files[$idx]}")
  done

  # 无任何 anchors.json：返回纯 DEFAULT（仅 sudo）
  if [[ ${#all_files[@]} -eq 0 ]]; then
    printf '%s\n' "$default_json"
    return 0
  fi

  if ! jq -s "$_ANCHORS_MERGE_JQ" "${all_files[@]}" 2>/dev/null; then
    log_gate_error "crush-gate" "load_merged_anchors" \
      "jq 合并失败，回退到 DEFAULT（仅 sudo）。文件: ${all_files[*]}"
    printf '%s\n' "$default_json"
    return 0
  fi
}

# ─── frozen_globs 告警 ───────────────────────────────────────────────────────
# bash hook 不实现 glob→regex 匹配（pi-gate 有专门的 globToRegex）。
# 当前两层 anchors.json 的 frozen_globs 均为空，零影响；非空时记日志，不静默忽略。
warn_globs_if_any() {
  local merged="$1"
  local n
  n="$(jq '.frozen_globs | length' <<<"$merged" 2>/dev/null || printf '0')"
  if [[ "$n" -gt 0 ]]; then
    log_gate_error "crush-gate" "frozen_globs" \
      "anchors.json 含 ${n} 条 frozen_globs，crush bash hook 暂不支持 glob 匹配（完整语义见 pi-gate globToRegex），这些 glob 不会在 crush 生效。"
  fi
}
