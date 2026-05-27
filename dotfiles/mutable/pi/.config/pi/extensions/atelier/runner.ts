// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 执行编排 — 三种运行模式的顶层协调逻辑
 *
 * - runParallelBatches: 并行执行（含并发限制和分批）
 * - runChain: 串行链式执行（{previous} 替换）
 */

import type { AgentConfig, RunResult, SubagentConfig } from "./types.ts";
import { launchParallel, launchSingle, paneIsAlive } from "./launcher.ts";
import { waitForAll, waitForCompletion } from "./monitor.ts";
import { ensureWorkfile } from "./workfile.ts";

/**
 * 并行执行多批任务，每批不超过 maxConcurrency。
 *
 * 布局效果（以 3 个任务为例）：
 *   ┌──────────┬──────────┬──────────┐
 *   │  task1   │  task2   │  task3   │   ← 上方行，水平等分
 *   ├──────────┴──────────┴──────────┤
 *   │  主 agent                       │
 *   └────────────────────────────────┘
 */
export async function runParallelBatches(
	tasks: Array<{ agent: AgentConfig; task: string; cwd?: string }>,
	config: SubagentConfig,
	cwd: string,
	model?: string,
	thinking?: string,
	signal?: AbortSignal,
): Promise<RunResult[]> {
	const results: RunResult[] = [];
	const concurrency = Math.max(1, Math.min(config.maxConcurrency, config.maxTasks));
	const startedAt = Date.now();
	let topRowTargetPaneId: string | undefined;

	for (let i = 0; i < tasks.length; i += concurrency) {
		const batch = tasks.slice(i, i + concurrency);
		// 如果上一个 batch 的 pane 已关闭，重置续接点，让 launchParallel 重新创建顶部行
		if (topRowTargetPaneId && !paneIsAlive(topRowTargetPaneId)) {
			topRowTargetPaneId = undefined;
		}
		const launches = launchParallel(batch, config, model, thinking, topRowTargetPaneId);
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

/**
 * 串行执行任务链。
 *
 * 每步的 task 中的 {previous} 被替换为上一步的输出，
 * {task} 被替换为根任务。
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
	model?: string,
	thinking?: string,
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
		const launch = launchSingle(
			step.agent,
			task,
			config,
			step.cwd ?? cwd,
			model,
			thinking,
			topRowTargetPaneId,
			pct,
		);
		topRowTargetPaneId = launch.paneId;
		const result = await waitForCompletion(launch, config, signal);

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
