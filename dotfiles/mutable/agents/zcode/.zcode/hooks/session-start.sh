#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# session-start — zcode SessionStart hook
#
# 会话开始时注入当前项目的 anchors 防护规则摘要到 context（additionalContext），
# 让 agent 启动即知边界：冻结命令/路径、重定向建议、路径提示、仅人工操作。
# 规则源与 pi-gate / crush / zcode gate 同：anchors.json（全局 + 项目级 ratchet）。
# 另注入全局上下文（~/.config/agents/context/）：注入哪些文件由 context-select.sh
# 统一决策（决策核与 omp / hermes 共享），本脚本只做协议转换与预算控制。

set -euo pipefail

# ─── 读 cwd + source lib + 加载 anchors ─────────────────────────────────────
INPUT="$(cat 2>/dev/null || true)"
CWD="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('cwd', ''), end='')
except Exception:
    print('', end='')
" 2>/dev/null || true)"
CWD="${CWD:-${CLAUDE_PROJECT_DIR:-${ZCODE_PROJECT_DIR:-$PWD}}}"

DEFAULT_MERGED='{"frozen_commands":["sudo"],"frozen_paths":[],"frozen_globs":[],"redirect_conventions":{},"rewrite":{},"path_hints":{},"builtin_rewrite":true,"human_only_actions":[],"anchor_measurements":[]}'
if ! source "$HOME/.config/agents/anchors-lib.sh" 2>/dev/null; then
  MERGED="$DEFAULT_MERGED"
else
  MERGED="$(load_merged_anchors "$CWD" 2>/dev/null || printf '%s' "$DEFAULT_MERGED")"
fi

# ─── 生成摘要 ───────────────────────────────────────────────────────────────
PROJ="$(find_git_root "$CWD" 2>/dev/null || printf '%s' "$CWD")"
PROJ_NAME=""
if [[ "$PROJ" != "$HOME" && -d "$PROJ/.git" ]]; then
  PROJ_NAME=" + 项目 $(basename "$PROJ")/.agents/anchors.json"
fi

# 人工总开关（固定路径，见 gate-core.sh 文件头）：存在时摘要改为暂停态，
# 避免 agent 误以为规则仍在生效。
if [[ -f "/run/agent-gate.off" ]]; then
  SUMMARY="[anchors 护栏已手动暂停（/run/agent-gate.off 存在）：冻结命令/路径暂不拦截，恢复请人工删除该开关文件]"
else
  SUMMARY="[anchors 防护规则已加载（源：~/.config/agents/anchors.json${PROJ_NAME}）]"
fi

FC="$(jq -r '.frozen_commands | if length>0 then "[冻结命令] 禁止执行，需提示用户手动操作：\n  " + (join("， ")) else empty end' <<<"$MERGED" 2>/dev/null || true)"
[[ -n "$FC" ]] && SUMMARY+=$'\n\n'"$FC"

FP="$(jq -r '.frozen_paths | if length>0 then "[冻结路径] 禁止写入，修改需改源码后执行 blue home：\n  " + ([.[] | if type == "string" then . else (.path + "〔cwd 在 " + (.unless_inside // "?") + " 内豁免〕") end] | join("， ")) else empty end' <<<"$MERGED" 2>/dev/null || true)"
[[ -n "$FP" ]] && SUMMARY+=$'\n\n'"$FP"

RC="$(jq -r '.redirect_conventions | if length>0 then "[重定向建议]\n" + ([to_entries[] | "  " + .key + " → " + .value] | join("\n")) else empty end' <<<"$MERGED" 2>/dev/null || true)"
[[ -n "$RC" ]] && SUMMARY+=$'\n\n'"$RC"

PH="$(jq -r '.path_hints | if length>0 then "[路径提示] 修改后需执行联动操作：\n" + ([to_entries[] | "  " + .key + " → " + .value] | join("\n")) else empty end' <<<"$MERGED" 2>/dev/null || true)"
[[ -n "$PH" ]] && SUMMARY+=$'\n\n'"$PH"

HO="$(jq -r '.human_only_actions | if length>0 then "[仅人工操作] agent 不得执行：\n" + ([.[] | "  " + .] | join("\n")) else empty end' <<<"$MERGED" 2>/dev/null || true)"
[[ -n "$HO" ]] && SUMMARY+=$'\n\n'"$HO"

# ─── 全局上下文（context-select.sh 决策注入）────────────────────────────────
# 源 ~/.config/agents/context/；注入清单由 context-select.sh 统一决策（决策核
# 与 omp / hermes 共享）：00-core 与 INDEX 恒注入，git 仓库内自动附加 coding 域。
# 预算对齐 omp：单文件 64KiB 跳过，总量 192KiB 截断。
SELECTOR="${CONTEXT_SELECT_BIN:-$HOME/.config/agents/context-select.sh}"
CTX=""
CTX_FILES=()
if [[ -x "$SELECTOR" ]]; then
  mapfile -t CTX_FILES < <("$SELECTOR" --platform zcode --cwd "$CWD" 2>/dev/null || true)
else
  # fallback：selector 未部署时直接 cat 恒注入两件（存在才 cat），保证不空转
  for f in "$HOME/.config/agents/context/00-core.md" "$HOME/.config/agents/context/INDEX.md"; do
    [[ -f "$f" ]] && CTX_FILES+=("$f")
  done
fi

CTX_FILE_MAX=$((64 * 1024))
CTX_MAX=$((192 * 1024))
CTX_TOTAL=0
for f in ${CTX_FILES[@]+"${CTX_FILES[@]}"}; do
  [[ -f "$f" ]] || continue
  size="$(wc -c <"$f")"
  if (( size > CTX_FILE_MAX )); then
    printf 'session-start: 跳过超大上下文文件（%d B > %d B 上限）：%s\n' "$size" "$CTX_FILE_MAX" "$f" >&2
    continue
  fi
  if (( CTX_TOTAL + size > CTX_MAX )); then
    CTX+="$(head -c "$((CTX_MAX - CTX_TOTAL))" "$f")"$'\n\n'
    printf 'session-start: 上下文总量触顶 %d B，已截断：%s\n' "$CTX_MAX" "$f" >&2
    break
  fi
  CTX+="$(cat "$f")"$'\n\n'
  CTX_TOTAL=$((CTX_TOTAL + size))
done
[[ -n "$CTX" ]] && SUMMARY="[全局上下文已加载（源：~/.config/agents/context/，由 context-select.sh 决策：恒注入 00-core / INDEX，git 仓库内自动附加 coding 域；决策核与 omp / hermes 共享）]"$'\n\n'"$CTX"$'\n'"$SUMMARY"

printf '{"additionalContext":%s}\n' "$(printf '%s' "$SUMMARY" | jq -Rs .)"
