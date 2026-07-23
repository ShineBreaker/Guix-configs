// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { readdir, readFile, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

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
 * 定位 omp 配置目录（替代旧 pi 的 getAgentDir()）。
 *
 * omp 17.0.7 没有把 getAgentDir 暴露给扩展运行时（value import 会
 * `Cannot find module`）。这里按 omp 内部解析顺序定位：环境变量优先，
 * 回退 ~/.config/omp（config.yml / mcp.json / global-context.json 都在这里）。
 */
function getOmpConfigDir(): string {
  return (
    process.env.OMP_CONFIG_DIR ||
    process.env.PI_CONFIG_DIR ||
    join(homedir(), ".config", "omp")
  );
}

/**
 * global-context extension
 *
 * 使用 before_agent_start hook 将内容追加到系统提示词。
 *
 * 支持的配置（settings.json → globalContext 字段）：
 *   - enabled: boolean     — 显式启用/禁用（默认：有配置时启用）
 *   - contextDir: string   — 上下文文件目录（必需）
 *   - files: string[]       — contextDir 内的文件列表（默认按文件名排序加载目录下所有 .md）
 *   - extraFiles: string[]  — 额外的绝对路径文件列表
 *   - separator: string     — 文件之间的分隔符（默认 \n\n）
 *   - maxFiles: number      — 最多注入文件数（默认 8）
 *   - maxBytesPerFile: number — 单文件最大读取字节（默认 65536）
 *   - maxTotalBytes: number — 总注入字节预算（默认 196608）
 */

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

function resolveConfiguredPath(input: string): string {
  let expanded = input;
  if (expanded === "~") {
    expanded = homedir();
  } else if (expanded.startsWith("~/")) {
    expanded = resolve(homedir(), expanded.slice(2));
  }

  expanded = expanded.replace(
    /\$([A-Z_][A-Z0-9_]*)|\$\{([A-Z_][A-Z0-9_]*)\}/gi,
    (_match, bare, braced) => {
      const key = bare ?? braced;
      if (process.env[key]) return process.env[key]!;
      if (key === "HOME") return homedir();
      if (key === "XDG_CONFIG_HOME") return resolve(homedir(), ".config");
      if (key === "XDG_DATA_HOME") return resolve(homedir(), ".local", "share");
      if (key === "XDG_CACHE_HOME") return resolve(homedir(), ".cache");
      return "";
    },
  );

  return resolve(expanded);
}

// ─── 配置类型 ────────────────────────────────────────────────────────────────

interface GlobalContextConfig {
  enabled?: boolean;
  contextDir?: string;
  files?: string[];
  extraFiles?: string[];
  separator?: string;
  maxFiles?: number;
  maxBytesPerFile?: number;
  maxTotalBytes?: number;
}

/**
 * 读取 global-context 自身配置
 *
 * omp 的 ExtensionAPI 不提供配置读取接口（无 pi.config / pi.getConfig），
 * 扩展需自管配置文件。本扩展读 getOmpConfigDir()/global-context.json。
 * 兼容旧 pi：若 config.yml 不存在，回退读 settings.json 的 globalContext 字段。
 */
function loadConfig(): GlobalContextConfig | undefined {
  const agentDir = getOmpConfigDir();
  const candidates = [
    join(agentDir, "global-context.json"), // omp：独立配置文件（推荐）
    join(agentDir, "settings.json"), // 旧 pi：settings.json 内嵌字段（向后兼容）
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
 * 列出配置所指向的所有文件路径（不实际读取内容）
 *
 * 返回每个文件的：解析后路径、是否存在、文件大小（不存在时为 -1）
 */
async function listConfiguredFiles(config: GlobalContextConfig): Promise<
  {
    path: string;
    resolved: string;
    exists: boolean;
    size: number;
    source: string;
  }[]
> {
  const maxFiles = config.maxFiles ?? 8;
  const contextDir = config.contextDir
    ? resolveConfiguredPath(config.contextDir)
    : undefined;
  const results: {
    path: string;
    resolved: string;
    exists: boolean;
    size: number;
    source: string;
  }[] = [];

  // 1) contextDir 中的文件
  if (contextDir) {
    let filesToLoad: string[];

    if (config.files && config.files.length > 0) {
      filesToLoad = config.files.map((f) =>
        f.startsWith("/") || f.startsWith("~") || f.includes("$")
          ? resolveConfiguredPath(f)
          : resolve(contextDir, f),
      );
    } else {
      let entries: string[];
      try {
        entries = await readdir(contextDir);
      } catch {
        entries = [];
      }
      filesToLoad = entries
        .filter((f) => f.endsWith(".md"))
        .sort()
        .map((f) => resolve(contextDir, f));
    }

    for (const filePath of filesToLoad.slice(0, maxFiles)) {
      try {
        const info = await stat(filePath);
        results.push({
          path: filePath, // resolved 已经是绝对路径
          resolved: filePath,
          exists: true,
          size: info.size,
          source: config.files ? "files[]" : "contextDir",
        });
      } catch {
        results.push({
          path: filePath,
          resolved: filePath,
          exists: false,
          size: -1,
          source: config.files ? "files[]" : "contextDir",
        });
      }
    }
  }

  // 2) extraFiles
  if (config.extraFiles && config.extraFiles.length > 0) {
    const remaining = Math.max(0, maxFiles - results.length);
    for (const raw of config.extraFiles.slice(0, remaining)) {
      const resolved = resolveConfiguredPath(raw);
      try {
        const info = await stat(resolved);
        results.push({
          path: raw,
          resolved,
          exists: true,
          size: info.size,
          source: "extraFiles[]",
        });
      } catch {
        results.push({
          path: raw,
          resolved,
          exists: false,
          size: -1,
          source: "extraFiles[]",
        });
      }
    }
  }

  return results;
}

// ─── Extension Entry ──────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
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

  // ── registerCommand（始终注册，不受 enabled/contextDir 影响）──

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
      const contextDir = config.contextDir
        ? resolveConfiguredPath(config.contextDir)
        : undefined;
      lines.push("");
      lines.push("配置:");
      if (contextDir)
        lines.push(`  contextDir: ${config.contextDir} → ${contextDir}`);
      else lines.push("  contextDir: (未配置)");
      if (config.files?.length)
        lines.push(
          `  files: [${config.files.map((f) => `"${f}"`).join(", ")}]`,
        );
      if (config.extraFiles?.length)
        lines.push(
          `  extraFiles: [${config.extraFiles.map((f) => `"${f}"`).join(", ")}]`,
        );
      lines.push(
        `  限制: maxFiles=${config.maxFiles ?? 8}, maxBytesPerFile=${formatBytes(config.maxBytesPerFile ?? 65536)}, maxTotalBytes=${formatBytes(config.maxTotalBytes ?? 196608)}`,
      );

      // 文件列表（实时扫描）
      const files = await listConfiguredFiles(config);
      if (files.length === 0) {
        lines.push("");
        lines.push("文件: (无)");
      } else {
        const totalBytes = files
          .filter((f) => f.exists)
          .reduce((sum, f) => sum + f.size, 0);
        lines.push("");
        lines.push(`文件 (${files.length} 个, ${formatBytes(totalBytes)}):`);
        for (const f of files) {
          const icon = f.exists ? "✅" : "❌";
          const sizeStr = f.exists ? ` (${formatBytes(f.size)})` : "";
          const srcTag = f.source === "extraFiles[]" ? " [extra]" : "";
          if (f.path === f.resolved) {
            lines.push(`  ${icon} ${f.path}${sizeStr}${srcTag}`);
          } else {
            lines.push(
              `  ${icon} ${f.path} → ${f.resolved}${sizeStr}${srcTag}`,
            );
          }
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

  // ── before_agent_start hook（仅在 enabled + contextDir 有效时注册）──

  if (!isEnabled || !config.contextDir) {
    return;
  }

  const separator = config.separator ?? "\n\n";
  const contextDir = resolveConfiguredPath(config.contextDir);
  const maxFiles = config.maxFiles ?? 8;
  const maxBytesPerFile = config.maxBytesPerFile ?? 65536;
  const maxTotalBytes = config.maxTotalBytes ?? 196608;

  pi.on("before_agent_start", async (event, _ctx) => {
    let filesToLoad: string[];

    if (config?.files && config.files.length > 0) {
      filesToLoad = config.files.map((f) =>
        f.startsWith("/") || f.startsWith("~") || f.includes("$")
          ? resolveConfiguredPath(f)
          : resolve(contextDir, f),
      );
    } else {
      let entries: string[];
      try {
        entries = await readdir(contextDir);
      } catch {
        entries = [];
      }
      filesToLoad = entries
        .filter((f) => f.endsWith(".md"))
        .sort()
        .map((f) => resolve(contextDir, f));
    }

    if (config?.extraFiles && config.extraFiles.length > 0) {
      filesToLoad.push(...config.extraFiles.map(resolveConfiguredPath));
    }

    filesToLoad = filesToLoad.slice(0, Math.max(0, maxFiles));

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
