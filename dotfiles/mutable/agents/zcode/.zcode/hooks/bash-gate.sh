#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# bash-gate — zcode PreToolUse hook for the Bash tool
#
# 规则源：anchors.json（与 pi-gate / crush 同源），经 ~/.config/agents/anchors-lib.sh
# 的 load_merged_anchors 分层 ratchet 合并。行为对齐 pi-gate（checkBashCommand）。
#
# zcode hook 协议（claude-code 兼容）：
#   - stdin JSON: { tool_name, tool_input: { command }, cwd, session_id, ... }
#   - stdout JSON: {"decision":"allow"} | {"additionalContext":"..."} | 空
#   - exit 0 通过；exit 2 = block（deny）
#   - zcode 不支持 updated_input（不能重写命令）→ 命令改写降级为 additionalContext 提醒

set -euo pipefail

# ─── Phase 0: 读 stdin + source lib + 加载 anchors ──────────────────────────
INPUT="$(cat 2>/dev/null || true)"
eval "$(printf '%s' "$INPUT" | python3 -c "
import sys, json, shlex
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
ti = d.get('tool_input', {})
print('CMD=' + shlex.quote(ti.get('command', '')))
print('CWD=' + shlex.quote(d.get('cwd', '')))
" 2>/dev/null || true)"

CMD="${CMD:-}"
CWD="${CWD:-$PWD}"
[ -n "$CMD" ] || exit 0

DEFAULT_MERGED='{"frozen_commands":["sudo"],"frozen_paths":[],"frozen_globs":[],"redirect_conventions":{},"rewrite":{},"path_hints":{},"builtin_rewrite":true,"human_only_actions":[],"anchor_measurements":[]}'
if ! source "$HOME/.config/agents/anchors-lib.sh" 2>/dev/null; then
  MERGED="$DEFAULT_MERGED"
else
  MERGED="$(load_merged_anchors "$CWD" 2>/dev/null || printf '%s' "$DEFAULT_MERGED")"
  warn_globs_if_any "$MERGED"
fi

deny() { printf '%s\n' "$1" >&2; exit 2; }
allow() { printf '{"decision":"allow"}\n'; exit 0; }

PREFIX='(^|[;&|()$]|&&|\|\|)[[:space:]]*'

# ─── Phase 1: 硬拦截（exit 2）──────────────────────────────────────────────

# 1a 冻结命令（子串匹配 + --dry-run 兜底）+ guix system 宽匹配
if [[ "$CMD" != *"--dry-run"* ]]; then
  while IFS= read -r frozen; do
    [[ -z "$frozen" ]] && continue
    if [[ "$CMD" == *"$frozen"* ]]; then
      deny "🚫 冻结命令「${frozen}」需 sudo 提权或为系统级操作，禁止执行。验证请用 \`blue --dry-run rebuild\`；固化请提醒用户手动运行。"
    fi
  done < <(jq -r '.frozen_commands[]?' <<<"$MERGED" 2>/dev/null)
  if [[ "$CMD" == *"guix"* ]] && printf '%s' "$CMD" | grep -qE '\bsystem[[:space:]]+(reconfigure|init)\b'; then
    deny "🚫 禁止 guix system reconfigure/init（含 time-machine 包装，需 sudo）。验证请用 \`blue --dry-run rebuild\`；固化请提醒用户手动运行。"
  fi
fi

# 1b 交互式命令（命令起始位置匹配，无 TTY 会挂起）——名单来自 anchors.json
# 出现即禁（\b 词边界）
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  esc="$(printf '%s' "$name" | sed 's/[.[\*^$()+?{|\\]/\\&/g')"
  if printf '%s' "$CMD" | grep -qE "${PREFIX}${esc}\b"; then
    deny "🚫 禁止交互式命令 ${name}（无 TTY 会挂起），请使用对应工具"
  fi
done < <(jq -r '.interactive_commands[]?' <<<"$MERGED" 2>/dev/null)
# 仅裸调用禁（行尾）
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  esc="$(printf '%s' "$name" | sed 's/[.[\*^$()+?{|\\]/\\&/g')"
  if printf '%s' "$CMD" | grep -qE "${PREFIX}${esc}[[:space:]]*$"; then
    deny "🚫 禁止裸 REPL ${name}，请使用 ${name} -c '...' 或脚本"
  fi
done < <(jq -r '.bare_repl_commands[]?' <<<"$MERGED" 2>/dev/null)

# 1c Git 限制
if printf '%s' "$CMD" | grep -qE "${PREFIX}git[[:space:]]+commit\b"; then
  if ! printf '%s' "$CMD" | grep -qE '([[:space:]]-m[[:space:]]|[[:space:]]--message[[:space:]])'; then
    deny "🚫 git commit 必须使用 -m 指定提交信息"
  fi
fi
if printf '%s' "$CMD" | grep -qE "${PREFIX}git[[:space:]]+add[[:space:]].*-p\b"; then
  deny "🚫 禁止 git add -p（交互式）"
fi
if printf '%s' "$CMD" | grep -qE "${PREFIX}git[[:space:]]+rebase[[:space:]].*-i\b"; then
  deny "🚫 禁止 git rebase -i（交互式）"
fi

# 1d rm 破坏性删除防护
RM_HINT=""
if printf '%s' "$CMD" | grep -qE "${PREFIX}rm\b"; then
  rm_args="${CMD#*rm}"
  rm_recursive=0; rm_force=0; rm_danger=0
  if printf '%s' "$rm_args" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[rR]|--recursive'; then rm_recursive=1; fi
  if printf '%s' "$rm_args" | grep -qE '(^|[[:space:]])-[a-zA-Z]*f|--force'; then rm_force=1; fi
  if [[ "$rm_args" == *'$HOME'* ]]; then rm_danger=1; fi
  if [[ "$rm_args" == *'*' ]]; then rm_danger=1; fi
  if [[ "$rm_args" == *'..'* ]]; then rm_danger=1; fi
  if printf '%s' "$rm_args" | grep -qE '(^|[[:space:]])(/|~)([[:space:]]|$)'; then rm_danger=1; fi
  if printf '%s' "$rm_args" | grep -qE '(^|[[:space:]])~/'; then rm_danger=1; fi
  if { [[ $rm_recursive -eq 1 && $rm_force -eq 1 ]]; } || [[ $rm_danger -eq 1 ]]; then
    deny "🚫 禁止破坏性 rm（rm -rf，或针对根/家/\$HOME/通配符的删除，不可逆）。请改用 \`trash-put <path>\` / \`gio trash <path>\`，或先 \`mv <path> /tmp/\` 保留可恢复副本。"
  fi
  RM_HINT="💡 检测到 rm：建议改用 \`trash-put\`/\`gio trash\` 或 \`mv\` 到临时目录，避免误删重要文件后无法恢复。"
fi

# ─── Phase 2: 只读命令白名单 ─────────────────────────────────────────────────
FIRST="$(printf '%s' "$CMD" | sed -E 's/^[[:space:]]*//' | awk '{print $1}')"
BASE="$(basename "${FIRST:-cmd}" 2>/dev/null || printf '%s' "${FIRST:-cmd}")"
case "$BASE" in
  cat|head|tail|bat|echo|printf|seq|date|uptime) allow ;;
  wc|sort|uniq|tr|cut|column|rev|tac|paste|comm|diff|patch) allow ;;
  whoami|id|hostname|uname|pwd|env|printenv|which|whereis|command|type) allow ;;
  file|stat|realpath|readlink|basename|dirname|test|true|false) allow ;;
  ls|tree|dust|df|free) allow ;;
  rg|ag|ack|fd) allow ;;
  jq|yq|mlr) allow ;;
  dig|nslookup|host|ping|traceroute) allow ;;
  guix)
    for word in $CMD; do
      case "$word" in
        describe|show|search|hash|lint|size|graph|weather) allow ;;
      esac
    done
    ;;
  git)
    git_only_read=1
    for word in $CMD; do
      case "$word" in
        commit|push|merge|rebase|reset|checkout|switch|cherry-pick|bisect|am|clean|format-patch) git_only_read=0; break ;;
      esac
    done
    [[ "$git_only_read" -eq 1 ]] && allow
    ;;
esac

# ─── Phase 3+4: 非阻塞提醒（zcode 无法改写命令，只提醒）─────────────────────
NOTES=""
builtin_rw="$(jq -r '.builtin_rewrite' <<<"$MERGED" 2>/dev/null || printf 'true')"
if [[ "$builtin_rw" == "true" ]]; then
  has_npm="$(jq -r '.rewrite | has("npm")' <<<"$MERGED" 2>/dev/null || printf 'false')"
  has_pip="$(jq -r '.rewrite | has("pip") or has("pip3")' <<<"$MERGED" 2>/dev/null || printf 'false')"
  if [[ "$has_npm" != "true" ]] && printf '%s' "$CMD" | grep -qE '(^|[|&;])[[:space:]]*npm\b'; then
    NOTES="${NOTES:+$NOTES; }npm → pnpm"
  fi
  if [[ "$has_pip" != "true" ]] && printf '%s' "$CMD" | grep -qE '(^|[|&;])[[:space:]]*pip3?\b'; then
    NOTES="${NOTES:+$NOTES; }pip → uv pip"
  fi
fi
while IFS=$'\t' read -r from to; do
  [[ -z "$from" ]] && continue
  esc_from="$(printf '%s' "$from" | sed 's/[.[\*^$()+?{|\\]/\\&/g')"
  if printf '%s' "$CMD" | grep -qE "(^|[|&;])[[:space:]]*${esc_from}\\b"; then
    NOTES="${NOTES:+$NOTES; }${from} → ${to}"
  fi
done < <(jq -r '.rewrite | to_entries[] | "\(.key)\t\(.value)"' <<<"$MERGED" 2>/dev/null)

REDIRECT_MSG=""; REDIRECT_PAT=""
while IFS=$'\t' read -r pat msg; do
  [[ -z "$pat" ]] && continue
  if [[ "$CMD" == *"$pat"* ]] && [[ ${#pat} -gt ${#REDIRECT_PAT} ]]; then
    REDIRECT_PAT="$pat"; REDIRECT_MSG="💡 ${msg}"
  fi
done < <(jq -r '.redirect_conventions | to_entries[] | "\(.key)\t\(.value)"' <<<"$MERGED" 2>/dev/null)

PARTS=()
[[ -n "$RM_HINT" ]] && PARTS+=("$RM_HINT")
[[ -n "$NOTES" ]] && PARTS+=("本机偏好命令替代：${NOTES}；如适用请改用后重新执行")
[[ -n "$REDIRECT_MSG" ]] && PARTS+=("$REDIRECT_MSG")

if [[ ${#PARTS[@]} -gt 0 ]]; then
  ctx="$(IFS='; '; echo "${PARTS[*]}")"
  printf '{"additionalContext":%s}\n' "$(printf '%s' "$ctx" | jq -Rs .)"
fi
exit 0
