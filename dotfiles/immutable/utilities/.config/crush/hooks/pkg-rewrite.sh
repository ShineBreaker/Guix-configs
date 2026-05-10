#!/usr/bin/env bash
set -euo pipefail

CMD="${CRUSH_TOOL_INPUT_COMMAND:-}"
REWRITTEN="$CMD"

REWRITTEN=$(echo "$REWRITTEN" | sed -E \
  -e 's/(^|[|&;]|\s)npm\b/\1pnpm/g' \
  -e 's/(^|[|&;]|\s)pip3?\b/\1uv pip/g')

if [[ "$REWRITTEN" != "$CMD" ]]; then
  # Escape for JSON
  REWRITTEN_ESC=$(echo "$REWRITTEN" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')
  echo "{\"context\": \"已将包管理器命令替换为项目规范版本 (npm→pnpm, pip→uv)\", \"updated_input\": {\"command\": \"$REWRITTEN_ESC\"}}"
else
  echo '{}'
fi
