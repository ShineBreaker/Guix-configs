// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { readdir, readFile, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

// ─── 加载错误日志（omp 默认静默吞掉扩展错误，这里显式留痕）────────────────────
const LOG_FILE = join(
  homedir(),
  ".config",
  "omp",
  "extensions",
  ".load-errors.log",
);
function logLoadError(ext: string, where: string, err: unknown): void {
  const msg =
    err instanceof Error ? `${err.message}\n${err.stack ?? ""}` : String(err);
  appendFileSync(
    LOG_FILE,
    `[${new Date().toISOString()}] [${ext}] ${where}: ${msg}\n`,
  );
}

/**
 * 定位 omp 配置根（~/.config/omp）。
 *
 * omp 18 没有把配置路径 API 暴露给扩展运行时，这里按 omp 内部解析顺序定位：
 * PI_CONFIG_DIR 是「home 下相对目录名」（fish conf.d 设为 .config/omp），
 * 必须 resolve(homedir(), ...) 绝对化——直接 join 会相对 cwd 解析。
 * global-context.json / mcp.json / agent.db 等均直接位于配置根，
 * 不存在 agent/ 子目录层（旧注释假设 `<config root>/agent` 是错的，
 * 那曾导致 loadConfig 永远找不到配置、注入整体休眠）。
 */
function getOmpConfigDir(): string {
  return resolve(
    homedir(),
    process.env.PI_CONFIG_DIR || join(".config", "omp"),
  );
}

/**
 * global-context extension
 *
 * 使用 before_agent_start hook 将上下文文件注入系统提示词。
 * 注入文件列表由决策核 ~/.config/agents/context-select.sh 统一裁决
 * （--platform omp + 当前会话 cwd 门控），本扩展只做协议适配与预算控制，
 * 与 zcode / crush / hermes 端共享同一注入映射表。selector 缺失或执行
 * 失败时降级为扫描默认 context 目录全量注入（部署是渐进的，扩展可能
 * 先于 selector 的 blue home 上线）。
 *
 * 配置（<omp 配置根>/global-context.json，扩展自管——omp 的 ExtensionAPI
 * 不提供配置读取接口）：
 *   - enabled: boolean       — 显式启用/禁用（默认：有配置时启用）
 *   - separator: string      — 文件之间的分隔符（默认 \n\n）
 *   - maxFiles: number       — 最多注入文件数（默认 8）
 *   - maxBytesPerFile: number — 单文件最大读取字节（默认 65536）
 *   - maxTotalBytes: number  — 总注入字节预算（默认 196608）
 *
 * selector 路径可用环境变量 CONTEXT_SELECT_BIN 覆盖（默认
 * ~/.config/agents/context-select.sh，blue home 部署前调试用）。
 */

// ─── 决策核 selector（CONTEXT_SELECT_BIN 可覆盖，供部署前调试）───────────────
const SELECTOR_BIN =
  process.env.CONTEXT_SELECT_BIN ||
  join(homedir(), ".config", "agents", "context-select.sh");
// 降级扫描目录：selector 内置的默认 context 目录（$XDG_CONFIG_HOME/agents/context）
const DEFAULT_CONTEXT_DIR = resolve(
  process.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
  "agents",
  "context",
);

/**
 * 将 content blocks 数组转为可读文本
 */
function formatContentBlocks(blocks: any[]): string {
  return blocks
    .map((block: any) => {
      switch (block.type) {
        case "text":
          return block.text;
        case "image":
          return `[Image: ${block.mimeType}]`;
        case "thinking":
          return `<details><summary>Thinking</summary>\n\n${block.thinking}\n\n</details>`;
        case "toolCall":
          return `**Tool Call: ${block.name}**\n\`\`\`json\n${JSON.stringify(block.arguments, null, 2)}\n\`\`\``;
        default:
          return JSON.stringify(block);
      }
    })
    .join("\n\n");
}

/**
 * 格式化消息内容（string 或 content blocks 数组）
 */
function formatMessageContent(content: string | any[]): string {
  if (typeof content === "string") return content;
  return formatContentBlocks(content);
}

/**
 * 格式化单条 AgentMessage 为 [角色标签, 内容文本]
 */
function formatMessage(msg: any): { role: string; text: string } {
  switch (msg.role) {
    case "user":
      return { role: "User", text: formatMessageContent(msg.content) };
    case "assistant":
      return { role: "Assistant", text: formatMessageContent(msg.content) };
    case "toolResult":
      return {
        role: `Tool Result (${msg.toolName ?? "unknown"})`,
        text: formatMessageContent(msg.content),
      };
    case "custom":
      return {
        role: `[Custom: ${msg.customType ?? "unknown"}]`,
        text: formatMessageContent(msg.content),
      };
    case "compactionSummary":
      return { role: "Compaction Summary", text: msg.summary ?? "" };
    case "branchSummary":
      return { role: "Branch Summary", text: msg.summary ?? "" };
    case "bashExecution":
      return {
        role: "Bash Execution",
        text: `$ ${msg.command ?? ""}\n${msg.output ?? ""}`,
      };
    default:
      return {
        role: `Unknown (${String(msg.role)})`,
        text: JSON.stringify(msg),
      };
  }
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// ─── 配置类型 ────────────────────────────────────────────────────────────────

interface GlobalContextConfig {
  enabled?: boolean;
  separator?: string;
  maxFiles?: number;
  maxBytesPerFile?: number;
  maxTotalBytes?: number;
}

/**
 * 读取 global-context 自身配置
 *
 * omp 的 ExtensionAPI 不提供配置读取接口（无 pi.config / pi.getConfig），
 * 扩展需自管配置文件。本扩展读 <omp 配置根>/global-context.json
 * （getOmpConfigDir() 即配置根，无 agent/ 子目录层）。
 * 兼容旧 pi：若 config.yml 不存在，回退读 settings.json 的 globalContext 字段。
 */
function loadConfig(): GlobalContextConfig | undefined {
  const configRoot = getOmpConfigDir();
  const candidates = [
    join(configRoot, "global-context.json"), // omp：独立配置文件（推荐）
    join(configRoot, "settings.json"), // 旧 pi：settings.json 内嵌字段（向后兼容）
  ];

  for (const cfgPath of candidates) {
    if (!existsSync(cfgPath)) continue;
    try {
      const raw = JSON.parse(readFileSync(cfgPath, "utf8"));
      // 独立文件直接是配置对象；settings.json 内嵌在 globalContext 字段下
      const cfg = cfgPath.endsWith("global-context.json")
        ? raw
        : raw?.globalContext;
      return cfg as GlobalContextConfig | undefined;
    } catch {
      continue;
    }
  }
  return undefined;
}

/**
 * 调决策核 selector 获取本会话应注入的文件列表。
 *
 * 以参数数组传参（禁止字符串拼接 shell 命令——cwd 含空格/特殊字符会炸）。
 * 成败以 stdout 为契约（忽略 returncode）：仅 spawn 级失败（selector 缺失
 * 等）或 stdout 全空才降级目录扫描——部署是渐进的，扩展可能先于
 * selector 的 blue home 上线。
 */
function runContextSelector(cwd: string): string[] | undefined {
  let res;
  try {
    res = spawnSync(
      "bash",
      [SELECTOR_BIN, "--platform", "omp", "--cwd", cwd],
      { encoding: "utf8", timeout: 10_000 },
    );
  } catch (err) {
    console.warn(
      `[global-context] selector 调用异常，降级目录扫描: ${err instanceof Error ? err.message : String(err)}`,
    );
    return undefined;
  }
  const stdout = typeof res.stdout === "string" ? res.stdout : "";
  if (res.error || (res.status !== 0 && stdout.trim() === "")) {
    const detail = res.error ?? `exit ${res.status}`;
    const stderr = typeof res.stderr === "string" ? res.stderr.trim() : "";
    console.warn(
      `[global-context] selector 不可用（${detail}${stderr ? `: ${stderr}` : ""}），降级目录扫描`,
    );
    return undefined;
  }
  return stdout
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
}

/**
 * 降级路径：按名排序扫描默认 context 目录（selector 未部署时的现状行为）。
 */
async function scanDefaultContextDir(maxFiles: number): Promise<string[]> {
  let entries: string[];
  try {
    entries = await readdir(DEFAULT_CONTEXT_DIR);
  } catch {
    return [];
  }
  return entries
    .filter((f) => f.endsWith(".md"))
    .sort()
    .map((f) => resolve(DEFAULT_CONTEXT_DIR, f))
    .slice(0, Math.max(0, maxFiles));
}

/**
 * 解析本会话应注入的文件路径列表（selector 裁决，失败降级扫描）。
 * 返回路径列表 + 来源标记（供 /global-context 展示）。
 */
async function resolveInjectionFiles(
  config: GlobalContextConfig,
  cwd: string,
): Promise<{ paths: string[]; via: "selector" | "fallback" }> {
  const maxFiles = config.maxFiles ?? 8;
  const selected = runContextSelector(cwd);
  if (selected) {
    return {
      paths: selected.slice(0, Math.max(0, maxFiles)),
      via: "selector",
    };
  }
  return { paths: await scanDefaultContextDir(maxFiles), via: "fallback" };
}

/**
 * stat 校验路径列表（不实际读取内容），供 /global-context 展示。
 * 返回每个文件的：路径、是否存在、文件大小（不存在时为 -1）
 */
async function inspectFiles(
  paths: string[],
  source: string,
): Promise<{ path: string; exists: boolean; size: number; source: string }[]> {
  return Promise.all(
    paths.map(async (p) => {
      try {
        const info = await stat(p);
        return {
          path: p,
          exists: info.isFile(),
          size: info.isFile() ? info.size : -1,
          source,
        };
      } catch {
        return { path: p, exists: false, size: -1, source };
      }
    }),
  );
}

// ─── Extension Entry ──────────────────────────────────────────────────────────

export default function (pi: any) {
  try {
    return factoryBody(pi);
  } catch (err) {
    logLoadError("global-context", "factory", err);
    throw err; // 重新抛出让 omp 记录到它自己的 load errors
  }
}

function factoryBody(pi: ExtensionAPI) {
  const config = loadConfig();
  const isEnabled = config && config.enabled !== false;

  // ── registerCommand（始终注册，不受 enabled 影响）──

  pi.registerCommand("global-context", {
    description: "显示 global-context 插件注入的上下文文件及其路径",
    handler: async (_args, ctx) => {
      if (!config) {
        ctx.ui.notify(
          "globalContext 未配置（settings.json 中缺少 globalContext 字段）",
          "warn",
        );
        return;
      }

      const lines: string[] = [];
      lines.push("");
      lines.push("─── Global Context ───");
      lines.push("");

      // 状态行
      if (!isEnabled) {
        lines.push("状态: ❌ 已禁用 (enabled = false)");
      } else {
        lines.push("状态: ✅ 已启用");
      }

      // 配置摘要
      lines.push("");
      lines.push("配置:");
      lines.push(`  selector: ${SELECTOR_BIN}`);
      lines.push(
        `  限制: maxFiles=${config.maxFiles ?? 8}, maxBytesPerFile=${formatBytes(config.maxBytesPerFile ?? 65536)}, maxTotalBytes=${formatBytes(config.maxTotalBytes ?? 196608)}`,
      );

      // 文件列表（selector 裁决，失败降级扫描）
      const cwd = ctx?.cwd ?? process.cwd();
      const { paths, via } = await resolveInjectionFiles(config, cwd);
      const files = await inspectFiles(paths, via);
      if (files.length === 0) {
        lines.push("");
        lines.push("文件: (无)");
      } else {
        const totalBytes = files
          .filter((f) => f.exists)
          .reduce((sum, f) => sum + f.size, 0);
        const viaLabel =
          via === "selector" ? "selector 裁决" : "降级扫描（selector 不可用）";
        lines.push("");
        lines.push(
          `文件 (${viaLabel}, ${files.length} 个, ${formatBytes(totalBytes)}):`,
        );
        for (const f of files) {
          const icon = f.exists ? "✅" : "❌";
          const sizeStr = f.exists ? ` (${formatBytes(f.size)})` : "";
          lines.push(`  ${icon} ${f.path}${sizeStr}`);
        }
      }

      ctx.ui.notify(lines.join("\n"), "info");
    },
  });

  // ── /fetchcontext 命令（始终注册）──

  pi.registerCommand("fetchcontext", {
    description: "导出当前所有 LLM 上下文（系统提示词 + 对话历史）到文件",
    handler: async (_args, ctx) => {
      const systemPrompt = ctx.getSystemPrompt();
      const sm = ctx.sessionManager as any;
      const entries = sm.getEntries();
      const leafId = sm.getLeafId();
      const header = sm.getHeader();

      // 旧版用模块级 buildSessionContext(entries, leafId)，但 omp 没有把该函数
      // 暴露给扩展运行时。改用 ctx.sessionManager.buildContextEntries() 拿到
      // compaction-aware 的活跃 entries，再手动投影出 messages / model / thinkingLevel。
      // buildContextEntries 同样遵循 leaf 路径 + 处理 compaction，语义等价于
      // buildSessionContext 的 entries 部分（后者内部也是先调 buildContextEntries）。
      const contextEntries: any[] = sm.buildContextEntries
        ? sm.buildContextEntries(entries, leafId)
        : entries;

      // 投影：message entry → AgentMessage；model_change / thinking_level_change
      // 取最新一条（沿 leaf 路径从根到当前，最后出现的即当前生效值）。
      const messages: any[] = [];
      let model: { provider: string; modelId: string } | null = null;
      let thinkingLevel = "default";
      for (const e of contextEntries) {
        if (!e || typeof e !== "object") continue;
        if (e.type === "message" && e.message) {
          messages.push(e.message);
        } else if (e.type === "model_change") {
          model = { provider: e.provider, modelId: e.modelId };
        } else if (e.type === "thinking_level_change") {
          thinkingLevel = e.thinkingLevel;
        }
      }

      const sections: string[] = [];

      // 文档头
      sections.push("# LLM Context Export");
      sections.push("");
      sections.push(`Generated: ${new Date().toISOString()}`);
      if (header) sections.push(`Session: ${header.id}`);
      if (model) sections.push(`Model: ${model.provider}/${model.modelId}`);
      sections.push(`Thinking Level: ${thinkingLevel}`);
      sections.push(`Messages: ${messages.length}`);
      sections.push("");
      sections.push("---");
      sections.push("");

      // 系统提示词
      if (systemPrompt) {
        sections.push("## System Prompt");
        sections.push("");
        sections.push(systemPrompt);
        sections.push("");
        sections.push("---");
        sections.push("");
      }

      // 对话历史
      if (messages.length > 0) {
        sections.push("## Messages");
        sections.push("");
        for (const msg of messages) {
          const { role, text } = formatMessage(msg);
          sections.push(`### ${role}`);
          sections.push("");
          sections.push(text);
          sections.push("");
        }
      }

      // 写入文件
      const timestamp = new Date()
        .toISOString()
        .replace(/[-:]/g, "")
        .slice(0, 15);
      const outputPath = join(ctx.cwd, `context-export-${timestamp}.md`);
      try {
        await writeFile(outputPath, sections.join("\n"), "utf8");
        ctx.ui.notify(`Context exported to: ${outputPath}`, "info");
      } catch (err) {
        ctx.ui.notify(
          `Failed to write context export: ${err instanceof Error ? err.message : String(err)}`,
          "error",
        );
      }
    },
  });

  // ── before_agent_start hook（仅在 enabled 时注册）──

  if (!isEnabled) {
    return;
  }

  const separator = config.separator ?? "\n\n";
  const maxFiles = config.maxFiles ?? 8;
  const maxBytesPerFile = config.maxBytesPerFile ?? 65536;
  const maxTotalBytes = config.maxTotalBytes ?? 196608;

  pi.on("before_agent_start", async (event, _ctx) => {
    const cwd = _ctx?.cwd ?? process.cwd();
    const { paths: filesToLoad } = await resolveInjectionFiles(config, cwd);

    if (filesToLoad.length === 0) {
      return;
    }

    const contents = await Promise.all(
      filesToLoad.map(async (filePath) => {
        try {
          const info = await stat(filePath);
          if (!info.isFile() || info.size > maxBytesPerFile) {
            return null;
          }
          const content = await readFile(filePath, "utf8");
          return { filePath, content, size: info.size };
        } catch {
          return null;
        }
      }),
    );

    const validContents = contents.filter(
      (c): c is { filePath: string; content: string; size: number } =>
        c !== null && c.content.trim().length > 0,
    );

    if (validContents.length === 0) {
      return;
    }

    const blocks: string[] = [];
    let usedBytes = 0;
    for (const { filePath, content, size } of validContents) {
      const bytes = Buffer.byteLength(content, "utf8");
      if (usedBytes + bytes > maxTotalBytes) {
        break;
      }
      usedBytes += bytes;
      blocks.push(
        `<global_context_file path="${filePath}">\n${content}\n</global_context_file>`,
      );
    }

    if (blocks.length === 0) {
      return;
    }

    const injected = blocks.join(separator);
    const header =
      "The following is global context injected by the global-context extension:";

    return {
      systemPrompt:
        event.systemPrompt + separator + header + separator + injected,
    };
  });
}
