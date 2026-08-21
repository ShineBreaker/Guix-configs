#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# edit-gate — zcode PreToolUse hook for Write/Edit tools
#
# 规则源：anchors.json（与 pi-gate / crush 同源），经 ~/.config/agents/anchors-lib.sh
# 加载合并。行为对齐 pi-gate（checkProtectedPath / detectSensitiveInfo / collectPathHints）。
#
# zcode hook 协议：
#   - stdin JSON: { tool_name, tool_input: { file_path, content | new_string }, cwd, ... }
#   - stdout JSON: {"additionalContext":"..."} | 空
#   - exit 0 通过；exit 2 = block

set -euo pipefail

# ─── Phase 0: 读 stdin + source lib + 路径解析 ──────────────────────────────
INPUT="$(cat 2>/dev/null || true)"
eval "$(printf '%s' "$INPUT" | python3 -c "
import sys, json, shlex
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
ti = d.get('tool_input', {})
content = ti.get('content', '') or ti.get('new_string', '')
print('TOOL=' + shlex.quote(d.get('tool_name', '')))
print('FILE=' + shlex.quote(ti.get('file_path', '')))
print('CONTENT=' + shlex.quote(content))
print('CWD=' + shlex.quote(d.get('cwd', '')))
" 2>/dev/null || true)"

FILE="${FILE:-}"
TOOL="${TOOL:-}"
CONTENT="${CONTENT:-}"
CWD="${CWD:-$PWD}"
[ -n "$FILE" ] || exit 0

DEFAULT_MERGED='{"frozen_commands":["sudo"],"frozen_paths":[],"frozen_globs":[],"redirect_conventions":{},"rewrite":{},"path_hints":{},"builtin_rewrite":true,"human_only_actions":[],"anchor_measurements":[]}'
if ! source "$HOME/.config/agents/anchors-lib.sh" 2>/dev/null; then
  MERGED="$DEFAULT_MERGED"
else
  MERGED="$(load_merged_anchors "$CWD" 2>/dev/null || printf '%s' "$DEFAULT_MERGED")"
  warn_globs_if_any "$MERGED"
fi

deny() { printf '%s\n' "$1" >&2; exit 2; }

# 规范化路径（展开 ~，不要求存在，不解析符号链接——对齐 pi-gate path.resolve）
resolve_path() {
  local p="$1"
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="${HOME}${p:1}" ;;
  esac
  if command -v realpath >/dev/null 2>&1; then
    realpath -ms "$p" 2>/dev/null || printf '%s' "$p"
  else
    readlink -f "$p" 2>/dev/null || printf '%s' "$p"
  fi
}

RESOLVED="$(resolve_path "$FILE")"
BASENAME="${RESOLVED##*/}"
PROJ="$(find_git_root "$CWD")"
REL="${RESOLVED#"$PROJ"/}"
INSIDE=0
if [[ "$RESOLVED" == "$PROJ"* ]]; then INSIDE=1; fi

# ─── Phase 1: 路径硬拦截 ─────────────────────────────────────────────────────

# 1a meta-frozen
if [[ "$BASENAME" == "anchors.json" ]]; then
  GA_RESOLVED="$(resolve_path "$HOME/.config/agents/anchors.json")"
  if [[ "$RESOLVED" == "$GA_RESOLVED" ]]; then
    deny "🚫 全局 anchors.json 是冻结规则源（meta-frozen），禁止 agent 修改。如需调整全局冻结规则请人工编辑。"
  fi
  if [[ -f "$RESOLVED" ]] && jq -e '._meta_frozen == true' "$RESOLVED" >/dev/null 2>&1; then
    deny "🚫 该 anchors.json 声明了 _meta_frozen，禁止 agent 修改（人工锁定的项目 gate）。如需调整请人工编辑。"
  fi
fi

# 1b frozen_paths
while IFS= read -r frozen; do
  [[ -z "$frozen" ]] && continue
  case "$frozen" in
    "~/"*)
      exp="${HOME}${frozen:1}"
      if [[ "$RESOLVED" == "$exp" || "$RESOLVED" == "$exp"* ]]; then
        deny "🚫 冻结路径「${frozen}」禁止写入。请修改源文件后通过 blue home 生效。"
      fi
      ;;
    *)
      if [[ $INSIDE -eq 1 && "$REL" == "$frozen"* ]]; then
        deny "🚫 冻结路径「${frozen}」禁止写入。请修改源文件后通过 blue home 生效。"
      fi
      if [[ "$RESOLVED" == *"$frozen" ]]; then
        deny "🚫 冻结路径「${frozen}」禁止写入。请修改源文件后通过 blue home 生效。"
      fi
      ;;
  esac
done < <(jq -r '.frozen_paths[]?' <<<"$MERGED" 2>/dev/null)

# 1c 部署位置保护
if [[ "$RESOLVED" == "$HOME/.config/"* || "$RESOLVED" == "$HOME/.local/"* ]]; then
  if [[ "$RESOLVED" != "$PROJ"* ]]; then
    deny "🚫 禁止直接修改已部署位置（~/.config/ 或 ~/.local/）。请修改 dotfiles/ 源文件后运行 blue home。"
  fi
fi

# ─── Phase 2: 敏感信息检测（exit 2 block）────────────────────────────────────
if [[ -n "$CONTENT" ]]; then
  TMPFILE="$(mktemp)"
  trap 'rm -f "$TMPFILE"' EXIT
  printf '%s' "$CONTENT" >"$TMPFILE"
  FOUND=""
  while IFS=$'\t' read -r pattern label flags; do
    [[ -z "$pattern" ]] && continue
    gflag="-qE"
    [[ "$flags" == *"i"* ]] && gflag="-qiE"
    if grep $gflag -e "$pattern" "$TMPFILE" 2>/dev/null; then
      FOUND="${FOUND:+$FOUND; }$label"
    fi
  done < <(jq -r '.sensitive_patterns[]? | [.pattern, .label, (.flags // "")] | @tsv' <<<"$MERGED" 2>/dev/null)
  if [[ -n "$FOUND" ]]; then
    deny "🚫 检测到敏感信息: $FOUND。如确认无风险请手动操作。"
  fi
fi

# ─── Phase 3: path_hints（additionalContext 软提示）──────────────────────────
HINTS=()
if [[ $INSIDE -eq 1 ]]; then
  while IFS=$'\t' read -r prefix msg; do
    [[ -z "$prefix" ]] && continue
    p="${prefix%/}/"
    if [[ "$REL" == "$prefix" || "$REL" == "$p"* || "$REL" == "$prefix"* ]]; then
      HINTS+=("$msg")
    fi
  done < <(jq -r '.path_hints | to_entries[] | "\(.key)\t\(.value)"' <<<"$MERGED" 2>/dev/null)
fi

if [[ ${#HINTS[@]} -gt 0 ]]; then
  ctx="$(IFS='; '; echo "${HINTS[*]}")"
  printf '{"additionalContext":%s}\n' "$(printf '%s' "$ctx" | jq -Rs .)"
fi
exit 0
