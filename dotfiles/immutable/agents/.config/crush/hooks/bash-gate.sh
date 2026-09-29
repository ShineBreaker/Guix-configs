#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# bash-gate.sh — crush bash 工具拦截 hook（协议适配器；判定语义在
# ~/.config/agents/gate-core.sh，本脚本只做协议转换）。
#   stdin  - 无（命令经 CRUSH_TOOL_INPUT_COMMAND 传入）
#   stdout - {"decision":"allow"} | {"context":...} | {"updated_input":{...}} | {}
#   exit   - 2 + stderr = 硬拦截；crush 支持 updated_input → REWRITTEN 真改写
# 协议细则见 docs/scripts/crush-bash-gate.md。

set -uo pipefail

CMD="${CRUSH_TOOL_INPUT_COMMAND:-}"
CORE="$HOME/.config/agents/gate-core.sh"
# 人工总开关固定路径（须在核缺失保底之前检查——gate-core.md）
GATE_PAUSE_FILE="/run/agent-gate.off"

deny() {
  printf '%s\n' "$1" >&2
  exit 2
}

[ -n "$CMD" ] || exit 0

# 最优先：静默放行同正常放行的 {} 形态，不向 agent 暴露暂停态
if [[ -f "$GATE_PAUSE_FILE" ]]; then
  printf '{}\n'
  exit 0
fi

# 核未部署：sudo 保底 + stderr 提醒
if [[ ! -f "$CORE" ]]; then
  case "$CMD" in *sudo*) deny "冻结命令「sudo」禁止执行（gate-core 未部署，保底拦截）。" ;; esac
  printf '[警告] gate-core.sh 未部署（dotfiles/immutable/agents/.config/agents/），gate 仅保底 sudo 检查\n' >&2
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
    RM_HINT | NOTES | REDIRECT)
      CONTEXT_PARTS+=("$payload")
      ;;
  esac
done <<<"$VERDICT"

if [[ -n "$REWRITTEN" ]]; then
  if [[ ${#CONTEXT_PARTS[@]} -gt 0 ]]; then
    ctx="$(
      IFS='; '
      echo "${CONTEXT_PARTS[*]}"
    )"
    jq -nc --arg ctx "$ctx" --arg cmd "$REWRITTEN" '{context:$ctx, updated_input:{command:$cmd}}'
  else
    jq -nc --arg cmd "$REWRITTEN" '{updated_input:{command:$cmd}}'
  fi
elif [[ ${#CONTEXT_PARTS[@]} -gt 0 ]]; then
  ctx="$(
    IFS='; '
    echo "${CONTEXT_PARTS[*]}"
  )"
  jq -nc --arg ctx "$ctx" '{context:$ctx}'
else
  printf '{}\n'
fi
