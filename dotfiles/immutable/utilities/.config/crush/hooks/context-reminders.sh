#!/usr/bin/env bash
set -euo pipefail

FILE="${CRUSH_TOOL_INPUT_FILE_PATH:-}"
PROJ="${CRUSH_PROJECT_DIR:-}"
MSG=()

REL="${FILE#"$PROJ"/}"

# dotfiles 修改提醒
if [[ "$REL" == dotfiles/* ]]; then
  MSG+=("此文件修改后需要运行 maak home 才能生效")
fi

# org 文件修改提醒
if [[ "$FILE" == *.org ]]; then
  MSG+=("修改 org 配置后，务必先用 MAAK_DRY_RUN=1 maak home 或 maak system 验证")
fi

if [[ ${#MSG[@]} -gt 0 ]]; then
  CONTEXT=$(printf "%s; " "${MSG[@]}")
  # Remove trailing "; "
  CONTEXT="${CONTEXT%; }"
  # Escape for JSON
  CONTEXT_ESC=$(echo "$CONTEXT" | sed 's/\\/\\\\/g; s/"/\\"/g')
  echo "{\"context\": \"$CONTEXT_ESC\"}"
else
  echo '{}'
fi
