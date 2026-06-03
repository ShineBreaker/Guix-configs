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
 */

const SUBAGENT_START = /<!--\s*@atelier:subagent\s*-->/;
const SUBAGENT_END = /<!--\s*\/@atelier:subagent\s*-->/;

/**
 * 检查文件中是否有 subagent-only 标记。
 */
export function hasSubagentOnlySection(content: string): boolean {
  return SUBAGENT_START.test(content) && SUBAGENT_END.test(content);
}

/**
 * 提取 subagent-only 段（标记之间的内容，不含标记本身）。
 *
 * 如果只有一个标记或没有匹配的结束/开始标记，按以下规则处理：
 * - 没有开始标记：返回空字符串
 * - 没有结束标记：返回开始标记到文件末尾的内容
 *
 * 多个 subagent-only 段会被拼接（每段之间用一个换行分隔）。
 */
export function extractSubagentOnlySection(content: string): string {
  const parts: string[] = [];
  const lines = content.split("\n");
  let i = 0;
  let inSubagent = false;
  let buffer: string[] = [];

  while (i < lines.length) {
    const line = lines[i];

    if (!inSubagent && SUBAGENT_START.test(line)) {
      inSubagent = true;
      buffer = [];
      i++;
      continue;
    }

    if (inSubagent && SUBAGENT_END.test(line)) {
      inSubagent = false;
      parts.push(buffer.join("\n").trim());
      buffer = [];
      i++;
      continue;
    }

    if (inSubagent) {
      buffer.push(line);
    }
    i++;
  }

  // 未闭合的开始标记：把剩余内容也加进去
  if (inSubagent && buffer.length > 0) {
    parts.push(buffer.join("\n").trim());
  }

  return parts.filter((p) => p.length > 0).join("\n\n");
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
