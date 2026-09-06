#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# edit-gate.sh — crush 的文件写入拦截 hook（edit / write / multiedit）（协议适配器）
#
# 判定语义全部在 ~/.config/agents/gate-core.sh（决策核，规则源为两级
# anchors.json 的 ratchet 合并，含 frozen_paths / 部署位置保护 / 敏感信息）；
# 本脚本只做 crush hook 协议转换：
#   - 环境变量 CRUSH_TOOL_INPUT_FILE_PATH / CRUSH_PROJECT_DIR / CRUSH_TOOL_NAME
#   - stdin 接收 JSON（write 取 content；edit/multiedit 取 new_string / edits[].new_string）
#   - stdout JSON：{"context":...} | {}
#   - stderr + exit 2 = 路径硬拦截；exit 49 = 敏感信息拦截

set -uo pipefail

FILE="${CRUSH_TOOL_INPUT_FILE_PATH:-}"
PROJ_INPUT="${CRUSH_PROJECT_DIR:-$PWD}"
TOOL="${CRUSH_TOOL_NAME:-}"

CORE="$HOME/.config/agents/gate-core.sh"

deny() { printf '%s\n' "$1" >&2; exit 2; }

[ -n "$FILE" ] || exit 0

# 从 stdin JSON 提取待检内容（write/edit/multiedit 三形态）
# python3 缺失或 JSON 非法 → fail-closed 拦截（crush 的输入恒为合法 JSON，
# 异常态宁可误拦不可跳过敏感信息检查）
command -v python3 >/dev/null 2>&1 || deny "🚫 edit-gate：python3 不可用（fail-closed 拦截）。"
INPUT="$(cat 2>/dev/null || true)"
CONTENT="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    inp = json.load(sys.stdin)
except Exception:
    raise SystemExit(3)
ti = inp.get('tool_input') or {}
if 'content' in ti:
    c = ti.get('content', '')
elif 'new_string' in ti:
    c = ti.get('new_string', '')
elif 'edits' in ti:
    c = ''.join(e.get('new_string', '') for e in ti['edits'] if isinstance(e, dict))
else:
    c = ''
print(c if isinstance(c, str) else '', end='')
" 2>/dev/null)" || deny "🚫 edit-gate：stdin JSON 解析失败（fail-closed 拦截）。"

# 核未部署：降级提醒（不再像旧版那样静默跳过路径保护）
if [[ ! -f "$CORE" ]]; then
  printf '⚠ gate-core.sh 未部署（dotfiles/immutable/agents/.config/agents/），路径与敏感信息检查降级跳过\n' >&2
  exit 0
fi

VERDICT="$(printf '%s' "$CONTENT" | GATE_CWD="$PROJ_INPUT" bash "$CORE" edit "$FILE" 2>/dev/null)" || true

HINTS=()
while IFS=$'\t' read -r type payload; do
  case "$type" in
    BLOCK)
      deny "$payload"
      ;;
    SENSITIVE)
      printf '%s\n' "$payload" >&2
      exit 49
      ;;
    HINT)
      HINTS+=("$payload")
      ;;
  esac
done <<<"$VERDICT"

if [[ ${#HINTS[@]} -gt 0 ]]; then
  ctx="$(IFS='; '; echo "${HINTS[*]}")"
  jq -nc --arg ctx "$ctx" '{context:$ctx}'
else
  printf '{}\n'
fi
