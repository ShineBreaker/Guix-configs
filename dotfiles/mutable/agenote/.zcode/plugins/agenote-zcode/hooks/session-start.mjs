#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

// agenote-zcode SessionStart hook
//
// 对应 pi 侧 agenote-hooks 的 session_start：向会话注入 agenote 使用规则
// （含 AGENOTE_AGENT=zcode 归因前缀要求）与记事本健康度摘要。
// 信号清单、写入流程、卡片格式由 agenote-{base,curator,review} skill 提供，
// 本 hook 只做"规则常驻提醒"，避免与 skill 重复维护。
//
// 手动冒烟测试：
//   printf '%s\n' '{"hook_event_name":"SessionStart","session_id":"manual","source":"startup"}' \
//     | node hooks/session-start.mjs

import { spawnSync } from "node:child_process";

let raw = "";
process.stdin.setEncoding("utf8");
for await (const chunk of process.stdin) raw += chunk;

let input = {};
try {
  input = raw.trim() ? JSON.parse(raw) : {};
} catch (err) {
  process.stderr.write(`[agenote-zcode] invalid SessionStart stdin: ${err}\n`);
  process.exit(1);
}

const eventName = input.hook_event_name || input.hookEventName || "SessionStart";

// 健康度摘要：只保留关键行（对齐 pi getAgenoteStatusSummary 的筛选规则）。
// 命令失败时静默——hook 不应因记事本缺失而阻塞会话启动。
function healthSummary() {
  let out;
  try {
    out = spawnSync("agenote", ["health"], {
      encoding: "utf-8",
      timeout: 4000,
    }).stdout;
  } catch {
    return "";
  }
  if (!out) return "";
  const keep = out
    .split("\n")
    .map((l) => l.trim())
    .filter(
      (l) =>
        l.startsWith("总卡片:") ||
        l.startsWith("孤立率:") ||
        l.startsWith("过时率:") ||
        l.startsWith("stale") ||
        l.includes("⚠️") ||
        l.includes("❌"),
    );
  return keep.length ? "\n" + keep.map((l) => `[agenote] ${l}`).join("\n") : "";
}

const rules = [
  "[agenote] 记事本已接入（跨 agent 共享知识库，详见 agenote-base skill）。规则：",
  "• 所有 agenote CLI 调用必须加前缀 AGENOTE_AGENT=zcode（如 AGENOTE_AGENT=zcode agenote search ...），否则卡片归因会错误落到 pi",
  "• 非平凡任务开始前先 agenote search 查已有经验；查到的资料用后 agenote touch 留痕",
  "• 踩坑/被纠正/找到更优方案时按 agenote-base skill 记录（agenote add / agenote memory --add）",
].join("\n");

const context = rules + healthSummary();

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: eventName,
      additionalContext: context,
    },
  }),
);
