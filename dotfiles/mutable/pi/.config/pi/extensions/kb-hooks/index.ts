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
 * - agent_end: 检测经验信号，提醒审查
 * - turn_end: 轮次计数，定期提醒策展
 * - /curate 命令: 执行知识库策展
 * - /kb-review 命令: 对话后经验审查（健康度 + 信号检测清单）
 */

const KB_SCRIPT = join(homedir(), ".local", "bin", "kb");
const KB_AGENT = join(homedir(), ".local", "bin", "kb-agent");
const REVIEW_INTERVAL = 10; // 每 10 轮提醒

/** 经验信号关键词 */
const EXPERIENCE_SIGNALS = [
  "错误",
  "error",
  "bug",
  "失败",
  "踩坑",
  "解决",
  "修复",
  "配置",
  "config",
  "发现",
  "注意",
  "重要",
  "总结",
  "可以用了",
  "Done",
  "完成",
];

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

/** 从 message.content 提取文本 */
function extractText(content: unknown): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .filter(
        (p): p is { type: "text"; text: string } =>
          p &&
          typeof p === "object" &&
          "type" in p &&
          (p as any).type === "text",
      )
      .map((p) => p.text)
      .join(" ");
  }
  return "";
}

export default function init(pi: ExtensionAPI): void {
  // ── session_start: 注入 KB 状态 ──
  pi.on("session_start", async (_event, _ctx) => {
    const summary = getKbStatusSummary();
    if (summary) {
      console.log(summary);
    }
  });

  // ── agent_end: 检测经验信号 ──
  pi.on("agent_end", async (event, ctx) => {
    const messages = (event as any).messages || [];
    // 提取用户消息文本
    const userTexts = messages
      .filter((m: any) => m.role === "user")
      .map((m: any) => extractText(m.content))
      .join(" ")
      .toLowerCase();

    if (!userTexts) return;

    const hasSignals = EXPERIENCE_SIGNALS.some((s) =>
      userTexts.includes(s.toLowerCase()),
    );

    if (hasSignals) {
      ctx.ui.notify(
        "[KB] 检测到可能的经验信号，可运行 /kb-review 记录经验",
        "info",
      );
    }
  });

  // ── turn_end: 轮次计数提醒 ──
  pi.on("turn_end", async (_event, ctx) => {
    turnCount++;
    if (turnCount >= REVIEW_INTERVAL) {
      turnCount = 0;
      ctx.ui.notify(
        `[KB] ${REVIEW_INTERVAL} 轮对话完成，可运行 /curate 审查知识库`,
        "info",
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
    description: "对话后经验审查（健康度 + 信号检测清单）",
    handler: async (_args, ctx) => {
      ctx.ui.notify("[KB] 经验审查中...", "info");

      // 健康度报告
      const health = runKb("health");
      console.log("=== 知识库健康度 ===");
      console.log(health);

      // 经验信号检测清单
      console.log("");
      console.log("=== 经验信号检测清单 ===");
      console.log("请检查本次对话是否包含以下信号：");
      console.log("  □ 修复了 bug 或解决了技术问题 → kb add --type debug");
      console.log("  □ 配置了新工具或调整了配置 → kb add --type config");
      console.log("  □ 重构了代码或优化了结构 → kb add --type refactor");
      console.log("  □ 发现了用户偏好或习惯 → kb memory --add --type feedback");
      console.log("  □ 做了架构决策 → kb add --type feature");
      console.log("  □ 做了简化或发现了更优方案 → kb add");
      console.log("");
      console.log("如无可记录经验，可忽略此审查。");
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
