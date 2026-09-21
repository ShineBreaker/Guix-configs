#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# bash-gate — zcode PreToolUse hook for the Bash tool（协议适配器）
#
# 判定语义全部在 ~/.config/agents/gate-core.sh（决策核，规则源为两级
# anchors.json 的 ratchet 合并）；本脚本只做 zcode hook 协议转换：
#   - stdin JSON: { tool_name, tool_input: { command }, cwd, ... }
#   - stdout JSON: {"decision":"allow"} | {"additionalContext":"..."} | 空
#   - exit 0 通过；exit 2 = block（deny）
#   - zcode 不支持 updated_input（不能重写命令）→ REWRITTEN 降级为提醒

set -uo pipefail

CORE="$HOME/.config/agents/gate-core.sh"
# 人工总开关（固定路径，见 gate-core.sh 文件头；须在核缺失保底之前检查）
GATE_PAUSE_FILE="/run/agent-gate.off"

deny() { printf '%s\n' "$1" >&2; exit 2; }

# ─── Phase 0: 读 stdin，fail-closed 解析 ─────────────────────────────────────
# python3 缺失时无法解析输入，fail-closed 拦截（而非静默放行整条命令）
command -v python3 >/dev/null 2>&1 || deny "bash-gate：python3 不可用，无法解析输入（fail-closed 拦截）。"
INPUT="$(cat 2>/dev/null || true)"

eval "$(printf '%s' "$INPUT" | python3 -c "
import sys, json, shlex
try:
    d = json.load(sys.stdin)
except Exception:
    print('PARSE_FAIL=1')
    raise SystemExit
ti = d.get('tool_input') or {}
cmd = ti.get('command', '')
if not isinstance(cmd, str):
    cmd = ''
print('CMD=' + shlex.quote(cmd))
print('CWD=' + shlex.quote(d.get('cwd') or ''))
" 2>/dev/null || true)"

# JSON 非空但解析失败 → fail-closed（此前 fail-open 是已知绕过面）
if [[ "${PARSE_FAIL:-}" == "1" && -n "$INPUT" ]]; then
  deny "bash-gate：stdin JSON 解析失败（fail-closed 拦截）。请重试或检查 hook 输入。"
fi

CMD="${CMD:-}"
CWD="${CWD:-$PWD}"
[ -n "$CMD" ] || exit 0

# ─── Phase 0.5: 人工总开关（最优先，覆盖核缺失保底）────────────────────
if [[ -f "$GATE_PAUSE_FILE" ]]; then
  printf '{"additionalContext":"%s"}' "护栏已手动暂停（/run/agent-gate.off 存在）：本次不做拦截检查，权限仍走客户端自身流程。恢复请人工删除该开关文件。"
  exit 0
fi

# ─── Phase 1: 调决策核 ───────────────────────────────────────────────────────
# 核未部署（blue home 未跑）：sudo 保底 + stderr 提醒，其余放行
if [[ ! -f "$CORE" ]]; then
  case "$CMD" in *sudo*) deny "冻结命令「sudo」禁止执行（gate-core 未部署，保底拦截）。" ;; esac
  printf '[警告] gate-core.sh 未部署（dotfiles/immutable/agents/.config/agents/），gate 仅保底 sudo 检查\n' >&2
  exit 0
fi

VERDICT="$(GATE_CWD="$CWD" bash "$CORE" bash "$CMD" 2>/dev/null)" || true

# ─── Phase 2: 行协议 → zcode 协议 ────────────────────────────────────────────
PARTS=()
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
      PARTS+=("本机命令改写建议：${payload}（zcode 无法自动改写，如适用请手动改用）")
      ;;
    RM_HINT|NOTES|REDIRECT)
      PARTS+=("$payload")
      ;;
  esac
done <<<"$VERDICT"

if [[ ${#PARTS[@]} -gt 0 ]]; then
  ctx="$(IFS='; '; echo "${PARTS[*]}")"
  printf '{"additionalContext":%s}\n' "$(printf '%s' "$ctx" | jq -Rs .)"
fi
exit 0
