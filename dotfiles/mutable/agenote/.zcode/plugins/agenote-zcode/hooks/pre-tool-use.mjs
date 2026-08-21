#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

// agenote-zcode PreToolUse(Bash) hook — 归因前缀提醒
//
// zcode hook 不支持改写命令，只能通过 additionalContext 提醒：
// agenote CLI 调用缺 AGENOTE_AGENT= 前缀时提醒补上（归因必需；
// 与 SessionStart 注入的常驻规则形成双保险，防长会话遗忘）。
//
// 手动冒烟测试：
//   printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"agenote search 测试"}}' \
//     | node hooks/pre-tool-use.mjs

let raw = "";
process.stdin.setEncoding("utf8");
for await (const chunk of process.stdin) raw += chunk;

let input = {};
try {
  input = raw.trim() ? JSON.parse(raw) : {};
} catch (err) {
  process.stderr.write(`[agenote-zcode] invalid PreToolUse stdin: ${err}\n`);
  process.exit(1);
}

const eventName = input.hook_event_name || input.hookEventName || "PreToolUse";
const command = String(input.tool_input?.command ?? "");
if (!command) process.exit(0);

if (!/\bagenote\b/.test(command) || command.includes("AGENOTE_AGENT=")) {
  process.exit(0);
}

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: eventName,
      additionalContext:
        "💡 agenote CLI 调用请加 AGENOTE_AGENT=zcode 前缀（如 AGENOTE_AGENT=zcode agenote search ...），确保卡片归因正确",
    },
  }),
);
