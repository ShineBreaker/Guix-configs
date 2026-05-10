#!/usr/bin/env bash
set -euo pipefail

CMD="${CRUSH_TOOL_INPUT_COMMAND:-}"
REWRITTEN="$CMD"

REWRITTEN=$(echo "$REWRITTEN" | sed -E \
  -e 's/(^|[|&;]|\s)npm\b/\1pnpm/g' \
  -e 's/(^|[|&;]|\s)pip3?\b/\1uv pip/g' \
  -e 's/(^|[|&;]|\s)du\b/\1dust/g' \
  -e 's/(^|[|&;]|\s)find\b/\1fd/g' \
  -e 's/(^|[|&;]|\s)grep\b/\1rg/g')

if [[ "$REWRITTEN" != "$CMD" ]]; then
  REWRITTEN_ESC=$(echo "$REWRITTEN" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')
  echo "{\"context\": \"已替换命令 (npm→pnpm, pip→uv, du→dust, find→fd, grep→rg)，注意 fd/rg 参数与原命令有差异\", \"updated_input\": {\"command\": \"$REWRITTEN_ESC\"}}"
else
  echo '{}'
fi
