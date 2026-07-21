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
 *
 * 调用路径：agenote 已改造为 MCP server（agenote_mcp.py），agent 主循环通过
 * MCP tool 调用。但 pi 的 ExtensionAPI 不提供 MCP 调用接口，本插件的命令
 * （/agenote-health、/agenote-curate）改调轻量 CLI shim（agenote_cli.py），
 * 它复用同一套 ag_lib 内核，输出人类可读文本。
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const KB_SCRIPT = join(homedir(), ".local", "bin", "agenote_cli.py");
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
/** 注入到下一轮的 agenote-review 评估提示（含留痕环节）。reason 说明触发来源。 */
function buildReviewPrompt(reason: string): string {
  return [
    `<agenote-hook>${reason}，请按 agenote-review skill 流程评估本次对话：`,
    "（注意：这有可能是误报，如果当前任务没有完成的话，请忽略）",
    "1. 是否有可记录的经验信号（bug/踩坑/更优方案/用户纠正/项目决策）？",
    "2. 如有 → 通过 agenote MCP tool 写入（agenote_add / agenote_memory_add / 链接用 agenote_get 后手动关联）",
    "3. 本轮用到的资料留痕：已有卡片 agenote_touch，联网新知识 agenote_add（type=note）",
    "4. 如无 → 明确回复'本次无可记录经验'</agenote-hook>",
  ].join("\n");
}

/** 显式完成信号触发的防抖冷却期：同一信号在冷却期内不重复触发 */
const DEBOUNCE_MS = 5 * 60 * 1000; // 5 分钟
/** 空闲兜底：会话连续空闲超过此时长且本会话从未触发过总结 → 触发一次（覆盖夜间无人值守） */
const IDLE_FALLBACK_MS = 5 * 60 * 1000; // 5 分钟

let lastTriggerTime = 0;
/** 本会话是否已通过显式信号触发过总结（true 后禁用空闲兜底，避免重复打扰） */
let signalTriggered = false;
/** 本会话是否已触发过空闲兜底（至多一次） */
let idleFallbackFired = false;
/** 已处理的 agent_end 轮次计数（用于判断是否有真实工作） */
let turnCount = 0;
/** 空闲兜底定时器 */
let idleTimer: ReturnType<typeof setTimeout> | undefined;
/** 本扩展注入的 review 提示的标识符——用于排除自注入消息，断开自触发反馈环 */
const HOOK_MARKER = "<agenote-hook>";

/** 运行 agenote_cli 命令并返回 stdout
 *
 * agenote_cli.py 是轻量 CLI shim（纯 stdlib），复用 ag_lib 内核。
 * agent 主循环已改用 MCP tool 调用 agenote，但本插件（ExtensionAPI 无
 * MCP 调用接口）只能 execSync 外部进程，故走此 shim。
 */
function runKb(...args: string[]): string {
  try {
    return execSync(`python3 "${KB_SCRIPT}" ${args.join(" ")}`, {
      encoding: "utf-8",
      timeout: 30000,
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch (err: any) {
    return `(agenote_cli 命令失败: ${err.message?.split("\n")[0] || err})`;
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
  const health = runKb("health");
  if (health.startsWith("(agenote")) return ""; // 命令失败，静默

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

/**
 * 当前进程是否是 subagent 工具 spawn 出来的独立 pi 进程。
 *
 * subagent 工具为每次委派 spawn 一个 `pi --mode json -p --no-session ...` 子进程，
 * 它也会加载本扩展。如果不识别并跳过，它内部对话里的 "完成 / 搞定 / done" 等信号
 * 会污染 handoff 输出：
 *   1. hook 在 worker 进程的 agent_end 触发
 *   2. 把 review 提示（buildReviewPrompt）作为 followUp 注入到 worker 进程
 *   3. worker 进程下一轮开始执行经验总结评估
 *   4. 主 agent 收到的不是干净 handoff，而是混入"请评估是否记录经验"的内容
 *
 * `--no-session` 是 subagent 工具独有的标志（interactive 模式 / 普通 `pi -p`
 * 一次性命令都不会带），用它识别最稳。
 */
function isSubagentProcess(): boolean {
  return process.argv.includes("--no-session");
}

export default function init(pi: ExtensionAPI): void {
  // session_start：状态显示已交给 pi-ui 扩展（欢迎框中显示）。
  // 原逻辑在这里 console.log 会导致 stdout 在 TUI 之前打印多行文本，
  // 且与 pi-ui 欢迎框重复。pi-ui 已调用 kb agenote health 解析后
  // 在欢迎框中显示。需要独立查看请使用 /agenote-health 命令。

  // ── session_start：新会话彻底重置触发状态（修 bug：状态跨会话残留）──
  // 模块级状态（idleTimer / idleFallbackFired / turnCount 等）在 /new 切换会话时
  // 不随进程重启而清除——旧会话中断时那次 agent_end 武装的 5 分钟定时器会被
  // "串台"到新会话，导致新会话刚开、agent 正干活时旧定时器到点误触发。
  // 故每次新会话开始：清定时器 + 归零所有触发状态。
  pi.on("session_start", () => {
    if (isSubagentProcess()) return;
    if (idleTimer) clearTimeout(idleTimer);
    idleTimer = undefined;
    idleFallbackFired = false;
    signalTriggered = false;
    turnCount = 0;
    lastTriggerTime = 0;
  });

  // ── agent_start：新一轮 turn 开始 = 会话不再空闲，取消空闲定时器 ──
  // （修 bug：定时器只在 agent_end 武装，长输出 turn 期间从不取消，
  //  上一轮武装的定时器会在"正在流式输出"时到点误触发——截图所示现象。）
  // 语义：idle 计时只能从 agent_end（会话真正安静下来）起算；
  //  一旦 agent_start（新一轮开始），任何待发的 idle 定时器都作废。
  pi.on("agent_start", () => {
    if (isSubagentProcess()) return;
    if (idleTimer) {
      clearTimeout(idleTimer);
      idleTimer = undefined;
    }
  });

  // ── agent_end: 检测完成信号 + 空闲兜底，提示 agent 进入总结流程 ──
  pi.on("agent_end", async (event, ctx) => {
    // subagent 进程的内部对话不应触发本扩展——见 isSubagentProcess 注释。
    // 这是修复"hook 在 worker 进程触发，污染 handoff"问题的关键守卫。
    if (isSubagentProcess()) return;

    turnCount++;

    const messages = (event as any).messages || [];
    // 只看最近一条用户消息：完成信号应来自用户"刚说"的话，
    // 而非全会话历史的拼接（旧实现把历史拼成一坠，任何完成词说一次就永久上膛）。
    let lastUserText = "";
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i]?.role === "user") {
        lastUserText = extractText(messages[i].content);
        break;
      }
    }
    const lastLower = lastUserText.toLowerCase();

    // 排除本扩展自注入的 review 提示（含 HOOK_MARKER）——断开自触发反馈环。
    // 旧实现的 SUMMARIZE_PROMPT 自身含"完成"/"通过"，注入后下轮又匹配到自己，造成重复触发。
    const isSelfInjection = lastUserText.includes(HOOK_MARKER);

    // ── 显式完成信号触发 ──
    if (!isSelfInjection && lastLower) {
      const now = Date.now();
      const hasCompletion = COMPLETION_SIGNALS.some((s) =>
        lastLower.includes(s.toLowerCase()),
      );
      // 防抖：冷却期内不重复触发
      if (hasCompletion && now - lastTriggerTime >= DEBOUNCE_MS) {
        lastTriggerTime = now;
        signalTriggered = true;
        // deliverAs: followUp — 若 agent 仍在 streaming 则安全排队，idle 时立即交付
        pi.sendUserMessage(buildReviewPrompt("检测到任务完成信号"), {
          deliverAs: "followUp",
        });
        ctx.ui.notify(
          "[agenote] 任务完成信号已检测，建议运行 /agenote-summarize 总结经验",
          "info",
        );
      }
    }

    // ── 空闲兜底：会话连续空闲超过阈值且从未被信号触发 → 触发一次 ──
    // 覆盖夜间无人值守工作：用户 kick-off 后离开，agent 自主完成，无人说"完成"。
    // 仅当本会话从未被显式信号触发过时启用（signalTriggered 为 true 则永久禁用，避免与信号路径重复）。
    if (idleTimer) clearTimeout(idleTimer);
    idleTimer = setTimeout(() => {
      if (idleFallbackFired || signalTriggered) return;
      if (turnCount < 1) return; // 至少处理过一轮真实工作
      idleFallbackFired = true;
      lastTriggerTime = Date.now();
      // 定时器回调在 pi 事件流之外执行，session 状态可能已变，故守护异常。
      try {
        pi.sendUserMessage(
          buildReviewPrompt(
            "会话已空闲 5 分钟且未检测到显式完成信号——可能是一段工作（含夜间自动任务）已结束",
          ),
          { deliverAs: "followUp" },
        );
      } catch (err) {
        console.warn("[agenote] 空闲兜底注入失败:", err);
      }
      // 空闲兜底在定时器回调中执行，ctx 可能已失效，故不调 ctx.ui.notify。
    }, IDLE_FALLBACK_MS);
  });

  // ── /agenote-summarize 命令 ──（原 /kb-summarize）
  // 不开新会话——直接注入到当前会话让 agent（有完整上下文）做总结
  pi.registerCommand("agenote-summarize", {
    description: "在当前会话中触发 agenote 经验总结 + 留痕",
    handler: async (_args, ctx) => {
      ctx.ui.notify("[agenote] 触发经验总结，请在下一轮对话中查看结果", "info");
      pi.sendUserMessage(buildReviewPrompt("用户手动触发经验总结"), {
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
      const health = runKb("health");
      console.log(health);
    },
  });
}
