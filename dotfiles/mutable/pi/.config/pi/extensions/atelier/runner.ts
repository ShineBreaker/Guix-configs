// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 执行编排 — 三种运行模式的顶层协调逻辑
 *
 * - runParallelBatches: 并行执行（含并发限制和分批）
 * - runChain: 串行链式执行（{previous} 替换）
 * - executeWithFallback: 带 fallback 模型重试的单 agent 执行
 */

import type {
  AgentConfig,
  AgentModelConfig,
  RunResult,
  SubagentConfig,
} from "./types.ts";
import { launchParallel, launchSingle, paneIsAlive } from "./launcher.ts";
import { waitForAll, waitForCompletion } from "./monitor.ts";
import { ensureWorkfile } from "./workfile.ts";
// resolveAgentModel 已删除（subagents.json 废弃，逻辑并入 resolveModelChain）

// ─── Fallback 重试 ───────────────────────────────────────────────────────────

/** 同一任务最大重试次数（含首次尝试） */
const MAX_ATTEMPTS = 3;

/**
 * 解析 agent 的完整模型尝试链：[首选, ...fallback]
 *
 * 新优先级（自上而下短路）：
 *   1. 调用方显式覆盖（params.model）
 *   2. agent frontmatter `tier: inherit` → []（不传 model，跟随前台）
 *   3. agent frontmatter `tier: <name>` → 查 config.tiers[<name>]
 *   4. agent frontmatter 无 tier → 用 config.defaultTier
 *   5. 全部解析失败 → []（= inherit 行为，兜底跟随前台）
 *
 * @returns model 列表（可空），空数组表示"不传 --model"
 */
export function resolveModelChain(
  agent: AgentConfig,
  config: SubagentConfig,
  explicitModel?: string,
): string[] {
  // 1. 显式覆盖
  if (explicitModel) return [explicitModel];

  // 2-4. tier 解析
  const tier = agent.tier ?? config.defaultTier;

  // inherit 特殊值：明确声明跟随前台
  if (tier === "inherit") return [];

  // 查 tiers 配置
  const tierCfg: AgentModelConfig | undefined = config.tiers[tier];
  if (!tierCfg) return []; // 未知 tier 视为 inherit（兜底安全）

  return [tierCfg.model, ...tierCfg.fallback].filter(Boolean);
}

/**
 * 带 fallback 重试的单 agent 执行。
 *
 * 对同一任务尝试不同的模型（最多 MAX_ATTEMPTS 次）：
 *   1. 用首选模型执行
 *   2. 如果失败，用 fallback 链中的下一个模型重试
 *   3. 所有模型都失败后，返回最后一个失败结果
 *
 * 对 abort/timeout 不重试（这些不是模型问题）。
 */
export async function executeWithFallback(
  agent: AgentConfig,
  task: string,
  config: SubagentConfig,
  cwd: string,
  explicitModel: string | undefined,
  signal: AbortSignal | undefined,
  topRowTargetPaneId?: string,
  splitPercent?: number,
  images?: string[],
): Promise<RunResult> {
  const modelChain = resolveModelChain(agent, config, explicitModel);

  // 如果没有模型链（全部依赖 defaultModel），直接执行不重试
  if (modelChain.length === 0) {
    const launch = launchSingle(
      agent,
      task,
      config,
      cwd,
      undefined,
      topRowTargetPaneId,
      splitPercent ?? 50,
      images,
    );
    return waitForCompletion(launch, config, signal);
  }

  let lastResult: RunResult | undefined;
  const maxAttempts = Math.min(MAX_ATTEMPTS, modelChain.length);

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const model = modelChain[attempt];
    const launch = launchSingle(
      agent,
      task,
      config,
      cwd,
      model,
      topRowTargetPaneId,
      splitPercent ?? 50,
      images,
    );
    const result = await waitForCompletion(launch, config, signal);

    if (result.status === "completed") return result;

    lastResult = result;
    // abort 或超时不重试——这不是模型问题
    if (result.error === "Aborted" || result.error === "timeout") return result;
  }

  return lastResult!;
}

// ─── 并行执行 ────────────────────────────────────────────────────────────────

/**
 * 并行执行多批任务，每批不超过 maxConcurrency。
 *
 * 布局效果（以 3 个任务为例）：
 *   ┌──────────┬──────────┬──────────┐
 *   │  task1   │  task2   │  task3   │   ← 上方行，水平等分
 *   ├──────────┴──────────┴──────────┤
 *   │  主 agent                      │
 *   └────────────────────────────────┘
 */
export async function runParallelBatches(
  tasks: Array<{ agent: AgentConfig; task: string; cwd?: string }>,
  config: SubagentConfig,
  cwd: string,
  explicitModel?: string,
  signal?: AbortSignal,
): Promise<RunResult[]> {
  const results: RunResult[] = [];
  const concurrency = Math.max(
    1,
    Math.min(config.maxConcurrency, config.maxTasks),
  );
  const startedAt = Date.now();
  let topRowTargetPaneId: string | undefined;

  for (let i = 0; i < tasks.length; i += concurrency) {
    const batch = tasks.slice(i, i + concurrency);
    // 如果上一个 batch 的 pane 已关闭，重置续接点，让 launchParallel 重新创建顶部行
    if (topRowTargetPaneId && !paneIsAlive(topRowTargetPaneId)) {
      topRowTargetPaneId = undefined;
    }
    const launches = launchParallel(
      batch,
      config,
      // 注意：parallel 模式下所有任务共享同一 explicitModel（如提供），
      // 否则每个 agent 从自己的 tier 解析 model。
      // TODO: 如果需要 per-agent fallback，需要改为逐个 launchSingle
      explicitModel,
      topRowTargetPaneId,
    );
    // 记录最后一个 pane 作为后续 batch 的续接点
    topRowTargetPaneId = launches[launches.length - 1].paneId;
    const batchResults = await waitForAll(launches, config, signal);
    results.push(...batchResults);
  }

  // 验证 workfile（agent 未自行写入时兜底持久化）
  for (const r of results) {
    if (r.status === "completed") {
      ensureWorkfile(r, cwd, startedAt);
    }
  }

  return results;
}

// ─── 串行链式执行 ────────────────────────────────────────────────────────────

/**
 * 串行执行任务链。
 *
 * 每步的 task 中的 {previous} 被替换为上一步的输出，
 * {task} 被替换为根任务。每步使用 executeWithFallback 自动处理 fallback。
 *
 * 布局效果（以 3 步链为例）：
 *   ┌──────────┬──────────┬──────────┐
 *   │  step1   │  step2   │  step3   │   ← 上方行，逐步水平扩展
 *   ├──────────┴──────────┴──────────┤
 *   │  主 agent                       │
 *   └────────────────────────────────┘
 *
 * 注意：chain 的每一步依次启动，上一步完成后下一步才开始。
 * topRowTargetPaneId 确保所有步骤共享上方行。
 */
export async function runChain(
  steps: Array<{ agent: AgentConfig; task: string; cwd?: string }>,
  config: SubagentConfig,
  cwd: string,
  rootTask?: string,
  explicitModel?: string,
  signal?: AbortSignal,
): Promise<RunResult[]> {
  const results: RunResult[] = [];
  let previous = rootTask ?? "";
  let topRowTargetPaneId: string | undefined;
  const startedAt = Date.now();

  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    const task = step.task
      .replaceAll("{previous}", previous)
      .replaceAll("{task}", rootTask ?? previous);
    // 计算水平分割百分比，确保等分
    const pct = Math.round(((steps.length - i) / (steps.length - i + 1)) * 100);

    // 使用带 fallback 的执行
    const result = await executeWithFallback(
      step.agent,
      task,
      config,
      step.cwd ?? cwd,
      explicitModel,
      signal,
      topRowTargetPaneId,
      pct,
    );

    // 验证 workfile
    if (result.status === "completed") {
      ensureWorkfile(result, cwd, startedAt);
    }

    // 将 workfile 路径注入到下一步的上下文中
    let outputWithContext = result.output;
    if (result.workfilePath) {
      outputWithContext += `\n\n---\n上一步工作产物已持久化到: ${result.workfilePath}`;
    }

    results.push(result);
    previous = outputWithContext;
    if (result.status === "failed") break;
  }

  return results;
}
