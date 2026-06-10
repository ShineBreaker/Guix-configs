#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

set -euo pipefail

FILE="${CRUSH_TOOL_INPUT_FILE_PATH:-}"
PROJ="${CRUSH_PROJECT_DIR:-}"
TOOL="${CRUSH_TOOL_NAME:-}"
REL="${FILE#"$PROJ"/}"

# --- Phase 1: Block checks ---

# Protected paths
if [[ "$REL" == tmp/* ]]; then
  echo "禁止手动编辑 tmp/ 目录，请修改 source/ 中的 .org 源文件" >&2; exit 2
fi

if [[ "$FILE" == */channel.lock ]]; then
  echo "禁止手动编辑 channel.lock，请使用 maak upgrade 更新" >&2; exit 2
fi

if echo "$FILE" | grep -qE '^/home/[^/]+/\.(config|local)/'; then
  if ! echo "$FILE" | grep -q "$PROJ"; then
    echo "禁止直接修改安装位置，请修改 dotfiles/ 后运行 maak home" >&2; exit 2
  fi
fi

# Sensitive info detection (write/edit/multiedit only)
INPUT=$(cat)
CONTENT=""

case "$TOOL" in
  write)
    CONTENT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('content',''), end='')" 2>/dev/null || true)
    ;;
  edit|multiedit)
    CONTENT=$(echo "$INPUT" | python3 -c "
import sys, json
inp = json.load(sys.stdin)
ti = inp.get('tool_input', {})
if 'new_string' in ti:
    print(ti.get('new_string', ''), end='')
elif 'edits' in ti:
    for e in ti['edits']:
        print(e.get('new_string', ''), end='')
" 2>/dev/null || true)
    ;;
esac

if [[ -n "$CONTENT" ]]; then
  TMPFILE=$(mktemp)
  trap "rm -f '$TMPFILE'" EXIT
  printf '%s' "$CONTENT" > "$TMPFILE"

  FOUND=""
  if grep -qiE 'sk-[a-zA-Z0-9]{20,}' "$TMPFILE"; then
    FOUND="检测到疑似 API key（sk-...）"
  fi
  if grep -qiE '(password|passwd|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*[\"\047][^\"\047[:space:]]{8,}[\"\047]' "$TMPFILE"; then
    FOUND="${FOUND}; 检测到明文密码/secret/token"
  fi
  if grep -qE -e '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----' "$TMPFILE"; then
    FOUND="${FOUND}; 检测到 SSH 私钥"
  fi
  if grep -qiE 'AKIA[0-9A-Z]{16}' "$TMPFILE"; then
    FOUND="${FOUND}; 检测到疑似 AWS access key"
  fi
  if grep -qiE 'ghp_[a-zA-Z0-9]{36}' "$TMPFILE"; then
    FOUND="${FOUND}; 检测到疑似 GitHub token"
  fi

  if [[ -n "$FOUND" ]]; then
    FOUND="${FOUND#; }"
    echo "检测到敏感信息: $FOUND。如确认无风险请手动重试。" >&2
    exit 49
  fi
fi

# --- Phase 2: Context reminders ---

MSG=()
if [[ "$REL" == dotfiles/* ]]; then
  MSG+=("此文件修改后需要运行 maak home 才能生效")
fi
if [[ "$FILE" == *.org ]]; then
  MSG+=("修改 org 配置后，务必先用 MAAK_DRY_RUN=1 maak home 或 maak system 验证")
fi

if [[ ${#MSG[@]} -gt 0 ]]; then
  CONTEXT=$(printf "%s; " "${MSG[@]}")
  CONTEXT="${CONTEXT%; }"
  CONTEXT_ESC=$(echo "$CONTEXT" | sed 's/\\/\\\\/g; s/"/\\"/g')
  echo "{\"context\": \"$CONTEXT_ESC\"}"
else
  echo '{}'
fi
