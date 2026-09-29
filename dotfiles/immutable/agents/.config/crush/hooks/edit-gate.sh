#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# edit-gate.sh — crush 文件写入拦截 hook（edit/write/multiedit）（协议适配器；
# 判定语义在 ~/.config/agents/gate-core.sh，本脚本只做协议转换）。
#   env    - CRUSH_TOOL_INPUT_FILE_PATH / CRUSH_PROJECT_DIR / CRUSH_TOOL_NAME
#   stdin  - JSON；write 取 content，edit 取 new_string，multiedit 拼 edits[].new_string
#   stdout - {"context":...} | {}
#   exit   - 2 + stderr = 路径硬拦截；49 = 敏感信息拦截
# 协议细则见 docs/scripts/crush-edit-gate.md。

set -uo pipefail

FILE="${CRUSH_TOOL_INPUT_FILE_PATH:-}"
PROJ_INPUT="${CRUSH_PROJECT_DIR:-$PWD}"

CORE="$HOME/.config/agents/gate-core.sh"
# 人工总开关固定路径（须在核缺失降级之前检查——gate-core.md）
GATE_PAUSE_FILE="/run/agent-gate.off"

deny() {
  printf '%s\n' "$1" >&2
  exit 2
}

[ -n "$FILE" ] || exit 0

# 最优先：静默放行同正常放行的 {} 形态，不向 agent 暴露暂停态
if [[ -f "$GATE_PAUSE_FILE" ]]; then
  printf '{}\n'
  exit 0
fi

# python3 缺失或 JSON 非法 → fail-closed（宁可误拦不可跳过敏感检查）
command -v python3 >/dev/null 2>&1 || deny "edit-gate：python3 不可用（fail-closed 拦截）。"
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
" 2>/dev/null)" || deny "edit-gate：stdin JSON 解析失败（fail-closed 拦截）。"

# 核未部署：降级提醒后放行
if [[ ! -f "$CORE" ]]; then
  printf '[警告] gate-core.sh 未部署（dotfiles/immutable/agents/.config/agents/），路径与敏感信息检查降级跳过\n' >&2
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
  ctx="$(
    IFS='; '
    echo "${HINTS[*]}"
  )"
  jq -nc --arg ctx "$ctx" '{context:$ctx}'
else
  printf '{}\n'
fi
