#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# anchors-lib.sh — zcode / pi / hermes / DSH 四端 gate 共享的 anchors.json 分层加载与 ratchet 合并库。
# 只做「读 + 合并」，判定语义全部在 gate-core.sh（单一真相源分工）。
# 分层模型、merge 语义、失败回退约定见 docs/scripts/gate-core.md §规则源。
#
# 被同目录 gate-core.sh source；消费链路：
#   zcode hooks → gate-core.sh → 本库
#   pi（pi-gate/index.ts）、hermes（plugins/gate/__init__.py）、DSH gate.js
#
# 契约：本库是被 source 的库文件——不得 set -e/-u/-o pipefail、不得 exit、
# 不得依赖未被调用方设置的变量以外的环境状态。
# shellcheck disable=SC2317 # 库文件：函数由调用方经 source 使用
# 允许重复 source（幂等）
if [[ -n "${_ANCHORS_LIB_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
_ANCHORS_LIB_LOADED=1

# ─── 加载错误日志（对齐 pi-gate logLoadError，显式留痕防静默吞错）──
log_gate_error() {
  local ext="$1" where="$2" msg="$3"
  local log_file="$HOME/.config/omp/extensions/.load-errors.log"
  mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
  printf '[%s] [%s] %s: %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ext" "$where" "$msg" \
    >>"$log_file" 2>/dev/null || true
}

# ─── 路径工具 ────────────────────────────────────────────────────────────────

# ~/ 前缀展开
# shellcheck disable=SC2317 # 库文件：函数由调用方使用
expand_tilde() {
  local p="$1"
  # shellcheck disable=SC2088 # 匹配 anchors.json 里的字面 ~/ 前缀
  case "$p" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "${HOME}${p:1}" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

# 向上找含 .git 的目录；找不到返回 dir 本身
find_git_root() {
  local d parent i
  d="$(readlink -f "$1" 2>/dev/null || printf '%s' "$1")"
  for ((i = 0; i < 64; i++)); do
    if [[ -d "$d/.git" ]]; then
      printf '%s\n' "$d"
      return 0
    fi
    parent="$(dirname "$d")"
    if [[ "$parent" == "$d" ]]; then break; fi
    d="$parent"
  done
  printf '%s\n' "$1"
}

# ─── anchors.json 分层收集与合并 ─────────────────────────────────────────────

# 收集项目级（近→根），含 git 根后停止。
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

# ratchet 合并（输入 [全局, 项目根, ..., 项目近]）：数组 unique 并集、映射
# 近层覆盖远层、builtin_rewrite 布尔由给出层覆盖；初始=DEFAULT（sudo 恒在，
# 语义细则见 docs/scripts/gate-core.md）。
# shellcheck disable=SC2016 # jq 程序文本，非 shell 待展开串
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

# load_merged_anchors [start_dir]：全局（底）→ 项目根 → … → 项目近，
# 输出合并 JSON 到 stdout；任何层损坏 → 回退 DEFAULT（仅 sudo）并记日志，
# 保证 hook 不因配置损坏整体失效。
load_merged_anchors() {
  local start_dir="${1:-$PWD}"
  local global="$HOME/.config/agents/anchors.json"
  # shellcheck disable=SC2016 # JSON 字面量
  local default_json='{"frozen_commands":["sudo"],"frozen_paths":[],"frozen_globs":[],"interactive_commands":[],"bare_repl_commands":[],"sensitive_patterns":[],"redirect_conventions":{},"rewrite":{},"path_hints":{},"builtin_rewrite":true,"human_only_actions":[],"anchor_measurements":[]}'

  # 进程替换而非管道——管道右侧在子 shell，mapfile 赋值会丢失
  local proj_files=()
  mapfile -t proj_files < <(_find_anchors_files_near_to_root "$start_dir")

  local all_files=()
  [[ -f "$global" ]] && all_files+=("$global")
  local idx
  for ((idx = ${#proj_files[@]} - 1; idx >= 0; idx--)); do
    all_files+=("${proj_files[$idx]}")
  done

  # 无 anchors.json → 纯 DEFAULT（仅 sudo）
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

# ─── frozen_globs 匹配 ───────────────────────────────────────────────────────
# glob_to_ere <glob> → 锚定 ERE：`**`→.*（吞 **/ 斜杠）、`*`→[^/]*、`?`→[^/]。
# 语义对齐 pi-gate globToRegex（docs/scripts/gate-core.md §glob 语义）。
# shellcheck disable=SC2016 # 内部 sed 程序文本含 $，须单引号防展开
glob_to_ere() {
  local g="$1" out="" i=0 c
  while ((i < ${#g})); do
    c="${g:$i:1}"
    case "$c" in
      '*')
        if [[ "${g:$((i + 1)):1}" == '*' ]]; then
          out+='.*'
          ((i++))
          [[ "${g:$((i + 1)):1}" == '/' ]] && ((i++))
        else
          out+='[^/]*'
        fi
        ;;
      '?') out+='[^/]' ;;
      *) out+="$(printf '%s' "$c" | sed 's/[.[\*^$()+?{|\\]/\\&/g')" ;;
    esac
    ((i++))
  done
  printf '%s' "^${out}$"
}
