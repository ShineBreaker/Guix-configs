// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 结果格式化 — 将 RunResult 数组转换为人类可读的汇总文本
 */

import type { RunResult } from "./types.ts";

/** 格式化单个 agent 的运行结果（含 workfile 路径提示） */
export function formatResult(r: RunResult): string {
  const icon = r.status === "completed" ? "✓" : "✗";
  const workfile = r.workfilePath ? `\n📄 工作产物: ${r.workfilePath}` : "";
  return `### [${r.agent}] ${icon} (${r.durationMs}ms)${workfile}\n\n${r.output}`;
}

/** 格式化多个 agent 运行结果的汇总 */
export function formatResults(results: RunResult[]): string {
  const success = results.filter((r) => r.status === "completed").length;
  return `${success}/${results.length} succeeded\n\n${results.map(formatResult).join("\n\n---\n\n")}`;
}
