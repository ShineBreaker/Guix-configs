// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
// SPDX-License-Identifier: MIT

/**
 * kb-hooks extension
 *
 * 知识库集成钩子：
 * - session_start:        注入 KB 健康度摘要
 * - before_agent_start:   注入当前项目 memory（memories/projects/<name>.org）
 * - agent_end:            检测"任务完成信号"，命中时注入 self-improving 评估提示
 * - /kb-summarize:        触发 self-improving 经验总结（自动切到 quick 模型，完成后恢复）
 * - /curate:              启动嵌套 agent 跑知识库策展
 * - /kb-health:           显示健康度报告
 *
 * 信号清单、写入流程、卡片格式由 self-improving / knowledge-base skill 提供，
 * 本插件只做"事件触发 + 命令快捷入口"，避免与 skill 重复维护。
 *
 * quick 模型：每次触发时从 settings.json 读取 `atelier.tiers.quick.model`，
 * 不在源码内硬编码——用户在 settings.json 改 quick tier 后无需重新发布插件。
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

const KB_SCRIPT = join(homedir(), ".local", "bin", "kb");
const KB_AGENT = join(homedir(), ".local", "bin", "kb-agent");
const KB_SETTINGS_PATH =
  process.env.PI_SETTINGS_PATH ||
  join(homedir(), ".config", "pi", "settings.json");

// 知识库根目录：与 kb 工具共享（KB_ROOT 环境变量可覆盖，默认 ~/Documents/Org）
const KB_ROOT = process.env.KB_ROOT || join(homedir(), "Documents", "Org");
const KB_MEMORY_FILE = join(KB_ROOT, "MEMORY.org");
const KB_PROJECTS_DIR = join(KB_ROOT, "memories", "projects");

/** 项目 memory 文件最大读取字节（防巨型文件爆 context） */
const PROJECT_MEMORY_MAX_BYTES = 65536;

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

/** MEMORY.org 解析出的项目条目 */
interface ProjectEntry {
  name: string;
  /** 原始 PATH 字符串（来自 MEMORY.org 的 :PATH: 属性） */
  pathRaw: string;
  /** 解析后的 FILE 路径（来自 :FILE: 属性） */
  filePath: string;
}

/**
 * 解析 MEMORY.org 的 `* project` 节，提取所有 `** <name>` 条目的 :PATH: 和 :FILE:。
 * 解析失败返回空数组。
 */
function parseProjectEntries(memoryText: string): ProjectEntry[] {
  const entries: ProjectEntry[] = [];
  // 找 * project 节的起止（节标题为顶级 `* xxx`）
  const lines = memoryText.split("\n");
  let inProject = false;
  let curEntry: string | null = null;
  let curProps: Record<string, string> = {};
  let inProps = false;

  for (const line of lines) {
    const topMatch = line.match(/^(\*)\s+\S/);
    if (topMatch) {
      // 顶级标题：先推入上一个 entry（避免节末尾的项目丢失），再切换节

      if (inProject && curEntry) entries.push(buildEntry(curEntry, curProps));

      inProject = /^\*\s+project\b/i.test(line);

      curEntry = null;

      curProps = {};

      inProps = false;

      continue;
    }

    if (!inProject) continue;

    const subMatch = line.match(/^\s*\*\*\s+(.+)/);
    if (subMatch) {
      if (curEntry) entries.push(buildEntry(curEntry, curProps));
      curEntry = subMatch[1].trim();
      curProps = {};
      inProps = false;
      continue;
    }

    if (curEntry) {
      if (/^\s*:PROPERTIES:\s*$/.test(line)) {
        inProps = true;
        continue;
      }
      if (/^\s*:END:\s*$/.test(line)) {
        inProps = false;
        continue;
      }
      if (inProps) {
        const pm = line.match(/^\s*:([A-Z_][A-Z0-9_]*):\s*(.+)/);
        if (pm) curProps[pm[1]] = pm[2].trim();
      }
    }
  }
  if (curEntry) entries.push(buildEntry(curEntry, curProps));
  return entries;
}

function buildEntry(name: string, props: Record<string, string>): ProjectEntry {
  return {
    name,
    pathRaw: props.PATH || "",
    filePath: props.FILE || "",
  };
}

/**

 * 找出 cwd 所在的项目。

 * 匹配规则：cwd == PATH 或 cwd 是 PATH 的严格子目录。

 * 多个项目匹配时选最深的（最具体的），避免祖先误匹配

 * （如 cwd=.emacs.d 时不该匹配其祖先 Guix-configs）。

 * 注：kb memory --project . 走双向前缀匹配，祖先路径也会被误匹配；

 * kb-hooks 用更严格的语义，因为 system prompt 注入对准确性要求高。

 */

function findProjectByCwd(
  cwd: string,

  entries: ProjectEntry[],
): ProjectEntry | undefined {
  let absCwd: string;

  try {
    absCwd = resolve(cwd);
  } catch {
    absCwd = cwd;
  }

  let best: ProjectEntry | undefined;

  let bestDepth = -1;

  for (const e of entries) {
    if (!e.pathRaw) continue;

    let absPath: string;

    try {
      absPath = resolve(e.pathRaw.replace(/^~/, homedir()));
    } catch {
      continue;
    }

    if (absCwd !== absPath && !absCwd.startsWith(absPath + "/")) continue;

    // 路径段越多越深：/a/b/c 深度 3 比 /a 深度 1 更具体

    const depth = absPath.split("/").length;

    if (depth > bestDepth) {
      best = e;

      bestDepth = depth;
    }
  }

  return best;
}

/**
 * 加载项目 memory 文件全文。带大小限制避免爆 context。
 * 返回 { content, truncated }；文件不存在/超过限制返回 undefined。
 */
function loadProjectMemory(
  entry: ProjectEntry,
): { content: string; truncated: boolean } | undefined {
  if (!entry.filePath) return undefined;
  const filePath = entry.filePath.startsWith("/")
    ? entry.filePath
    : join(KB_PROJECTS_DIR, "..", "..", entry.filePath);
  if (!existsSync(filePath)) return undefined;
  const stat = statSync(filePath);
  if (stat.size > PROJECT_MEMORY_MAX_BYTES) {
    const buf = readFileSync(filePath, "utf-8").slice(
      0,
      PROJECT_MEMORY_MAX_BYTES,
    );
    return { content: buf, truncated: true };
  }
  return { content: readFileSync(filePath, "utf-8"), truncated: false };
}

/** 构造注入到 system prompt 的项目 memory 段（空表示不注入） */
function buildProjectMemoryBlock(cwd: string): string {
  if (!existsSync(KB_MEMORY_FILE)) return "";
  let memoryText: string;
  try {
    memoryText = readFileSync(KB_MEMORY_FILE, "utf-8");
  } catch {
    return "";
  }
  const entries = parseProjectEntries(memoryText);
  const match = findProjectByCwd(cwd, entries);
  if (!match) return "";
  const loaded = loadProjectMemory(match);
  if (!loaded) return "";
  const note = loaded.truncated
    ? `\n\n> [kb-hooks] 注：原文 ${PROJECT_MEMORY_MAX_BYTES} 字节以上，已截断到 ${PROJECT_MEMORY_MAX_BYTES} 字节`
    : "";
  return (
    `<project_memory name="${match.name}" path="${match.pathRaw}">\n` +
    loaded.content +
    `${note}\n</project_memory>`
  );
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

  // ── before_agent_start: 注入当前项目 memory 到 system prompt ──
  pi.on("before_agent_start", async (event, ctx) => {
    const block = buildProjectMemoryBlock(ctx.cwd);
    if (!block) return;
    return {
      systemPrompt: event.systemPrompt + "\n\n" + block,
    };
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
