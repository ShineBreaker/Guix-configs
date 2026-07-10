#!/usr/bin/env bash
# 一次性把 emacs.org.newhead 替换到 emacs.org 的头部（到第一个顶层 * 之前）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORG="$ROOT/emacs.org"
HEAD="$ROOT/emacs.org.newhead"
TMP="$ORG.merging.$$.tmp"

trap 'rm -f "$TMP"' EXIT

# 取 newhead 行数（内容头不含前导空行）
HEAD_LINES=$(wc -l < "$HEAD")

# 保留新头内容，从 emacs.org 中删除旧头直到第一个顶层 * 之后（把第一个 * 标题也交给新头覆盖，因为新头已自带标题）。
# emacs.org 当前第一个顶层 * 在 "* 启动顺序与模块依赖速查" 那行；emacs.org.newhead 已包含新的该标题。
# 因此先写新头，然后 tail 从旧 emacs.org 的 "* 启动与基础设施" 那行开始（即跳过旧头到第一个 * 标题之间的内容）。
tail -n +21 "$ORG" > "$TMP.body"

cat "$HEAD" "$TMP.body" > "$TMP"
mv "$TMP" "$ORG"
rm -f "$TMP.body"

echo "Merged $HEAD_LINES lines of newhead into $ORG"
