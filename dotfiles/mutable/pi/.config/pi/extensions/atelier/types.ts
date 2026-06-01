// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 类型定义 — atelier 扩展的所有接口和常量
 *
 * 包含：Agent/Prompt/Run 相关接口、默认配置、分屏百分比常量
 */

// ─── Agent & Prompt 配置 ────────────────────────────────────────────────────

/** 从 .md 文件发现的 agent 配置 */
export interface AgentConfig {
  name: string;
  description: string;
  tools?: string[];
  model?: string;
  thinking?: string;
  systemPrompt: string;
  filePath: string;
}

/** 从 .md 文件发现的 prompt 模板配置 */
export interface PromptConfig {
  name: string;
  mode: "single" | "parallel" | "chain";
  param: string;
  description: string;
  /** 解析后的 {agent, task} 列表 */
  entries: Array<{ agent: string; task: string }>;
}

// ─── 运行时数据 ─────────────────────────────────────────────────────────────

/** atelier 运行时配置（从 settings.json 的 atelier 字段加载） */
export interface SubagentConfig {
  pollIntervalMs: number;
  panePrefix: string;
  keepResults: number;
  timeoutMs: number;
  maxTasks: number;
  maxConcurrency: number;
}

/** 单次 tmux pane 启动的结果 */
export interface LaunchResult {
  runId: string;
  runDir: string;
  paneId: string;
  paneTitle: string;
  agent: AgentConfig;
}

/** 单次 agent 运行的最终结果 */
export interface RunResult {
  runId: string;
  agent: string;
  status: "completed" | "failed" | "running";
  exitCode: number;
  output: string;
  durationMs: number;
  tmuxPane: string;
  error?: string;
  workfilePath?: string;
}

/** 返回给 tool caller 的 details 结构 */
export interface SubagentDetails {
  mode: "single" | "parallel" | "chain" | "list" | "status";
  results: RunResult[];
}

/** run 目录下的 status.json 文件结构 */
export interface StatusFile {
  status: "running" | "completed" | "failed";
  exitCode?: number;
  finishedAt?: number;
  startedAt?: number;
  error?: string;
}

// ─── 常量 ────────────────────────────────────────────────────────────────────

/** 默认运行时配置 */
export const DEFAULT_CONFIG: SubagentConfig = {
  pollIntervalMs: 2000,
  panePrefix: "sub:",
  keepResults: 24,
  timeoutMs: 30 * 60 * 1000,
  maxTasks: 8,
  maxConcurrency: 4,
};

/** parallel 模式下，上方 subagent 行占窗口高度百分比 */
export const TOP_ROW_PERCENT = "40";
