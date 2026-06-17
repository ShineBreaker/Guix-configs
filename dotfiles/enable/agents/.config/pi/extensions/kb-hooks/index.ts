// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
// SPDX-License-Identifier: MIT

/**
 * kb-hooks extension
 *
 * 知识库集成钩子：
 * - session_start: 注入 KB 健康度摘要
 * - agent_end:     检测"任务完成信号"，命中时注入 self-improving 评估提示
 * - /kb-summarize: 触发 self-improving 经验总结（自动切到 quick 模型，完成后恢复）
 * - /curate:       启动嵌套 agent 跑知识库策展
 * - /kb-health:    显示健康度报告
 *
 * 信号清单、写入流程、卡片格式由 self-improving / knowledge-base skill 提供，
 * 本插件只做"事件触发 + 命令快捷入口"，避免与 skill 重复维护。
 *
 * quick 模型：每次触发时从 settings.json 读取 `atelier.tiers.quick.model`，
 * 不在源码内硬编码——用户在 settings.json 改 quick tier 后无需重新发布插件。
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const KB_SCRIPT = join(homedir(), ".local", "bin", "kb");
const KB_AGENT = join(homedir(), ".local", "bin", "kb-agent");
const KB_SETTINGS_PATH =
  process.env.PI_SETTINGS_PATH ||
  join(homedir(), ".config", "pi", "settings.json");

/**
 * 任务完成信号（取自 self-improving skill references/triggers.md）
 * 收紧到强完成词，避免"好了"等高频词误触发。
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

/** 注入到下一轮的 self-improving 评估提示 */
const SUMMARIZE_PROMPT = [
  "<kb-hook>检测到任务完成信号,请按 self-improving skill 流程评估本次对话：",
  "(注意：这有可能是误报，如果当前任务没有完成的话，请忽略)",
  "1. 是否有可记录的经验信号（bug/踩坑/更优方案/用户纠正/项目决策）？",
  "2. 如有 → 调用 /kb-summarize 写入知识库（kb add / kb memory / kb connect）",
  "3. 如无 → 明确回复'本次无可记录经验'</kb-hook>",
].join("\n");

/** SUMMARIZE_PROMPT 的稳定标记，用于在 agent_end 中识别本轮是否在处理总结任务 */
const SUMMARIZE_MARKER = "<kb-hook>";

/** 防抖：同一信号在冷却期内不重复触发 */
const DEBOUNCE_MS = 5 * 60 * 1000; // 5 分钟
let lastTriggerTime = 0;

/** 标记：当前是否在 SUMMARIZE_PROMPT 处理轮中，用于 agent_end 时识别并恢复模型 */
let summarizeRoundActive = false;
let originalModelForSummarize: any = undefined;

/**
 * 从 settings.json 读取 `atelier.tiers.quick.model`，拆为 { provider, id }。
 * 任何环节失败（文件不存在、JSON 损坏、字段缺失、格式非 "provider/id"）都返回 undefined，
 * 调用方需降级处理。不缓存——/kb-summarize 是低频命令，解析开销可忽略，
 * 且 maak home 后 settings.json 内容可能变化。
 */
function readQuickModel(): { provider: string; id: string } | undefined {
  try {
    const raw = readFileSync(KB_SETTINGS_PATH, "utf-8");
    const settings = JSON.parse(raw);
    const modelStr: unknown = settings?.atelier?.tiers?.quick?.model;
    if (typeof modelStr !== "string") return undefined;
    const slash = modelStr.indexOf("/");
    if (slash < 1 || slash === modelStr.length - 1) return undefined;
    return {
      provider: modelStr.slice(0, slash),
      id: modelStr.slice(slash + 1),
    };
  } catch {
    return undefined;
  }
}

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

/** 获取简短的 KB 状态摘要（session_start 注入用） */
function getKbStatusSummary(): string {
  const health = runKb("health");
  if (health.startsWith("(kb")) return ""; // 命令失败，静默

  const lines = health.split("\n");
  const summary: string[] = ["[KB] 知识库状态:"];

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
  // ── session_start: 注入 KB 状态 ──
  pi.on("session_start", async (_event, _ctx) => {
    const summary = getKbStatusSummary();
    if (summary) {
      console.log(summary);
    }
  });

  // ── agent_end: 检测完成信号 + 恢复 summarize 模式前的原模型 ──
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
        "[KB] 任务完成信号已检测，建议运行 /kb-summarize 总结经验",
        "info",
      );
    }

    // ── 恢复 summarize 轮切换前的原模型 ──
    // 仅当本轮最后一条 user 消息是 SUMMARIZE_PROMPT 时触发，避免误恢复
    if (summarizeRoundActive && originalModelForSummarize) {
      const lastUserText = messages
        .filter((m: any) => m.role === "user")
        .map((m: any) => extractText(m.content))
        .join(" ");
      if (lastUserText.includes(SUMMARIZE_MARKER)) {
        const saved = originalModelForSummarize;
        summarizeRoundActive = false;
        originalModelForSummarize = undefined;
        const ok = await pi.setModel(saved);
        ctx.ui.notify(
          ok
            ? "[KB] 已恢复原模型"
            : "[KB] 恢复原模型失败（可能无 API key，当前模型保持不变）",
          ok ? "info" : "warning",
        );
      }
    }
  });

  // ── /kb-summarize 命令 ──
  // 不开新会话——直接注入到当前会话让 agent（有完整上下文）做总结
  pi.registerCommand("kb-summarize", {
    description: "在当前会话中触发 self-improving 经验总结",
    handler: async (_args, ctx) => {
      // 切换到 quick 模型加速总结（agent_end 会在 SUMMARIZE_PROMPT 处理完后恢复）
      const quickConfig = readQuickModel();
      if (!quickConfig) {
        ctx.ui.notify(
          `[KB] 无法从 settings.json 读取 atelier.tiers.quick.model，使用当前模型总结`,
          "warning",
        );
      } else {
        const quickModel = ctx.modelRegistry.find(
          quickConfig.provider,
          quickConfig.id,
        );
        if (quickModel && ctx.model) {
          const ok = await pi.setModel(quickModel);
          if (ok) {
            originalModelForSummarize = ctx.model;
            summarizeRoundActive = true;
            ctx.ui.notify(
              `[KB] 切换到 quick 模型 (${quickConfig.provider}/${quickConfig.id})，总结完成后恢复原模型`,
              "info",
            );
          } else {
            ctx.ui.notify(
              `[KB] quick 模型无 API key，使用当前模型总结`,
              "warning",
            );
          }
        } else {
          ctx.ui.notify(
            `[KB] 未找到 quick 模型 (${quickConfig.provider}/${quickConfig.id})，使用当前模型总结`,
            "warning",
          );
        }
      }

      ctx.ui.notify("[KB] 触发经验总结，请在下一轮对话中查看结果", "info");
      pi.sendUserMessage(SUMMARIZE_PROMPT, {
        deliverAs: "followUp",
      });
    },
  });

  // ── /curate 命令 ──
  pi.registerCommand("curate", {
    description: "执行知识库策展（健康检查 + 去重 + 归档）",
    handler: async (_args, ctx) => {
      ctx.ui.notify("[KB] 开始策展...", "info");

      const result = runKbAgent("curate", "pi");

      ctx.ui.notify("[KB] 策展完成", "info");
      console.log("=== 策展结果 ===");
      console.log(result);
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
