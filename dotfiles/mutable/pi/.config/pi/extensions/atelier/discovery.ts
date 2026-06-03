// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Agent 和 Prompt 发现 — 从 agents/ 和 prompts/ 目录扫描 .md 文件
 *
 * Agent 位置：$XDG_CONFIG_HOME/pi/agents/*.md（含 YAML frontmatter）
 * Prompt 位置：$XDG_CONFIG_HOME/pi/prompts/*.md（含 YAML frontmatter + JSON 模板）
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { getAgentDir, parseFrontmatter } from "@earendil-works/pi-coding-agent";
import type {
  AgentConfig,
  AgentModelConfig,
  PromptConfig,
  SubagentsJson,
} from "./types.ts";

// ─── Agent 发现 ──────────────────────────────────────────────────────────────

/**
 * 扫描 agents/ 目录下的 .md 文件，解析 frontmatter 提取 agent 配置。
 *
/**
 * 加载 subagents.json — agent 模型配置和 fallback 链
 *
 * 文件格式：
 * {
 *   "agents": {
 *     "oracle": { "model": "zai/GLM-5.1", "fallback": ["minimax-cn/MiniMax-M3"] }
 *   }
 * }
 *
 * 查找位置：$XDG_CONFIG_HOME/pi/subagents.json
 */
export function loadSubagentsConfig(): Record<string, AgentModelConfig> {
  const configPath = path.join(getAgentDir(), "subagents.json");
  try {
    const raw = JSON.parse(
      fs.readFileSync(configPath, "utf-8"),
    ) as SubagentsJson;
    return raw.agents ?? {};
  } catch {
    return {};
  }
}

/**
 * 获取 agent 的模型配置（首选模型 + fallback 链）。
 *
 * 优先级：subagents.json > settings.json defaultModel
 */
export function resolveAgentModel(
  agentName: string,
  subagentsConfig: Record<string, AgentModelConfig>,
): AgentModelConfig | undefined {
  return subagentsConfig[agentName];
}

/**
 * 每个 agent .md 文件格式：
 * ---
 * name: agent-name
 * description: 简短描述
 * tools: read, grep, bash    (可选)
 * ---
 * (body 作为 systemPrompt)
 *
 * 模型配置已移至 subagents.json，不再从 frontmatter 读取。
 */
export function discoverAgents(): AgentConfig[] {
  const agentsDir = path.join(getAgentDir(), "agents");
  const agents: AgentConfig[] = [];

  if (!fs.existsSync(agentsDir)) return agents;

  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(agentsDir, { withFileTypes: true });
  } catch {
    return agents;
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

    // 解析 tools 列表（逗号分隔）
    const tools = frontmatter.tools
      ?.split(",")
      .map((t: string) => t.trim())
      .filter(Boolean);

    agents.push({
      name: frontmatter.name,
      description: frontmatter.description,
      tools: tools && tools.length > 0 ? tools : undefined,
      systemPrompt: body,
      filePath,
    });
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
  const promptsDir = path.join(getAgentDir(), "prompts");
  const prompts: PromptConfig[] = [];

  if (!fs.existsSync(promptsDir)) return prompts;

  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(promptsDir, { withFileTypes: true });
  } catch {
    return prompts;
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

  return prompts;
}
