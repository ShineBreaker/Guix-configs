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

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { getAgentDir } from "@earendil-works/pi-coding-agent";
import type {
  AgentConfig,
  AgentModelConfig,
  RunResult,
  SubagentConfig,
} from "../core/types.ts";
import {
  generateRunId,
  launchParallel,
  launchSingle,
  paneIsAlive,
} from "./launcher.ts";
import { waitForAll, waitForCompletion } from "./monitor.ts";
import { ensureWorkfile } from "./workfile.ts";
import { isSystemAgent } from "../core/system-agents.ts";
import {
  createCheckpoint,
  markCheckpointFailed,
  markStepCompleted,
  writeCheckpoint,
} from "../lifecycle/checkpoint.ts";
import { generateWorkflowId, persistWorkflow } from "../lifecycle/workflow.ts";

/**
 * 从 settings.json 读 defaultProvider + defaultModel，组合成完整 model ID。
 *
 * 用途：tier=inherit 的"跟随前台"实际解析。
 * 原实现是返回 []（不传 --model），导致 wrapper.sh 启动日志显示
 * "model: default"，与子进程实际推理用的 defaultModel 不一致。
 * 改为显式拼出 [provider/model]，让 wrapper 日志如实显示当前正在用的模型。
 *
 * @returns ["provider/model"] 成功；[] 解析失败兜底（保持原行为）
 */
export function readDefaultModelFromSettings(): string[] {
  // 复用 config.ts 的查找策略：agent dir → ~/.config/pi/
  const candidates = [
    path.join(getAgentDir(), "settings.json"),
    path.join(os.homedir(), ".config", "pi", "settings.json"),
  ];
  for (const p of candidates) {
    try {
      const raw = JSON.parse(fs.readFileSync(p, "utf8")) as Record<
        string,
        unknown
      >;
      const provider = raw.defaultProvider;
      const model = raw.defaultModel;
      if (
        typeof provider === "string" &&
        typeof model === "string" &&
        provider &&
        model
      ) {
        return [`${provider}/${model}`];
      }
    } catch {
      // 试下一个候选路径
      continue;
    }
  }
  return [];
}

// ─── Fallback 重试 ───────────────────────────────────────────────────────────

/** 同一任务最大重试次数（含首次尝试） */
const MAX_ATTEMPTS = 3;

/**
 * 解析 agent 的完整模型尝试链：[首选, ...fallback]
 *
 * 新优先级（自上而下短路）：
 *   1. 调用方显式覆盖（params.model）
 *   2. agent frontmatter `tier: inherit` → 从 settings.json 读 defaultProvider/defaultModel 组成 ["provider/model"]，让 wrapper 日志如实显示当前模型
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

  // inherit 特殊值：从 settings.json 解析出 [provider/model]，既让 wrapper 启动日志如实显示，也保证 model 链路非空（避免 fallback 重试时跳过 inherit）
  if (tier === "inherit") return readDefaultModelFromSettings();

  // 查 tiers 配置
  const tierCfg: AgentModelConfig | undefined = config.tiers[tier];
  if (!tierCfg) return []; // 未知 tier → 回退 []（让 subagent-wrapper 用自己的 defaultModel）

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
  // PR-9: 系统子 agent 透传。默认由 isSystemAgent(agent.name) 推断。
  isSystemSpawned?: boolean,
  // PR-10: chain/parallel 内的 parent run id(由 runChain/runParallelBatches 生成)
  parentRunId?: string,
): Promise<RunResult> {
  const resolvedSystem = isSystemSpawned ?? isSystemAgent(agent.name);
  const modelChain = resolveModelChain(agent, config, explicitModel);

  // 把 resolvedSystem 闭包到一个本地 helper 中,避免在两处 launchSingle 重复写 9 个参数
  const launchWith = (model: string | undefined) =>
    launchSingle(
      agent,
      task,
      config,
      cwd,
      model,
      topRowTargetPaneId,
      splitPercent ?? 50,
      images,
      resolvedSystem,
      parentRunId,
    );

  if (modelChain.length === 0) {
    const launch = launchWith(undefined);
    return waitForCompletion(launch, config, signal);
  }

  let lastResult: RunResult | undefined;
  const maxAttempts = Math.min(MAX_ATTEMPTS, modelChain.length);

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const launch = launchWith(modelChain[attempt]);
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

  // PR-10: 为整个 chain 生成一个 parentRunId；所有 step 的 registerRun 关联到此 id。
  // 同时创建 checkpoint（5 节格式 YAML）与 Workflow（PR-11 JSON）并持久化。
  const parentRunId = generateRunId();
  const intent = (rootTask ?? steps[0]?.task ?? "").slice(0, 200);

  let checkpoint: ReturnType<typeof createCheckpoint> | null = null;
  let workflow: import("./workflow.ts").Workflow | null = null;
  try {
    checkpoint = createCheckpoint(
      parentRunId,
      "chain",
      steps.map((s, idx) => ({
        id: `step-${idx + 1}`,
        agent: s.agent.name,
        task: s.task,
      })),
      intent,
    );
    writeCheckpoint(checkpoint, cwd);
  } catch (err) {
    console.warn(
      `[atelier:runner] chain ${parentRunId} createCheckpoint failed:`,
      err,
    );
    checkpoint = null;
  }
  try {
    workflow = {
      id: generateWorkflowId(),
      name: `chain-${parentRunId}`,
      mode: "chain",
      steps: steps.map((s, idx) => ({
        id: `step-${idx + 1}`,
        agent: s.agent.name,
        task: s.task,
        dependsOn: idx === 0 ? [] : [`step-${idx}`],
        status: "pending",
      })),
      context: { task: rootTask ?? "" },
      parentRunId,
    };
    persistWorkflow(workflow, cwd);
  } catch (err) {
    console.warn(
      `[atelier:runner] chain ${parentRunId} workflow persist failed:`,
      err,
    );
    workflow = null;
  }

  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    const task = step.task
      .replaceAll("{previous}", previous)
      .replaceAll("{task}", rootTask ?? previous);
    // 计算水平分割百分比，确保等分
    const pct = Math.round(((steps.length - i) / (steps.length - i + 1)) * 100);

    // 使用带 fallback 的执行（PR-10: 传入 parentRunId 关联到 atelier_runs.parent_run_id）
    const result = await executeWithFallback(
      step.agent,
      task,
      config,
      step.cwd ?? cwd,
      explicitModel,
      signal,
      topRowTargetPaneId,
      pct,
      undefined, // images
      undefined, // isSystemSpawned
      parentRunId,
    );

    // 验证 workfile
    if (result.status === "completed") {
      ensureWorkfile(result, cwd, startedAt);
    }

    // PR-10: 每完成一步写 checkpoint（写盘 + 更新 workflow 状态 + persist）
    if (checkpoint) {
      try {
        checkpoint = markStepCompleted(checkpoint, i, {
          runId: result.runId,
          workfilePath: result.workfilePath,
          outputPreview: result.output.slice(0, 500),
          inheritedContextForNext: previous.slice(0, 2000),
        });
        writeCheckpoint(checkpoint, cwd);
      } catch (err) {
        console.warn(
          `[atelier:runner] chain ${parentRunId} step ${i + 1} markStepCompleted failed:`,
          err,
        );
      }
    }
    if (workflow) {
      try {
        workflow.steps[i].status =
          result.status === "completed" ? "completed" : "failed";
        persistWorkflow(workflow, cwd);
      } catch (err) {
        console.warn(
          `[atelier:runner] chain ${parentRunId} workflow step ${i + 1} persist failed:`,
          err,
        );
      }
    }

    // 将 workfile 路径注入到下一步的上下文中
    let outputWithContext = result.output;
    if (result.workfilePath) {
      outputWithContext += `\n\n---\n上一步工作产物已持久化到: ${result.workfilePath}`;
    }

    results.push(result);
    previous = outputWithContext;
    if (result.status === "failed") {
      if (checkpoint) {
        try {
          checkpoint = markCheckpointFailed(
            checkpoint,
            i,
            result.error ?? "failed",
          );
          writeCheckpoint(checkpoint, cwd);
        } catch (err) {
          console.warn(
            `[atelier:runner] chain ${parentRunId} markCheckpointFailed failed:`,
            err,
          );
        }
      }
      break;
    }
  }

  return results;
}
