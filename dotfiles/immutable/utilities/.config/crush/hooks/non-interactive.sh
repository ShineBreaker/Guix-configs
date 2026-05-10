#!/usr/bin/env bash
set -euo pipefail

CMD="${CRUSH_TOOL_INPUT_COMMAND:-}"

# --- Banned interactive commands ---

# Editors that will hang without TTY
if echo "$CMD" | grep -qE '(^|\s)(vim|vi|nano|emacs|pico|ed)\b'; then
  echo "禁止在 agent 环境中使用交互式编辑器，请使用 edit/write 工具编辑文件" >&2
  exit 2
fi

# Pagers that will hang without TTY
if echo "$CMD" | grep -qE '(^|\s)(less|more|most|pg)\b'; then
  echo "禁止在 agent 环境中使用交互式 pager，请使用 view/grep 工具查看内容" >&2
  exit 2
fi

# man pages that will hang
if echo "$CMD" | grep -qE '(^|\s)man\s'; then
  echo "禁止在 agent 环境中使用 man，请使用 --help 或在线文档" >&2
  exit 2
fi

# pkexec requires GUI PolicyKit auth dialog — will hang
if echo "$CMD" | grep -qE '(^|\s)pkexec\b'; then
  echo "pkexec 需要 GUI 认证弹窗，在 agent 环境中会 hang。需要权限的操作请使用 maak system" >&2
  exit 2
fi

# --- Interactive git commands ---

# git commit without -m (will open editor)
if echo "$CMD" | grep -qE '(^|\s)git\s+commit\b' && ! echo "$CMD" | grep -qE '\s(-m|--message)\b'; then
  echo "git commit 必须使用 -m 指定提交信息" >&2
  exit 2
fi

# git add -p (interactive patch mode)
if echo "$CMD" | grep -qE '(^|\s)git\s+add\s.*-p\b'; then
  echo "禁止在 agent 环境中使用 git add -p（交互式补丁模式）" >&2
  exit 2
fi

# git rebase -i (interactive rebase)
if echo "$CMD" | grep -qE '(^|\s)git\s+rebase\s.*-i\b'; then
  echo "禁止在 agent 环境中使用 git rebase -i（交互式 rebase）" >&2
  exit 2
fi

# --- Bare REPL invocations (will hang) ---

# python/python3 without -c or script argument
if echo "$CMD" | grep -qE '(^|\s)(python|python3)\s*$'; then
  echo "禁止启动交互式 Python REPL，请使用 python -c '...' 或 python script.py" >&2
  exit 2
fi

# node without -e or script argument
if echo "$CMD" | grep -qE '(^|\s)node\s*$'; then
  echo "禁止启动交互式 Node REPL，请使用 node -e '...' 或 node script.js" >&2
  exit 2
fi

# ipython always interactive
if echo "$CMD" | grep -qE '(^|\s)ipython\b'; then
  echo "禁止在 agent 环境中使用 ipython，请使用 python -c '...'" >&2
  exit 2
fi

echo '{}'