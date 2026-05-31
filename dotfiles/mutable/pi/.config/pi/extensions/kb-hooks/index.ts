// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

/**
 * kb-hooks extension
 *
 * 知识库集成钩子：
 * - session_start: 注入 KB 状态摘要（stale 卡片警告）
 * - turn_end: 轮次计数，定期提醒策展
 * - /curate 命令: 执行知识库策展
 * - /kb-review 命令: 对话后经验审查
 */

const KB_SCRIPT = join(homedir(), ".local", "bin", "kb");
const KB_AGENT = join(homedir(), ".local", "bin", "kb-agent");
const REVIEW_INTERVAL = 10; // 每 10 轮提醒

let turnCount = 0;

/** 运行 kb 命令并返回 stdout */
function runKb(...args: string[]): string {
  try {
    return execSync(`python3 "${KB_SCRIPT}" ${args.join(" ")}`, {
      encoding: "utf-8",
      timeout: 30000,
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch (err: any) {
    return `(kb 命令失败: ${err.message?.split("\n")[0] || err})`;
  }
}

/** 运行 kb-agent 命令 */
function runKbAgent(action: string, backend = "direct"): string {
  try {
    return execSync(`bash "${KB_AGENT}" ${action} --backend ${backend}`, {
      encoding: "utf-8",
      timeout: 120000,
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch (err: any) {
    return `(kb-agent 命令失败: ${err.message?.split("\n")[0] || err})`;
  }
}

/** 获取简短的 KB 状态摘要 */
function getKbStatusSummary(): string {
  const health = runKb("health");
  if (health.startsWith("(kb")) return ""; // 命令失败，静默

  const lines = health.split("\n");
  const summary: string[] = ["[KB] 知识库状态:"];

  // 提取关键行
  for (const line of lines) {
    const trimmed = line.trim();
    if (
      trimmed.startsWith("总卡片:") ||
      trimmed.startsWith("孤立率:") ||
      trimmed.startsWith("过时率:") ||
      trimmed.startsWith("stale") ||
      trimmed.includes("⚠️") ||
      trimmed.includes("❌")
    ) {
      summary.push(`  ${trimmed}`);
    }
  }

  return summary.join("\n");
}

export default function init(pi: ExtensionAPI): void {
  // ── session_start: 注入 KB 状态 ──
  pi.on("session_start", async (_event, _ctx) => {
    const summary = getKbStatusSummary();
    if (summary) {
      console.log(summary);
    }
  });

  // ── turn_end: 轮次计数提醒 ──
  pi.on("turn_end", async (_event, ctx) => {
    turnCount++;
    if (turnCount >= REVIEW_INTERVAL) {
      turnCount = 0;
      ctx.ui.notify(
        `[KB] ${REVIEW_INTERVAL} 轮对话完成，可运行 /curate 审查知识库`,
        "info"
      );
    }
  });

  // ── /curate 命令 ──
  pi.registerCommand("curate", {
    description: "执行知识库策展（健康检查 + 去重 + 归档）",
    handler: async (_args, ctx) => {
      ctx.ui.notify("[KB] 开始策展...", "info");

      const result = runKbAgent("curate");

      ctx.ui.notify("[KB] 策展完成", "info");
      console.log("=== 策展结果 ===");
      console.log(result);
    },
  });

  // ── /kb-review 命令 ──
  pi.registerCommand("kb-review", {
    description: "对话后经验审查",
    handler: async (_args, ctx) => {
      ctx.ui.notify("[KB] 经验审查中...", "info");

      const health = runKb("health");
      console.log("=== 知识库健康度 ===");
      console.log(health);
      console.log();
      console.log("请检查本次对话是否有可记录的经验，如有请运行 kb add 或 kb memory --add");
    },
  });

  // ── /kb-health 命令 ──
  pi.registerCommand("kb-health", {
    description: "显示知识库健康度报告",
    handler: async (_args, _ctx) => {
      const health = runKb("health");
      console.log(health);
    },
  });
}
