import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

/**
 * global-context extension
 *
 * 使用 before_agent_start hook 将内容追加到系统提示词。
 *
 * 支持的配置（settings.json → globalContext 字段）：
 *   - contextDir: string   — 上下文文件目录（必需）
 *   - files: string[]       — contextDir 内的文件列表（默认按文件名排序加载目录下所有 .md）
 *   - extraFiles: string[]  — 额外的绝对路径文件列表
 *   - separator: string     — 文件之间的分隔符（默认 \n\n）
 */
export default function (pi: ExtensionAPI) {
  const config = (pi.settings as Record<string, unknown>)?.globalContext as
    | {
        contextDir?: string;
        files?: string[];
        extraFiles?: string[];
        separator?: string;
      }
    | undefined;

  const separator = config?.separator ?? "\n\n";
  const contextDir = config?.contextDir ?? ".";

  pi.on("before_agent_start", async (event, _ctx) => {
    let filesToLoad: string[];

    if (config?.files && config.files.length > 0) {
      // 显式指定了文件列表
      filesToLoad = config.files.map((f) =>
        f.startsWith("/") ? f : resolve(contextDir, f),
      );
    } else {
      // 动态扫描目录
      const { readdir } = await import("node:fs/promises");
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
      filesToLoad.push(...config.extraFiles);
    }

    if (filesToLoad.length === 0) {
      return;
    }

    // 并行读取所有文件
    const contents = await Promise.all(
      filesToLoad.map(async (filePath) => {
        try {
          return await readFile(filePath, "utf8");
        } catch {
          return null;
        }
      }),
    );

    // 过滤掉读取失败的文件，拼接内容
    const validContents = contents.filter(
      (c): c is string => c !== null && c.trim().length > 0,
    );

    if (validContents.length === 0) {
      return;
    }

    const injected = validContents.join(separator);
    const header =
      "The following is global context injected by the global-context extension:";

    return {
      systemPrompt:
        event.systemPrompt + separator + header + separator + injected,
    };
  });
}
