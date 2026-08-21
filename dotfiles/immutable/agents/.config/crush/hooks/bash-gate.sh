#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# bash-gate.sh — crush 的 bash 工具拦截 hook
#
# 规则源：anchors.json（与 pi-gate 同源）
#   - 全局 ~/.config/agents/anchors.json（meta-frozen，人工维护）
#   - 项目级 <root>/.agents/anchors.json（ratchet 加码；从 $PWD 向上到 git 根）
#   合并由 anchors-lib.sh 的 load_merged_anchors 完成。
# 语义对齐：dotfiles/mutable/agents/pi/.config/pi/extensions/pi-gate/index.ts
#
# crush hook 协议：
#   - 环境变量 CRUSH_TOOL_INPUT_COMMAND 传入命令
#   - stdout 输出 JSON：{"decision":"allow"} | {"context":...} | {"updated_input":{...}} | {}
#   - stderr + exit 2 = 硬拦截（deny）

set -euo pipefail

CMD="${CRUSH_TOOL_INPUT_COMMAND:-}"

# ─── Phase 0: 加载 anchors-lib + 合并配置 ───────────────────────────────────
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
  # lib 加载失败：降级 DEFAULT（sudo 仍拦），代码底层（交互式/git/rm/敏感信息）不依赖配置
  MERGED="$DEFAULT_MERGED"
else
  MERGED="$(load_merged_anchors "${PWD:-$HOME}" 2>/dev/null || printf '%s' "$DEFAULT_MERGED")"
  warn_globs_if_any "$MERGED"
fi

deny() { printf '%s\n' "$1" >&2; exit 2; }

# 命令起始位置前缀（对齐 pi-gate PREFIX）：行首 或 ; & | ( $ && || 之后可选空白
PREFIX='(^|[;&|()$]|&&|\|\|)[[:space:]]*'

# ─── Phase 1: 硬拦截（命中即 deny）─────────────────────────────────────────

# 1a 冻结命令（子串匹配，jq 读）+ --dry-run 兜底放行 + guix system 宽匹配
if [[ "$CMD" != *"--dry-run"* ]]; then
  while IFS= read -r frozen; do
    [[ -z "$frozen" ]] && continue
    if [[ "$CMD" == *"$frozen"* ]]; then
      deny "🚫 冻结命令「${frozen}」需 sudo 提权或为系统级操作，禁止 agent 执行。验证请用 \`blue --dry-run rebuild\`；固化请提醒用户手动运行。"
    fi
  done < <(jq -r '.frozen_commands[]?' <<<"$MERGED" 2>/dev/null)
  # guix system reconfigure/init 宽匹配（含 time-machine ... -- system reconfigure 包装）
  if [[ "$CMD" == *"guix"* ]] && printf '%s' "$CMD" | grep -qE '\bsystem[[:space:]]+(reconfigure|init)\b'; then
    deny "🚫 禁止 guix system reconfigure/init（含 time-machine 包装，需 sudo）。验证请用 \`blue --dry-run rebuild\`；固化请提醒用户手动运行。"
  fi
fi

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

# 1d rm 破坏性删除防护（对齐 pi-gate checkRmCommand）
#   硬拦：rm -rf（递归+强制），或针对根/家/$HOME/通配/.. 的删除（不可逆）
#   软提示：其余 rm → 建议改 trash/mv（保留可恢复副本）
RM_HINT=""
if printf '%s' "$CMD" | grep -qE "${PREFIX}rm\b"; then
  rm_args="${CMD#*rm}"
  rm_recursive=0; rm_force=0; rm_danger=0
  if printf '%s' "$rm_args" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[rR]|--recursive'; then rm_recursive=1; fi
  if printf '%s' "$rm_args" | grep -qE '(^|[[:space:]])-[a-zA-Z]*f|--force'; then rm_force=1; fi
  # 危险目标（分项检测，避免复杂正则转义）
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

# ─── Phase 2: 只读命令 auto-approve 白名单 ──────────────────────────────────
# 位置在 Phase 1 之后——白名单不绕过冻结/破坏性/交互式规则。
FIRST="$(printf '%s' "$CMD" | sed -E 's/^[[:space:]]*//' | awk '{print $1}')"
BASE="$(basename "${FIRST:-cmd}" 2>/dev/null || printf '%s' "${FIRST:-cmd}")"

case "$BASE" in
  cat|head|tail|bat|echo|printf|seq|date|uptime) printf '{"decision":"allow"}\n'; exit 0 ;;
  wc|sort|uniq|tr|cut|column|rev|tac|paste|comm|diff|patch) printf '{"decision":"allow"}\n'; exit 0 ;;
  whoami|id|hostname|uname|pwd|env|printenv|which|whereis|command|type) printf '{"decision":"allow"}\n'; exit 0 ;;
  file|stat|realpath|readlink|basename|dirname|test|true|false) printf '{"decision":"allow"}\n'; exit 0 ;;
  ls|tree|dust|df|free) printf '{"decision":"allow"}\n'; exit 0 ;;
  rg|ag|ack|fd) printf '{"decision":"allow"}\n'; exit 0 ;;
  jq|yq|mlr) printf '{"decision":"allow"}\n'; exit 0 ;;
  dig|nslookup|host|ping|traceroute) printf '{"decision":"allow"}\n'; exit 0 ;;
  guix)
    for word in $CMD; do
      case "$word" in
        describe|show|search|hash|lint|size|graph|weather) printf '{"decision":"allow"}\n'; exit 0 ;;
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
    if [[ "$git_only_read" -eq 1 ]]; then printf '{"decision":"allow"}\n'; exit 0; fi
    ;;
esac

# ─── Phase 3: 命令改写（对齐 pi-gate rewriteCommand）────────────────────────
# builtin：npm→pnpm / pip→uv pip（anchors.json rewrite 未自定义同名 key 时生效）
# 移除了旧 crush 的 du→dust / find→fd / grep→rg（pi-gate 无此 builtin；如需可放进 rewrite map）
REWRITTEN="$CMD"
NOTES=""
sed_escape_re() { printf '%s' "$1" | sed 's/[.[\*^$()+?{|\\]/\\&/g'; }
sed_escape_repl() { printf '%s' "$1" | sed 's/[&#\\]/\\&/g'; }

builtin_rw="$(jq -r '.builtin_rewrite' <<<"$MERGED" 2>/dev/null || printf 'true')"
if [[ "$builtin_rw" == "true" ]]; then
  has_npm="$(jq -r '.rewrite | has("npm")' <<<"$MERGED" 2>/dev/null || printf 'false')"
  has_pip="$(jq -r '.rewrite | has("pip") or has("pip3")' <<<"$MERGED" 2>/dev/null || printf 'false')"
  if [[ "$has_npm" != "true" ]]; then
    new="$(printf '%s' "$REWRITTEN" | sed -E 's/(^|[|&;])[[:space:]]*npm\b/\1pnpm/g')"
    if [[ "$new" != "$REWRITTEN" ]]; then REWRITTEN="$new"; NOTES="${NOTES:+$NOTES, }npm→pnpm"; fi
  fi
  if [[ "$has_pip" != "true" ]]; then
    new="$(printf '%s' "$REWRITTEN" | sed -E 's/(^|[|&;])[[:space:]]*pip3?\b/\1uv pip/g')"
    if [[ "$new" != "$REWRITTEN" ]]; then REWRITTEN="$new"; NOTES="${NOTES:+$NOTES, }pip→uv pip"; fi
  fi
fi

# 项目层 rewrite map（数据驱动，from → to）
while IFS=$'\t' read -r from to; do
  [[ -z "$from" ]] && continue
  esc_from="$(sed_escape_re "$from")"
  esc_to="$(sed_escape_repl "$to")"
  new="$(printf '%s' "$REWRITTEN" | sed -E "s#(^|[|&;])[[:space:]]*${esc_from}\\b#\\1${esc_to}#g")"
  if [[ "$new" != "$REWRITTEN" ]]; then REWRITTEN="$new"; NOTES="${NOTES:+$NOTES, }${from}→${to}"; fi
done < <(jq -r '.rewrite | to_entries[] | "\(.key)\t\(.value)"' <<<"$MERGED" 2>/dev/null)

# ─── Phase 4: 软提示 redirect_conventions（命中最长 pattern 胜出）───────────
REDIRECT_MSG=""; REDIRECT_PAT=""
while IFS=$'\t' read -r pat msg; do
  [[ -z "$pat" ]] && continue
  if [[ "$CMD" == *"$pat"* ]] && [[ ${#pat} -gt ${#REDIRECT_PAT} ]]; then
    REDIRECT_PAT="$pat"; REDIRECT_MSG="💡 ${msg}"
  fi
done < <(jq -r '.redirect_conventions | to_entries[] | "\(.key)\t\(.value)"' <<<"$MERGED" 2>/dev/null)

# ─── 输出（jq 构造 JSON，避免手工转义 bug）──────────────────────────────────
CONTEXT_PARTS=()
[[ -n "$RM_HINT" ]] && CONTEXT_PARTS+=("$RM_HINT")
[[ -n "$REDIRECT_MSG" ]] && CONTEXT_PARTS+=("$REDIRECT_MSG")
[[ -n "$NOTES" ]] && CONTEXT_PARTS+=("已替换命令 (${NOTES})，注意参数差异")

if [[ "$REWRITTEN" != "$CMD" ]]; then
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
