#!/bin/sh
# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>
# SPDX-License-Identifier: MIT
#
# jsonl-last-assistant.sh — 解析 JSONL，取最后一条 type=assistant 消息的 text content
# 适用：pi、codex、opencode 等 JSONL 输出
# 不依赖 jq，用 awk + sed 解析

_jla_file="$1"

if [ ! -f "$_jla_file" ]; then
    echo "" >&2
    exit 1
fi

# 从后往前找最后一条含 "assistant" 的行，提取 text content
# JSONL 格式通常是 {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
# 简化处理：取最后一条 assistant 行的第一个 text 字段
awk '
    /"assistant"/ { last_line = $0 }
    END {
        if (last_line == "") { exit 1 }
        # 提取第一个 "text":"..." 内容
        n = split(last_line, parts, "\"text\"")
        for (i = 2; i <= n; i++) {
            # 跳过 "type":"text" 这种
            if (parts[i] ~ /^":"[^{]/ || parts[i] ~ /^":[[:space:]]*"/) {
                gsub(/^":[[:space:]]*"/, "", parts[i])
                gsub(/"[[:space:]]*[,}].*$/, "", parts[i])
                print parts[i]
                exit
            }
        }
    }
' "$_jla_file"
