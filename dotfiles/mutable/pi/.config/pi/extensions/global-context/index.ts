// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getAgentDir } from "@earendil-works/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { readdir, readFile, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

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

  expanded = expanded.replace(/\$([A-Z_][A-Z0-9_]*)|\$\{([A-Z_][A-Z0-9_]*)\}/gi, (_match, bare, braced) => {
    const key = bare ?? braced;
    if (process.env[key]) return process.env[key]!;
    if (key === "HOME") return homedir();
    if (key === "XDG_CONFIG_HOME") return resolve(homedir(), ".config");
    if (key === "XDG_DATA_HOME") return resolve(homedir(), ".local", "share");
    if (key === "XDG_CACHE_HOME") return resolve(homedir(), ".cache");
    return "";
  });

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
 * 从 settings.json 文件读取 globalContext 配置
 *
 * Pi ExtensionAPI 不提供 pi.settings，需要自行读取文件。
 * 查找顺序：getAgentDir()/settings.json → ~/.config/pi/settings.json
 */
function loadConfig(): GlobalContextConfig | undefined {
  const candidates = [
    join(getAgentDir(), "settings.json"),
    join(homedir(), ".config", "pi", "settings.json"),
  ];

  for (const settingsPath of candidates) {
    if (!existsSync(settingsPath)) continue;
    try {
      const raw = JSON.parse(readFileSync(settingsPath, "utf8"));
      return raw?.globalContext as GlobalContextConfig | undefined;
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
  { path: string; resolved: string; exists: boolean; size: number; source: string }[]
> {
  const maxFiles = config.maxFiles ?? 8;
  const contextDir = config.contextDir ? resolveConfiguredPath(config.contextDir) : undefined;
  const results: { path: string; resolved: string; exists: boolean; size: number; source: string }[] = [];

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
        results.push({ path: filePath, resolved: filePath, exists: false, size: -1, source: config.files ? "files[]" : "contextDir" });
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
        results.push({ path: raw, resolved, exists: false, size: -1, source: "extraFiles[]" });
      }
    }
  }

  return results;
}

// ─── Extension Entry ──────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  const config = loadConfig();
  const isEnabled = config && config.enabled !== false;

  // ── registerCommand（始终注册，不受 enabled/contextDir 影响）──

  pi.registerCommand("global-context", {
    description: "显示 global-context 插件注入的上下文文件及其路径",
    handler: async (_args, ctx) => {
      if (!config) {
        ctx.ui.notify("globalContext 未配置（settings.json 中缺少 globalContext 字段）", "warn");
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
      if (contextDir) lines.push(`  contextDir: ${config.contextDir} → ${contextDir}`);
      else lines.push("  contextDir: (未配置)");
      if (config.files?.length) lines.push(`  files: [${config.files.map((f) => `"${f}"`).join(", ")}]`);
      if (config.extraFiles?.length) lines.push(`  extraFiles: [${config.extraFiles.map((f) => `"${f}"`).join(", ")}]`);
      lines.push(`  限制: maxFiles=${config.maxFiles ?? 8}, maxBytesPerFile=${formatBytes(config.maxBytesPerFile ?? 65536)}, maxTotalBytes=${formatBytes(config.maxTotalBytes ?? 196608)}`);

      // 文件列表（实时扫描）
      const files = await listConfiguredFiles(config);
      if (files.length === 0) {
        lines.push("");
        lines.push("文件: (无)");
      } else {
        const totalBytes = files.filter((f) => f.exists).reduce((sum, f) => sum + f.size, 0);
        lines.push("");
        lines.push(`文件 (${files.length} 个, ${formatBytes(totalBytes)}):`);
        for (const f of files) {
          const icon = f.exists ? "✅" : "❌";
          const sizeStr = f.exists ? ` (${formatBytes(f.size)})` : "";
          const srcTag = f.source === "extraFiles[]" ? " [extra]" : "";
          if (f.path === f.resolved) {
            lines.push(`  ${icon} ${f.path}${sizeStr}${srcTag}`);
          } else {
            lines.push(`  ${icon} ${f.path} → ${f.resolved}${sizeStr}${srcTag}`);
          }
        }
      }

      ctx.ui.notify(lines.join("\n"), "info");
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
        f.startsWith("/") || f.startsWith("~") || f.includes("$") ? resolveConfiguredPath(f) : resolve(contextDir, f),
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
      (c): c is { filePath: string; content: string; size: number } => c !== null && c.content.trim().length > 0,
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
      blocks.push(`<global_context_file path="${filePath}">\n${content}\n</global_context_file>`);
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
