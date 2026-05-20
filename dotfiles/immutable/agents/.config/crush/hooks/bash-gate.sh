#!/usr/bin/env bash
set -euo pipefail

CMD="${CRUSH_TOOL_INPUT_COMMAND:-}"

# --- Phase 1: Block checks (deny/halt takes priority) ---

# Block interactive commands (will hang without TTY)
if echo "$CMD" | grep -qE '(^|\s)(vi|nano|pico|ed)\b'; then
  echo "禁止交互式编辑器，请使用 edit/write 工具" >&2; exit 2
fi
if echo "$CMD" | grep -qE '(^|\s)(less|more|most|pg)\b'; then
  echo "禁止交互式 pager，请使用 view/grep 工具" >&2; exit 2
fi
if echo "$CMD" | grep -qE '(^|\s)man\s'; then
  echo "禁止 man，请使用 --help 或在线文档" >&2; exit 2
fi
if echo "$CMD" | grep -qE '(^|\s)git\s+commit\b' && ! echo "$CMD" | grep -qE '\s(-m|--message)\b'; then
  echo "git commit 必须使用 -m 指定提交信息" >&2; exit 2
fi
if echo "$CMD" | grep -qE '(^|\s)git\s+add\s.*-p\b'; then
  echo "禁止 git add -p" >&2; exit 2
fi
if echo "$CMD" | grep -qE '(^|\s)git\s+rebase\s.*-i\b'; then
  echo "禁止 git rebase -i" >&2; exit 2
fi
if echo "$CMD" | grep -qE '(^|\s)(python|python3)\s*$'; then
  echo "禁止裸 REPL，请使用 python -c '...' 或 python script.py" >&2; exit 2
fi
if echo "$CMD" | grep -qE '(^|\s)node\s*$'; then
  echo "禁止裸 REPL，请使用 node -e '...' 或 node script.js" >&2; exit 2
fi
if echo "$CMD" | grep -qE '(^|\s)ipython\b'; then
  echo "禁止 ipython，请使用 python -c '...'" >&2; exit 2
fi

# Block direct guix reconfigure
if echo "$CMD" | grep -qE '(^|\s)guix\s+(system|home)\s+reconfigure'; then
  echo "禁止直接 guix reconfigure，请使用 maak system 或 maak home" >&2; exit 2
fi

# --- Phase 2: Auto-approve safe commands ---

FIRST=$(echo "$CMD" | sed -E 's/^\s*//' | awk '{print $1}')
BASE=$(basename "${FIRST:-}" 2>/dev/null || echo "${FIRST:-}")

case "$BASE" in
  cat|head|tail|bat|echo|printf|seq|date|uptime)
    echo '{"decision":"allow"}'; exit 0;;
  wc|sort|uniq|tr|cut|column|rev|tac|paste|comm|diff|patch)
    echo '{"decision":"allow"}'; exit 0;;
  whoami|id|hostname|uname|pwd|env|printenv|which|whereis|command|type)
    echo '{"decision":"allow"}'; exit 0;;
  file|stat|realpath|readlink|basename|dirname|test|true|false)
    echo '{"decision":"allow"}'; exit 0;;
  ls|tree|dust|df|free)
    echo '{"decision":"allow"}'; exit 0;;
  rg|ag|ack|fd)
    echo '{"decision":"allow"}'; exit 0;;
  jq|yq|mlr)
    echo '{"decision":"allow"}'; exit 0;;
  dig|nslookup|host|ping|traceroute)
    echo '{"decision":"allow"}'; exit 0;;
  guix)
    for word in $CMD; do
      case "$word" in
        describe|show|search|hash|lint|size|graph|weather)
          echo '{"decision":"allow"}'; exit 0;;
      esac
    done
    ;;
  git)
    ONLY_READ=true
    for word in $CMD; do
      case "$word" in
        commit|push|merge|rebase|reset|checkout|switch|cherry-pick|bisect|am|clean|stash\ drop|tag\ -d|format-patch)
          ONLY_READ=false; break;;
      esac
    done
    if [[ "$ONLY_READ" == "true" ]]; then
      echo '{"decision":"allow"}'; exit 0
    fi
    ;;
esac

# --- Phase 3: Command rewrite ---

REWRITTEN="$CMD"
REWRITTEN=$(echo "$REWRITTEN" | sed -E \
  -e 's/(^|[|&;]|\s)npm\b/\1pnpm/g' \
  -e 's/(^|[|&;]|\s)pip3?\b/\1uv pip/g' \
  -e 's/(^|[|&;]|\s)du\b/\1dust/g' \
  -e 's/(^|[|&;]|\s)find\b/\1fd/g' \
  -e 's/(^|[|&;]|\s)grep\b/\1rg/g')

if [[ "$REWRITTEN" != "$CMD" ]]; then
  REWRITTEN_ESC=$(echo "$REWRITTEN" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')
  echo "{\"context\": \"已替换命令 (npm→pnpm, pip→uv, du→dust, find→fd, grep→rg)，注意 fd/rg 参数有差异\", \"updated_input\": {\"command\": \"$REWRITTEN_ESC\"}}"
else
  echo '{}'
fi
