// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Agent prompt 切片工具 — 在 agent .md 文件中用 HTML 注释标记切出
 * subagent-only 段。主会话注入时剥离，subagent 启动时保留。
 *
 * 标记语法：
 *   开始: <!-- @atelier:subagent -->
 *   结束: <!-- /@atelier:subagent -->
 *
 * 设计动机：agents/*.md 是 subagent 的真实 prompt，但当主会话按模式
 * 读取 worker.md / planner.md 时，那些 subagent-only 的实现细节
 * （workfile 路径、详细输出模板等）不应该污染主会话的上下文。
 *
 * HTML 注释是给解析器看的标记，LLM 不会复述。如果未来要切换到更
 * 结构化的标记（如 frontmatter 字段），只需修改这两个函数。
 *
 * ── 路径解析（2026 重构后）─────────────────────────────────────────
 * agent/prompt .md 源文件已从 ~/.config/pi/agents/ 迁移到插件内置
 * context/agents/。本模块提供统一的路径解析 helper，供 discovery.ts /
 * launcher.ts / wrapper.sh 复用：
 *   1. 插件内置 context/{agents,prompts}/ 优先（atelier 自包含 agent 定义）
 *   2. getAgentDir()/{agents,prompts}/ 兼容用户自定义 agent
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

const SUBAGENT_START = /<!--\s*@atelier:subagent\s*-->/;
const SUBAGENT_END = /<!--\s*\/@atelier:subagent\s*-->/;

// ─── 路径解析 helpers ─────────────────────────────────────────────────────────

/**
 * 解析插件内置资源根目录（atelier/）。
 *
 * 用 import.meta.url 定位当前模块（context.ts 在 atelier/core/），
 * 向上一级就是 atelier/。jiti 加载扩展时保留真实文件路径，所以
 * import.meta.url 反映磁盘上的真实位置（非内存虚拟模块）。
 */
export function getPluginRoot(): string {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
}

/**
 * agent .md 候选目录列表，按优先级排序：
 *   1. 插件内置 context/agents/（atelier 自带 agent 定义）
 *   2. getAgentDir()/agents/（用户自定义 agent，兼容旧路径）
 */
export function getAgentDirs(): string[] {
  return [
    path.join(getPluginRoot(), "context", "agents"),
    path.join(getAgentDir(), "agents"),
  ];
}

/**
 * prompt .md 候选目录列表，按同上优先级排序。
 */
export function getPromptDirs(): string[] {
  return [
    path.join(getPluginRoot(), "context", "prompts"),
    path.join(getAgentDir(), "prompts"),
  ];
}

/**
 * 按优先级查找指定 agent 名的 .md 文件，返回第一个存在的路径。
 *
 * 被 discovery.ts / launcher.ts / 主会话注入逻辑共用，
 * 保证所有读取点走同一路径解析策略。
 *
 * @returns 找到的文件绝对路径；全部不存在返回 null
 */
export function resolveAgentFile(agentName: string): string | null {
  for (const dir of getAgentDirs()) {
    const candidate = path.join(dir, `${agentName}.md`);
    try {
      if (fs.existsSync(candidate)) return candidate;
    } catch {
      /* 试下一个候选 */
    }
  }
  return null;
}

/**
 * 从完整内容中剥离 subagent-only 段，得到 main-session 视图。
 *
 * 保留所有非 subagent-only 段的内容（包括标记外的所有行）。
 * 标记本身也被删除。
 */
export function stripSubagentOnlySection(content: string): string {
  const lines = content.split("\n");
  const result: string[] = [];
  let inSubagent = false;

  for (const line of lines) {
    if (!inSubagent && SUBAGENT_START.test(line)) {
      inSubagent = true;
      continue;
    }
    if (inSubagent && SUBAGENT_END.test(line)) {
      inSubagent = false;
      continue;
    }
    if (!inSubagent) {
      result.push(line);
    }
  }

  // 清理可能因删除中间段而产生的多余空行
  return collapseBlankLines(result.join("\n"));
}

/**
 * 移除 subagent-only 标记但保留所有内容。
 *
 * 用于 subagent 启动：subagent 应该看到完整内容（包括 subagent-only 段），
 * 但不应该看到 HTML 注释标记本身（避免污染 LLM 上下文）。
 */
export function removeSubagentOnlyMarkers(content: string): string {
  return content
    .split("\n")
    .filter((line) => !SUBAGENT_START.test(line) && !SUBAGENT_END.test(line))
    .join("\n");
}

/** 将连续空行折叠为单个空行，并去除首尾空行 */
function collapseBlankLines(text: string): string {
  const lines = text.split("\n");
  const result: string[] = [];
  for (const line of lines) {
    const last = result[result.length - 1];
    if (line.trim() === "" && last !== undefined && last.trim() === "") {
      continue;
    }
    result.push(line);
  }
  return result.join("\n").trim();
}
