#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

// assisted-by-zcode PreToolUse(Bash) hook — Assisted-by 规范提醒层
//
// zcode hook 不支持改写命令，只能通过 additionalContext 提醒：
// git commit 时提醒模型在消息末尾写完整 trailer（含模型名与版本号）。
// 兜底层是 ~/.config/git/hooks/prepare-commit-msg（见插件 README），
// 模型遗漏时自动补 agent 名。
//
// 手动冒烟测试：
//   printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}' \
//     | node hooks/pre-tool-use.mjs

let raw = "";
process.stdin.setEncoding("utf8");
for await (const chunk of process.stdin) raw += chunk;

let input = {};
try {
  input = raw.trim() ? JSON.parse(raw) : {};
} catch (err) {
  process.stderr.write(`[assisted-by-zcode] invalid PreToolUse stdin: ${err}\n`);
  process.exit(1);
}

const eventName = input.hook_event_name || input.hookEventName || "PreToolUse";
const command = String(input.tool_input?.command ?? "");
if (!command) process.exit(0);

if (!/\bgit\s+commit\b/.test(command)) process.exit(0);

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: eventName,
      additionalContext:
        "💡 commit message 需以 Assisted-by trailer 结尾：Assisted-by: <你的模型名>:<模型版本>，请在 -m 信息末尾附加；格式详见 ~/.config/git/gitmessage",
    },
  }),
);
