#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# edit-gate.sh — crush 的文件写入拦截 hook（edit / write / multiedit）
#
# 规则源：anchors.json（与 pi-gate 同源）
#   - 全局 ~/.config/agents/anchors.json（meta-frozen，人工维护）
#   - 项目级 <root>/.agents/anchors.json（ratchet 加码）
#   合并由 anchors-lib.sh 的 load_merged_anchors 完成。
# 语义对齐：dotfiles/mutable/pi/.config/pi/extensions/pi-gate/index.ts
#   - checkProtectedPath（meta-frozen / frozen_paths / 部署位置保护）
#   - detectSensitiveInfo（敏感信息）
#   - collectPathHints（path_hints 软提示）
#
# crush hook 协议：
#   - 环境变量 CRUSH_TOOL_INPUT_FILE_PATH / CRUSH_PROJECT_DIR / CRUSH_TOOL_NAME
#   - stdin 接收 JSON（含 tool_input）
#   - stdout 输出 JSON：{"context":...} | {}
#   - stderr + exit 2 = 路径硬拦截；exit 49 = 敏感信息拦截

set -euo pipefail

FILE="${CRUSH_TOOL_INPUT_FILE_PATH:-}"
PROJ_INPUT="${CRUSH_PROJECT_DIR:-$PWD}"
TOOL="${CRUSH_TOOL_NAME:-}"

# ─── Phase 0: 加载 anchors-lib + 合并配置 + 路径解析 ────────────────────────
SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
HOOK_DIR="$(dirname "$SELF")"
DEFAULT_MERGED='{"frozen_commands":["sudo"],"frozen_paths":[],"frozen_globs":[],"redirect_conventions":{},"rewrite":{},"path_hints":{},"builtin_rewrite":true,"human_only_actions":[],"anchor_measurements":[]}'
# 定位 anchors-lib.sh：中立位置 ~/.config/agents/（与 anchors.json 同目录，部署位置）
# lib 是协议无关的共享库，crush/zcode/pi 三方 bash 消费者都指向这里
ANCHORS_LIB=""
for candidate in "$HOME/.config/agents/anchors-lib.sh" "$HOOK_DIR/anchors-lib.sh"; do
  if [[ -f "$candidate" ]]; then ANCHORS_LIB="$candidate"; break; fi
done
if [[ -z "$ANCHORS_LIB" ]] || ! source "$ANCHORS_LIB" 2>/dev/null; then
  MERGED="$DEFAULT_MERGED"
else
  MERGED="$(load_merged_anchors "${PWD:-$HOME}" 2>/dev/null || printf '%s' "$DEFAULT_MERGED")"
  warn_globs_if_any "$MERGED"
fi

deny() { printf '%s\n' "$1" >&2; exit 2; }

# 规范化路径（展开 ~，不要求存在，不解析符号链接——对齐 pi-gate 的 path.resolve 语义）
# 关键：-s/--no-symlinks。否则 ~/.config/agents/anchors.json 会被解析到 /gnu/store/...，
# basename 不再是 anchors.json，meta-frozen 与部署位置保护双双落空。
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
PROJ="$(find_git_root "$PROJ_INPUT")"
# rel：resolved 去掉 proj 前缀；inside=1 表示在项目内
REL="${RESOLVED#"$PROJ"/}"
INSIDE=0
if [[ "$RESOLVED" == "$PROJ"* ]]; then INSIDE=1; fi

# ─── Phase 1: 路径硬拦截（对齐 pi-gate checkProtectedPath）─────────────────

# 1a meta-frozen：全局 anchors.json 或显式 _meta_frozen 的 anchors.json 禁改
if [[ "$BASENAME" == "anchors.json" ]]; then
  GA_RESOLVED="$(resolve_path "$HOME/.config/agents/anchors.json")"
  if [[ "$RESOLVED" == "$GA_RESOLVED" ]]; then
    deny "🚫 全局 anchors.json 是冻结规则源（meta-frozen），禁止 agent 修改。如需调整全局冻结规则请人工编辑。"
  fi
  if [[ -f "$RESOLVED" ]] && jq -e '._meta_frozen == true' "$RESOLVED" >/dev/null 2>&1; then
    deny "🚫 该 anchors.json 声明了 _meta_frozen，禁止 agent 修改（人工锁定的项目 gate）。如需调整请人工编辑。"
  fi
  # 其余 anchors.json：agent 可写的项目 gate，放行（仍受下方 frozen_paths 约束）
fi

# ─── Phase 2: 敏感信息检测（保留原实现，exit 49）────────────────────────────
INPUT="$(cat)"
CONTENT=""
case "$TOOL" in
  write)
    CONTENT="$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('content',''), end='')" 2>/dev/null || true)"
    ;;
  edit | multiedit)
    CONTENT="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
inp = json.load(sys.stdin)
ti = inp.get('tool_input', {})
if 'new_string' in ti:
    print(ti.get('new_string', ''), end='')
elif 'edits' in ti:
    for e in ti['edits']:
        print(e.get('new_string', ''), end='')
" 2>/dev/null || true)"
    ;;
esac

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
    printf '检测到敏感信息: %s。如确认无风险请手动重试。\n' "$FOUND" >&2
    exit 49
  fi
fi

# ─── Phase 3: 路径提示 path_hints（软提示，对齐 pi-gate collectPathHints）───
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
  jq -nc --arg ctx "$ctx" '{context:$ctx}'
else
  printf '{}\n'
fi
