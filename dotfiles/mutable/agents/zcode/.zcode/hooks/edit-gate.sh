#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# edit-gate — zcode PreToolUse hook for Write/Edit tools（协议适配器）
#
# 判定语义全部在 ~/.config/agents/gate-core.sh（决策核，规则源为两级
# anchors.json 的 ratchet 合并）；本脚本只做 zcode hook 协议转换：
#   - stdin JSON: { tool_name, tool_input: { file_path, content | new_string }, cwd, ... }
#   - stdout JSON: {"additionalContext":"..."} | 空
#   - exit 0 通过；exit 2 = block（路径拦截与敏感信息统一走 exit 2）

set -uo pipefail

CORE="$HOME/.config/agents/gate-core.sh"
# 人工总开关（固定路径，见 gate-core.sh 文件头；须在核缺失降级之前检查）
GATE_PAUSE_FILE="/run/agent-gate.off"

deny() { printf '%s\n' "$1" >&2; exit 2; }

# ─── Phase 0: 读 stdin，fail-closed 解析 ─────────────────────────────────────
# python3 缺失时无法解析输入，fail-closed 拦截（而非静默跳过路径/敏感检查）
command -v python3 >/dev/null 2>&1 || deny "edit-gate：python3 不可用，无法解析输入（fail-closed 拦截）。"
INPUT="$(cat 2>/dev/null || true)"

eval "$(printf '%s' "$INPUT" | python3 -c "
import sys, json, shlex
try:
    d = json.load(sys.stdin)
except Exception:
    print('PARSE_FAIL=1')
    raise SystemExit
ti = d.get('tool_input') or {}
content = ti.get('content', '') or ti.get('new_string', '') or ''
if not isinstance(content, str):
    content = ''
print('FILE=' + shlex.quote(ti.get('file_path', '') or ''))
print('CONTENT=' + shlex.quote(content))
print('CWD=' + shlex.quote(d.get('cwd') or ''))
" 2>/dev/null || true)"

# JSON 非空但解析失败 → fail-closed
if [[ "${PARSE_FAIL:-}" == "1" && -n "$INPUT" ]]; then
  deny "edit-gate：stdin JSON 解析失败（fail-closed 拦截）。请重试或检查 hook 输入。"
fi

FILE="${FILE:-}"
CONTENT="${CONTENT:-}"
CWD="${CWD:-$PWD}"
[ -n "$FILE" ] || exit 0

# ─── Phase 0.5: 人工总开关（最优先）────────────────────────────────────
# 静默放行：不输出任何内容，与 Phase 2 无提示时的正常放行同形态，
# 不向 agent 暴露暂停态
if [[ -f "$GATE_PAUSE_FILE" ]]; then
  exit 0
fi

# ─── Phase 1: 调决策核（待检内容经 stdin 传入）──────────────────────────────
if [[ ! -f "$CORE" ]]; then
  printf '[警告] gate-core.sh 未部署（dotfiles/immutable/agents/.config/agents/），路径与敏感信息检查降级跳过\n' >&2
  exit 0
fi

VERDICT="$(printf '%s' "$CONTENT" | GATE_CWD="$CWD" bash "$CORE" edit "$FILE" 2>/dev/null)" || true

# ─── Phase 2: 行协议 → zcode 协议 ────────────────────────────────────────────
HINTS=()
while IFS=$'\t' read -r type payload; do
  case "$type" in
    BLOCK|SENSITIVE)
      deny "$payload"
      ;;
    HINT)
      HINTS+=("$payload")
      ;;
  esac
done <<<"$VERDICT"

if [[ ${#HINTS[@]} -gt 0 ]]; then
  ctx="$(IFS='; '; echo "${HINTS[*]}")"
  printf '{"additionalContext":%s}\n' "$(printf '%s' "$ctx" | jq -Rs .)"
fi
exit 0
