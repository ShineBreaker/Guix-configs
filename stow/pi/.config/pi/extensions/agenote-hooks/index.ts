// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
// SPDX-License-Identifier: MIT

/**
 * agenote-hooks extension
 *
 * agent 专属记事本（agenote）集成钩子：
 * - session_start: 注入 agenote 健康度摘要
 * - agent_end:     检测"任务完成信号"，命中时注入 agenote-review 评估提示（含留痕）
 * - /agenote-summarize: 在当前会话触发经验总结 + 留痕
 * - /agenote-curate:    执行 agenote 策展（健康+去重+归档+权重重分配）
 * - /agenote-health:    显示 agenote 健康度报告
 *
 * 信号清单、写入流程、卡片格式由 agenote-{base,curator,review} skill 提供，
 * 本插件只做"事件触发 + 命令快捷入口"，避免与 skill 重复维护。
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const KB_SCRIPT = join(homedir(), ".local", "bin", "kb");
const KB_AGENT = join(homedir(), ".local", "bin", "kb-agent");

/**
 * 任务完成信号（取自 agenote-review skill references/triggers.md — 单一真相源）
 * 收紧到强完成词，避免"好了"等高频词误触发。
 * 改动此处需同步 agenote-review/references/triggers.md。
 */
const COMPLETION_SIGNALS = [
  // 中文显式完成
  "可以用了",
  "一切正常",
  "都没问题",
  "都正常",
  "搞定",
  "完成",
  "做完了",
  "测试通过",
  "通过",
  "就这些",
  "先这样",
  "暂时够了",
  "就这样",
  "没了",
  // 英文显式完成
  "done.",
  "done!",
  "looks good",
  "ship it",
];

/** 注入到下一轮的 agenote-review 评估提示（含留痕环节） */
const SUMMARIZE_PROMPT = [
  "<agenote-hook>检测到任务完成信号，请按 agenote-review skill 流程评估本次对话：",
  "（注意：这有可能是误报，如果当前任务没有完成的话，请忽略）",
  "1. 是否有可记录的经验信号（bug/踩坑/更优方案/用户纠正/项目决策）？",
  "2. 如有 → 调用 /agenote-summarize 写入（kb agenote add / kb agenote memory / kb agenote connect）",
  "3. 本轮用到的资料留痕：已有卡片 kb agenote touch <id>，联网新知识 kb agenote add --type note",
  "4. 如无 → 明确回复'本次无可记录经验'</agenote-hook>",
].join("\n");

/** 防抖：同一信号在冷却期内不重复触发 */
const DEBOUNCE_MS = 5 * 60 * 1000; // 5 分钟
let lastTriggerTime = 0;

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

/**
 * 运行 kb-agent 命令
 * 备注：direct backend 只支持 health/deduplicate/archive/reindex 关键词匹配，
 * 跑 curate / review 必须用 pi / opencode / crush backend 启动嵌套 agent。
 */
function runKbAgent(action: string, backend = "pi"): string {
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

/** 获取简短的 agenote 状态摘要（session_start 注入用） */
function getAgenoteStatusSummary(): string {
  const health = runKb("agenote", "health");
  if (health.startsWith("(kb")) return ""; // 命令失败，静默

  const lines = health.split("\n");
  const summary: string[] = ["[agenote] 记事本状态:"];

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
        (
          p,
        ): p is {
          type: "text";
          text: string;
        } =>
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
  // ── session_start: 注入 agenote 状态 ──
  pi.on("session_start", async (_event, _ctx) => {
    const summary = getAgenoteStatusSummary();
    if (summary) {
      console.log(summary);
    }
  });

  // ── agent_end: 检测完成信号，提示 agent 进入总结流程 ──
  pi.on("agent_end", async (event, ctx) => {
    // 防抖：冷却期内跳过
    const now = Date.now();
    if (now - lastTriggerTime < DEBOUNCE_MS) return;

    const messages = (event as any).messages || [];
    const userTexts = messages
      .filter((m: any) => m.role === "user")
      .map((m: any) => extractText(m.content))
      .join(" ")
      .toLowerCase();

    if (!userTexts) return;

    const hasCompletion = COMPLETION_SIGNALS.some((s) =>
      userTexts.includes(s.toLowerCase()),
    );

    if (hasCompletion) {
      lastTriggerTime = now;
      // deliverAs: followUp — 若 agent 仍在 streaming 则安全排队，idle 时立即交付
      pi.sendUserMessage(SUMMARIZE_PROMPT, {
        deliverAs: "followUp",
      });
      ctx.ui.notify(
        "[agenote] 任务完成信号已检测，建议运行 /agenote-summarize 总结经验",
        "info",
      );
    }
  });

  // ── /agenote-summarize 命令 ──（原 /kb-summarize）
  // 不开新会话——直接注入到当前会话让 agent（有完整上下文）做总结
  pi.registerCommand("agenote-summarize", {
    description: "在当前会话中触发 agenote 经验总结 + 留痕",
    handler: async (_args, ctx) => {
      ctx.ui.notify("[agenote] 触发经验总结，请在下一轮对话中查看结果", "info");
      pi.sendUserMessage(SUMMARIZE_PROMPT, {
        deliverAs: "followUp",
      });
    },
  });

  // ── /agenote-curate 命令 ──（原 /curate）
  pi.registerCommand("agenote-curate", {
    description: "执行 agenote 策展（健康 + 去重 + 归档 + 权重重分配）",
    handler: async (_args, ctx) => {
      ctx.ui.notify("[agenote] 开始策展...", "info");

      const result = runKbAgent("curate", "pi");

      ctx.ui.notify("[agenote] 策展完成", "info");
      console.log("=== 策展结果 ===");
      console.log(result);
    },
  });

  // ── /agenote-health 命令 ──（原 /kb-health）
  pi.registerCommand("agenote-health", {
    description: "显示 agenote 健康度报告",
    handler: async (_args, _ctx) => {
      const health = runKb("agenote", "health");
      console.log(health);
    },
  });
}
