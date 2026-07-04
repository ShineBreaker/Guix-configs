#!/bin/sh
# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>
# SPDX-License-Identifier: MIT
#
# claude-code-print.sh — 解析 claude-code 的 stream-json 格式
# claude-code --output-format stream-json 输出为多行 JSON
# 每行是一个事件对象，最终文本在 type=result 的 result 字段中

_ccp_file="$1"

if [ ! -f "$_ccp_file" ]; then
    echo "" >&2
    exit 1
fi

# 优先找 type=result 的行，提取 result 字段
_result="$(awk '
    /"type"[[:space:]]*:[[:space:]]*"result"/ {
        line = $0
        n = split(line, parts, "\"result\"")
        for (i = 2; i <= n; i++) {
            if (parts[i] ~ /^":[[:space:]]*"/) {
                gsub(/^":[[:space:]]*"/, "", parts[i])
                gsub(/"[[:space:]]*\}.*$/, "", parts[i])
                print parts[i]
                exit
            }
        }
    }
' "$_ccp_file")"

if [ -n "$_result" ]; then
    printf '%s' "$_result"
else
    # fallback：提取所有 text content 块拼接
    awk '
        /"type"[[:space:]]*:[[:space:]]*"content_block_delta"/ && /"text"/ {
            gsub(/.*"text"[[:space:]]*:[[:space:]]*"/, "")
            gsub(/".*$/, "")
            printf "%s", $0
        }
    ' "$_ccp_file"
    echo ""
fi
