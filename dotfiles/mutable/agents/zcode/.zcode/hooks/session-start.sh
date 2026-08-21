#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# session-start — zcode SessionStart hook
#
# 会话开始时注入当前项目的 anchors 防护规则摘要到 context（additionalContext），
# 让 agent 启动即知边界：冻结命令/路径、重定向建议、路径提示、仅人工操作。
# 规则源与 pi-gate / crush / zcode gate 同：anchors.json（全局 + 项目级 ratchet）。

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

SUMMARY="[anchors 防护规则已加载（源：~/.config/agents/anchors.json${PROJ_NAME}）]"

FC="$(jq -r '.frozen_commands | if length>0 then "🚫 冻结命令（禁止执行，需提醒用户手动）：\n  " + (join("， ")) else empty end' <<<"$MERGED" 2>/dev/null || true)"
[[ -n "$FC" ]] && SUMMARY+=$'\n\n'"$FC"

FP="$(jq -r '.frozen_paths | if length>0 then "🚫 冻结路径（禁止写入，改 dotfiles 源后 blue home）：\n  " + (join("， ")) else empty end' <<<"$MERGED" 2>/dev/null || true)"
[[ -n "$FP" ]] && SUMMARY+=$'\n\n'"$FP"

RC="$(jq -r '.redirect_conventions | if length>0 then "💡 重定向建议：\n" + ([to_entries[] | "  " + .key + " → " + .value] | join("\n")) else empty end' <<<"$MERGED" 2>/dev/null || true)"
[[ -n "$RC" ]] && SUMMARY+=$'\n\n'"$RC"

PH="$(jq -r '.path_hints | if length>0 then "📝 路径提示（改后需对应操作）：\n" + ([to_entries[] | "  " + .key + " → " + .value] | join("\n")) else empty end' <<<"$MERGED" 2>/dev/null || true)"
[[ -n "$PH" ]] && SUMMARY+=$'\n\n'"$PH"

HO="$(jq -r '.human_only_actions | if length>0 then "👤 仅人工操作（agent 不可执行）：\n" + ([.[] | "  " + .] | join("\n")) else empty end' <<<"$MERGED" 2>/dev/null || true)"
[[ -n "$HO" ]] && SUMMARY+=$'\n\n'"$HO"

printf '{"additionalContext":%s}\n' "$(printf '%s' "$SUMMARY" | jq -Rs .)"
