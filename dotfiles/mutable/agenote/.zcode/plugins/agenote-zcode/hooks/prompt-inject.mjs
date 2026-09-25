#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

// agenote-zcode UserPromptSubmit hook — 记忆召回注入（每轮，追加型三件套）
//
// 设计 C4：query = prompt 折叠空白取前 200 字符 + cwd basename 伪词，调
// `AGENOTE_AGENT=zcode agenote context --mode recall --budget 4000` 注入。
// 三件套（指纹+query 未变不重注 / 短 prompt 与分数下限滤空跳过 / 单会话
// 累计 24000 触顶停 recall）在 lib.mjs，状态文件
// ~/.cache/agenote/injectors/zcode-<session_id>.json。
//
// 与既有 prompt-submit.mjs（完成信号检测，带 matcher 粗筛）并存为
// hooks.json UserPromptSubmit 的两个条目：本条目无 matcher = 每轮触发，
// 两边输出互不干扰（zcode 会合并同事件多个 hook 的 additionalContext——
// 待实装验证项，见 injectors/zcode/README.md）。
// 含 <agenote-hook> 的 prompt 是自注入回声，整轮跳过（防注入循环）。
//
// 手动冒烟测试：
//   printf '%s\n' '{"hook_event_name":"UserPromptSubmit","session_id":"manual",
//     "cwd":"/path/to/project","prompt":"记忆注入的预算怎么分配"}' \
//     | node hooks/prompt-inject.mjs

import { recallTurn } from "./lib.mjs";

let raw = "";
process.stdin.setEncoding("utf8");
for await (const chunk of process.stdin) raw += chunk;

let input = {};
try {
  input = raw.trim() ? JSON.parse(raw) : {};
} catch (err) {
  process.stderr.write(`[agenote-zcode] invalid UserPromptSubmit stdin: ${err}\n`);
  process.exit(1);
}

// 字段名防御式解析（与 prompt-submit.mjs 同款；prompt 字段实际下发名待实装验证）
const sessionId = input.session_id ?? input.sessionId ?? "";
const cwd = input.cwd || process.cwd();
const prompt = input.prompt ?? input.user_prompt ?? input.userPrompt ?? "";

// 空 prompt（协议未实装该字段时）无事可做；回声防循环
if (!prompt || prompt.includes("<agenote-hook>")) process.exit(0);

const content = recallTurn(sessionId, cwd, prompt);
if (content) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: content,
      },
    }),
  );
}
process.exit(0);
