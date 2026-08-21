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
  /**
   * 模型档次（来自 frontmatter `tier:` 字段）：
   *   - "ultra" | "pro" | "quick" | "visual" → 查 settings.json `atelier.tiers` 配置
   *   - "inherit" → 不传 --model，让 pi 用前台 defaultModel（worker 默认行为）
   *   - undefined → 用 settings.json `atelier.defaultTier`
   */
  tier?: string;
  systemPrompt: string;
  filePath: string;
}

/** 模型配置：首选 + fallback 链（tier 系统的底层结构） */
export interface AgentModelConfig {
  /** 首选模型 */
  model: string;
  /** fallback 模型链，按顺序尝试 */
  fallback: string[];
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
  /** tier 字段缺失时的默认 tier；解析不到时回退到 "inherit" */
  defaultTier: string;
  /** tier 名 → model + fallback 链的映射 */
  tiers: Record<string, AgentModelConfig>;
  /**
   * 模型使用时段限制（按模型名索引，跨 tier 生效）。
   *
   * 形状：`{ "zai/GLM-5.2": { deny: ["Mon-Fri 14:00-18:00"] } }`。
   * resolveModelChain 按模型名查这份映射；被时段过滤掉的模型从尝试链
   * 中跳过（每跳过一个 console.warn 一次）。未列出的模型不受限。
   *
   * 放在顶层而非 per-tier：同一个模型（如 GLM-5.2）可能作为多个 tier
   * 的首选或 fallback 出现，per-model 让时段规则跟随模型本身而非 tier。
   */
  modelSchedules: Record<string, { allow?: string[]; deny?: string[] }>;
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
  defaultTier: "pro",
  tiers: {},
  modelSchedules: {},
};
