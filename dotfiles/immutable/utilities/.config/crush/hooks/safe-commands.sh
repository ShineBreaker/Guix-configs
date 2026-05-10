#!/usr/bin/env bash
set -euo pipefail

CMD="${CRUSH_TOOL_INPUT_COMMAND:-}"

FIRST=$(echo "$CMD" | sed -E 's/^\s*//' | awk '{print $1}')
BASE=$(basename "${FIRST:-}" 2>/dev/null || echo "${FIRST:-}")

case "$BASE" in
  cat|head|tail|bat)
    echo '{"decision":"allow"}'; exit 0;;
  echo|printf|seq|date|uptime|sleep)
    echo '{"decision":"allow"}'; exit 0;;
  wc|sort|uniq|tr|cut|column|rev|tac|paste|comm|diff|patch)
    echo '{"decision":"allow"}'; exit 0;;
  whoami|id|hostname|uname|pwd|env|printenv|which|whereis|command|type)
    echo '{"decision":"allow"}'; exit 0;;
  file|stat|realpath|readlink|basename|dirname|test|true|false)
    echo '{"decision":"allow"}'; exit 0;;
  ls|tree|du|dust|df|free)
    echo '{"decision":"allow"}'; exit 0;;
  grep|rg|ag|ack|fd|find)
    echo '{"decision":"allow"}'; exit 0;;
  jq|yq|mlr)
    echo '{"decision":"allow"}'; exit 0;;
  dig|nslookup|host|ping|traceroute|curl|wget)
    echo '{"decision":"allow"}'; exit 0;;
  git)
    ONLY_READ=true
    for word in $CMD; do
      case "$word" in
        commit|push|merge|rebase|reset|checkout|switch|branch\ -[dD]|tag\ -d|stash\ drop|clean|cherry-pick|bisect|am|format-patch|fetch|pull|clone|remote\ add|remote\ remove|submodule\ update|worktree\ add|worktree\ remove|blame)
          ONLY_READ=false; break;;
      esac
    done
    if [[ "$ONLY_READ" == "true" ]]; then
      echo '{"decision":"allow"}'; exit 0
    fi
    ;;
  guix)
    for word in $CMD; do
      case "$word" in
        describe|show|search|package\ --list-available|package\ --list-installed|hash|lint|size|graph|weather|pull\ --list-generations|time-machine\ --help)
          echo '{"decision":"allow"}'; exit 0;;
      esac
    done
    ;;
  guix\.*|maak)
    ;;
esac

echo '{}'
