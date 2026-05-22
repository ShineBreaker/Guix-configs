import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readdir, readFile, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { resolve } from "node:path";

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

export default function (pi: ExtensionAPI) {
  const config = (pi.settings as Record<string, unknown>)?.globalContext as
    | {
        enabled?: boolean;
        contextDir?: string;
        files?: string[];
        extraFiles?: string[];
        separator?: string;
        maxFiles?: number;
        maxBytesPerFile?: number;
        maxTotalBytes?: number;
      }
    | undefined;

  if (!config || config.enabled === false) {
    return;
  }

  const separator = config?.separator ?? "\n\n";
  const contextDir = config?.contextDir ? resolveConfiguredPath(config.contextDir) : undefined;
  const maxFiles = config.maxFiles ?? 8;
  const maxBytesPerFile = config.maxBytesPerFile ?? 65536;
  const maxTotalBytes = config.maxTotalBytes ?? 196608;

  if (!contextDir) {
    return;
  }

  pi.on("before_agent_start", async (event, _ctx) => {
    let filesToLoad: string[];

    if (config?.files && config.files.length > 0) {
      // 显式指定了文件列表
      filesToLoad = config.files.map((f) =>
        f.startsWith("/") || f.startsWith("~") || f.includes("$") ? resolveConfiguredPath(f) : resolve(contextDir, f),
      );
    } else {
      // 动态扫描目录
      let entries: string[];
      try {
        entries = await readdir(contextDir);
      } catch {
        // 目录不存在，静默跳过
        entries = [];
      }
      filesToLoad = entries
        .filter((f) => f.endsWith(".md"))
        .sort()
        .map((f) => resolve(contextDir, f));
    }

    // 追加额外文件（绝对路径）
    if (config?.extraFiles && config.extraFiles.length > 0) {
      filesToLoad.push(...config.extraFiles.map(resolveConfiguredPath));
    }

    filesToLoad = filesToLoad.slice(0, Math.max(0, maxFiles));

    if (filesToLoad.length === 0) {
      return;
    }

    // 并行读取所有文件
    const contents = await Promise.all(
      filesToLoad.map(async (filePath) => {
        try {
          const info = await stat(filePath);
          if (!info.isFile() || info.size > maxBytesPerFile) {
            return null;
          }
          const content = await readFile(filePath, "utf8");
          return { filePath, content };
        } catch {
          return null;
        }
      }),
    );

    // 过滤掉读取失败的文件，拼接内容
    const validContents = contents.filter(
      (c): c is { filePath: string; content: string } => c !== null && c.content.trim().length > 0,
    );

    if (validContents.length === 0) {
      return;
    }

    const blocks: string[] = [];
    let usedBytes = 0;
    for (const { filePath, content } of validContents) {
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
