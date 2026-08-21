#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

// agenote-zcode UserPromptSubmit hook — 任务完成信号检测
//
// 对应 pi 侧 agenote-hooks 的 agent_end 检测逻辑。差异：
// - zcode 的 matcher 已在 hooks.json 层对 prompt 做正则粗筛（命中才起本进程），
//   本脚本再做一次精确匹配 + 防抖，双层过滤。
// - zcode 无 agent_end / 空闲兜底挂点，v1 不做夜间兜底。
//
// 完成信号清单的单一真相源是 agenote-review skill 的 references/triggers.md
// （"任务完成信号"节）。改动信号时需同步本文件 COMPLETION_SIGNALS 与
// hooks.json 的 UserPromptSubmit matcher 正则。
//
// 手动冒烟测试：
//   printf '%s\n' '{"hook_event_name":"UserPromptSubmit","session_id":"manual","prompt":"搞定了"}' \
//     | node hooks/prompt-submit.mjs

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

/** 显式完成信号（与 pi COMPLETION_SIGNALS 同源：triggers.md 单一真相源） */
const COMPLETION_SIGNALS = [
  "可以用了",
  "一切正常",
  "都没问题",
  "都正常",
  "搞定",
  "完成",
  "做完了",
  "测试通过",
  "就这些",
  "先这样",
  "暂时够了",
  "就这样",
  "没了",
  "done.",
  "done!",
  "looks good",
  "ship it",
];

/** 防抖冷却期：同一冷却期内不重复注入评估提示 */
const DEBOUNCE_MS = 5 * 60 * 1000;

/** 本 hook 注入的评估提示标识符——含此标记的 prompt 是自注入回声，跳过检测 */
const HOOK_MARKER = "<agenote-hook>";

// 长驻状态目录：优先用 zcode 注入的插件数据目录，缺失时退到 XDG state。
// （zcode 对插件 hook 注入数据目录 env；变量名以实际运行为准，stderr 留痕便于校准。）
const DATA_DIR =
  process.env.ZCODE_PLUGIN_DATA ||
  process.env.CLAUDE_PLUGIN_DATA ||
  join(homedir(), ".local", "state", "agenote-zcode");

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

process.stderr.write(
  `[agenote-zcode] dataDir=${DATA_DIR} (ZCODE_PLUGIN_DATA=${process.env.ZCODE_PLUGIN_DATA ? "set" : "unset"})\n`,
);

// prompt 字段名防御式解析（claude-code 兼容协议为 prompt）
const prompt =
  input.prompt ?? input.user_prompt ?? input.userPrompt ?? "";
if (!prompt || prompt.includes(HOOK_MARKER)) process.exit(0);

// 精确匹配（matcher 粗筛已过，这里再确认一次，两处信号集保持同步）
const lower = String(prompt).toLowerCase();
if (!COMPLETION_SIGNALS.some((s) => lower.includes(s.toLowerCase()))) {
  process.exit(0);
}

// 防抖：冷却期内不重复触发（读失败按无状态处理；写失败宁可重复也不漏报）
const stampFile = join(DATA_DIR, "last-review-trigger");
let last = 0;
try {
  last = Number(readFileSync(stampFile, "utf-8").trim()) || 0;
} catch {
  // 首次运行尚无状态文件
}
if (Date.now() - last < DEBOUNCE_MS) process.exit(0);
try {
  mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(stampFile, String(Date.now()));
} catch (err) {
  process.stderr.write(`[agenote-zcode] debounce state write failed: ${err}\n`);
}

const reviewPrompt = [
  `${HOOK_MARKER}检测到任务完成信号，请按 agenote-review skill 流程评估本次对话：`,
  "（注意：这有可能是误报，如果当前任务没有完成的话，请忽略）",
  "1. 是否有可记录的经验信号（bug/踩坑/更优方案/用户纠正/项目决策）？",
  "2. 如有 → 通过 agenote CLI 写入（AGENOTE_AGENT=zcode agenote add / agenote memory --add）",
  "3. 本轮用到的资料留痕：已有卡片 AGENOTE_AGENT=zcode agenote touch，联网新知识 agenote add --type note",
  `4. 如无 → 明确回复"本次无可记录经验"</agenote-hook>`,
].join("\n");

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: reviewPrompt,
    },
  }),
);
