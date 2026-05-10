#!/usr/bin/env bash
set -euo pipefail

FILE="${CRUSH_TOOL_INPUT_FILE_PATH:-}"
PROJ="${CRUSH_PROJECT_DIR:-}"

# 禁止修改 tmp/ 目录
if [[ "$FILE" == *"/tmp/"* ]] || [[ "$FILE" == *"/tmp"* && -d "${PROJ}/tmp" ]]; then
  REL="${FILE#"$PROJ"/}"
  if [[ "$REL" == tmp/* ]]; then
    echo "禁止手动编辑 tmp/ 目录，请修改 source/ 中的 .org 源文件" >&2
    exit 2
  fi
fi

# 禁止修改 channel.lock
if [[ "$FILE" == */channel.lock ]]; then
  echo "禁止手动编辑 channel.lock，请使用 maak upgrade 更新" >&2
  exit 2
fi

# 禁止编辑子模块
if echo "$FILE" | grep -qE '(emacs/\.config/emacs/|fcitx5/rime/|crush-superpowers/)'; then
  echo "禁止直接编辑子模块内容，请到对应上游仓库修改" >&2
  exit 2
fi

# 禁止修改 ~/.config ~/.local 等安装路径（不在项目 dotfiles/ 内）
if echo "$FILE" | grep -qE '^/home/[^/]+/\.(config|local)/'; then
  if ! echo "$FILE" | grep -q "$PROJ"; then
    echo "禁止直接修改安装位置的文件，请修改 dotfiles/ 中的源文件后运行 maak home" >&2
    exit 2
  fi
fi

echo '{}'
