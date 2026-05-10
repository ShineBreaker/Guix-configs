#!/usr/bin/env bash
set -euo pipefail

CMD="${CRUSH_TOOL_INPUT_COMMAND:-}"

# 拦截直接调用 guix system/home reconfigure（maak 内部调用不受影响）
if echo "$CMD" | grep -qE '(^|\s)guix\s+(system|home)\s+reconfigure'; then
  echo "禁止直接运行 guix reconfigure，请使用 maak system 或 maak home" >&2
  exit 2
fi

echo '{}'
