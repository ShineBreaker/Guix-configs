// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Agent 和 Prompt 发现 — 扫描候选目录下的 .md 文件并解析 frontmatter。
 *
 * 2026 重构后路径优先级（见 context.ts 的 getAgentDirs/getPromptDirs）：
 *   1. 插件内置 context/{agents,prompts}/（atelier 自包含 agent 定义）
 *   2. getAgentDir()/{agents,prompts}/（用户自定义，兼容旧路径）
 *
 * 同名 agent：插件内置优先，用户自定义被忽略（避免重复注册）。
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { parseFrontmatter } from "@earendil-works/pi-coding-agent";
import type { AgentConfig, PromptConfig } from "./types.ts";
import { getAgentDirs, getPromptDirs } from "./context.ts";

// ─── Agent 发现 ──────────────────────────────────────────────────────────────

/**
 * 扫描候选 agents/ 目录下的 .md 文件，解析 frontmatter 提取 agent 配置。
 *
 * 每个 agent .md 文件格式：
 * ---
 * name: agent-name
 * description: 简短描述
 * tier: ultra | pro | quick | visual | inherit   (可选；缺失时用 defaultTier)
 * tools: read, grep, bash                         (可选)
 * ---
 * (body 作为 systemPrompt)
 *
 * 模型档次通过 frontmatter `tier:` 字段声明；具体 model + fallback 在
 * settings.json 的 `atelier.tiers` 段集中配置。
 *
 * 同名 agent：插件内置目录优先（按 getAgentDirs() 顺序），后扫到的跳过。
 */
export function discoverAgents(): AgentConfig[] {
  const agents: AgentConfig[] = [];
  const seen = new Set<string>(); // 按 name 去重（插件内置优先）

  for (const agentsDir of getAgentDirs()) {
    if (!fs.existsSync(agentsDir)) continue;

    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(agentsDir, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      if (!entry.name.endsWith(".md")) continue;
      if (!entry.isFile() && !entry.isSymbolicLink()) continue;

      const filePath = path.join(agentsDir, entry.name);
      let content: string;
      try {
        content = fs.readFileSync(filePath, "utf-8");
      } catch {
        continue;
      }

      const { frontmatter, body } =
        parseFrontmatter<Record<string, string>>(content);
      if (!frontmatter.name || !frontmatter.description) continue;
      if (seen.has(frontmatter.name)) continue; // 插件内置优先，跳过重复
      seen.add(frontmatter.name);

      // 解析 tools 列表（逗号分隔）
      const tools = frontmatter.tools
        ?.split(",")
        .map((t: string) => t.trim())
        .filter(Boolean);

      // tier 字段：ultra / pro / quick / visual / inherit，缺失为 undefined
      const tier = frontmatter.tier?.trim() || undefined;

      agents.push({
        name: frontmatter.name,
        description: frontmatter.description,
        tools: tools && tools.length > 0 ? tools : undefined,
        tier,
        systemPrompt: body,
        filePath,
      });
    }
  }

  return agents;
}

// ─── Prompt 发现 ─────────────────────────────────────────────────────────────

/**
 * 自定义 frontmatter 解析器 — 跳过 SPDX 注释块（不依赖 parseFrontmatter 的文件起始约束）
 */
function parsePromptFrontmatter(
  content: string,
): { frontmatter: Record<string, string>; body: string } | null {
  // 跳过开头的 HTML 注释块（SPDX 头）
  let offset = 0;
  if (content.startsWith("<!--")) {
    const closeIdx = content.indexOf("-->");
    if (closeIdx >= 0) offset = closeIdx + 3;
  }
  // 跳过空白
  while (offset < content.length && /\s/.test(content[offset])) offset++;

  // 检查 frontmatter
  if (!content.startsWith("---", offset)) return null;
  const fmStart = offset + 3;
  const fmEnd = content.indexOf("\n---", fmStart);
  if (fmEnd < 0) return null;

  const fmText = content.slice(fmStart, fmEnd);
  const frontmatter: Record<string, string> = {};
  for (const line of fmText.split("\n")) {
    const m = line.match(/^(\w+):\s*(.*)/);
    if (m) frontmatter[m[1]] = m[2].trim();
  }

  const body = content.slice(fmEnd + 4); // skip \n---\n
  return { frontmatter, body };
}

/**
 * 扫描 prompts/ 目录下的 .md 文件，解析 frontmatter + JSON 模板。
 *
 * 每个 prompt .md 文件格式：
 * ---
 * name: prompt-name
 * mode: single | parallel | chain
 * param: task        (模板占位符名)
 * description: ...
 * ---
 * ```json
 * { "chain": [{ "agent": "...", "task": "..." }, ...] }
 * ```
 */
export function discoverPrompts(): PromptConfig[] {
  const prompts: PromptConfig[] = [];
  const seen = new Set<string>(); // 按 name 去重（插件内置优先）

  for (const promptsDir of getPromptDirs()) {
    if (!fs.existsSync(promptsDir)) continue;

    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(promptsDir, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      if (!entry.name.endsWith(".md")) continue;
      if (!entry.isFile() && !entry.isSymbolicLink()) continue;

      const filePath = path.join(promptsDir, entry.name);
      let content: string;
      try {
        content = fs.readFileSync(filePath, "utf-8");
      } catch {
        continue;
      }

      const parsed = parsePromptFrontmatter(content);
      if (!parsed || !parsed.frontmatter.name || !parsed.frontmatter.mode)
        continue;

      if (seen.has(parsed.frontmatter.name)) continue; // 插件内置优先，跳过重复
      seen.add(parsed.frontmatter.name);

      const mode = parsed.frontmatter.mode as "single" | "parallel" | "chain";
      if (!["single", "parallel", "chain"].includes(mode)) continue;

      // 从 body 中提取第一个 JSON 代码块作为模板
      const jsonMatch = parsed.body.match(/```json\s*\n([\s\S]*?)\n```/);
      if (!jsonMatch) continue;

      let template: Record<string, unknown>;
      try {
        template = JSON.parse(jsonMatch[1]);
      } catch {
        continue;
      }

      // 从 JSON 模板中提取 entries（支持 chain/tasks/单对象三种格式）
      const promptEntries: Array<{ agent: string; task: string }> = [];
      const items = (template.chain ?? template.tasks ?? [template]) as Array<
        Record<string, string>
      >;
      for (const item of items) {
        if (item.agent && item.task) {
          promptEntries.push({ agent: item.agent, task: item.task });
        }
      }

      if (promptEntries.length === 0) continue;

      prompts.push({
        name: parsed.frontmatter.name,
        mode,
        param: parsed.frontmatter.param ?? "task",
        description: parsed.frontmatter.description ?? "",
        entries: promptEntries,
      });
    }
  }

  return prompts;
}
