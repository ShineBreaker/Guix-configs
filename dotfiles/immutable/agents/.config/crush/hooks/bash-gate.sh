#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# bash-gate.sh — crush 的 bash 工具拦截 hook（协议适配器）
#
# 判定语义全部在 ~/.config/agents/gate-core.sh（决策核，规则源为两级
# anchors.json 的 ratchet 合并）；本脚本只做 crush hook 协议转换：
#   - 环境变量 CRUSH_TOOL_INPUT_COMMAND 传入命令
#   - stdout JSON：{"decision":"allow"} | {"context":...} | {"updated_input":{...}} | {}
#   - stderr + exit 2 = 硬拦截（deny）
# crush 支持 updated_input → REWRITTEN 真实改写命令

set -uo pipefail

CMD="${CRUSH_TOOL_INPUT_COMMAND:-}"
CORE="$HOME/.config/agents/gate-core.sh"

deny() { printf '%s\n' "$1" >&2; exit 2; }

[ -n "$CMD" ] || exit 0

# 核未部署：sudo 保底 + stderr 提醒
if [[ ! -f "$CORE" ]]; then
  case "$CMD" in *sudo*) deny "🚫 冻结命令「sudo」禁止执行（gate-core 未部署，保底拦截）。" ;; esac
  printf '⚠ gate-core.sh 未部署（dotfiles/immutable/agents/.config/agents/），gate 仅保底 sudo 检查\n' >&2
  exit 0
fi

VERDICT="$(GATE_CWD="${PWD:-$HOME}" bash "$CORE" bash "$CMD" 2>/dev/null)" || true

REWRITTEN=""
CONTEXT_PARTS=()
while IFS=$'\t' read -r type payload; do
  case "$type" in
    BLOCK)
      deny "$payload"
      ;;
    AUTO_ALLOW)
      printf '{"decision":"allow"}\n'
      exit 0
      ;;
    REWRITTEN)
      REWRITTEN="$payload"
      ;;
    RM_HINT|NOTES|REDIRECT)
      CONTEXT_PARTS+=("$payload")
      ;;
  esac
done <<<"$VERDICT"

if [[ -n "$REWRITTEN" ]]; then
  if [[ ${#CONTEXT_PARTS[@]} -gt 0 ]]; then
    ctx="$(IFS='; '; echo "${CONTEXT_PARTS[*]}")"
    jq -nc --arg ctx "$ctx" --arg cmd "$REWRITTEN" '{context:$ctx, updated_input:{command:$cmd}}'
  else
    jq -nc --arg cmd "$REWRITTEN" '{updated_input:{command:$cmd}}'
  fi
elif [[ ${#CONTEXT_PARTS[@]} -gt 0 ]]; then
  ctx="$(IFS='; '; echo "${CONTEXT_PARTS[*]}")"
  jq -nc --arg ctx "$ctx" '{context:$ctx}'
else
  printf '{}\n'
fi
