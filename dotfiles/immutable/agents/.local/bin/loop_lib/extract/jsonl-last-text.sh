#!/bin/sh
# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>
# SPDX-License-Identifier: MIT
#
# jsonl-last-text.sh — 取 JSONL 最后一行的完整 text 字段
# 适用：crush 等输出格式为 {"text":"..."} 的 JSONL

_jlt_file="$1"

if [ ! -f "$_jlt_file" ]; then
    echo "" >&2
    exit 1
fi

# 取最后一行，提取 "text" 字段值
tail -1 "$_jlt_file" | awk '{
    # 找到 "text":"... 并提取值
    n = split($0, parts, "\"text\"")
    for (i = 2; i <= n; i++) {
        if (parts[i] ~ /^":[[:space:]]*"/) {
            gsub(/^":[[:space:]]*"/, "", parts[i])
            gsub(/"[[:space:]]*[,}].*$/, "", parts[i])
            print parts[i]
            exit
        }
    }
}'
