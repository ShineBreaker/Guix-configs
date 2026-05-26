// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * tmux-subagents 扩展入口
 *
 * 通过 tmux 分屏可视化执行 subagent 任务。
 *
 * 模式：
 *   - single: { agent: "name", task: "..." }
 *   - parallel: { tasks: [{ agent: "name", task: "..." }, ...] }
 *   - chain: { chain: [{ agent: "name", task: "..." }, ...] }
 *   - list: { action: "list" }
 *   - status: { action: "status" [, id: "run-id"] }
 *
 * 快捷命令：
 *   - /agentname <task>     — 启动单个 agent
 *   - /<prompt-name> <param> — 按 prompt 模板启动链路
 *
 * 文件拆分：
 *   types.ts       — 接口和常量
 *   config.ts      — 配置加载
 *   discovery.ts   — Agent 和 Prompt 发现
 *   workfile.ts    — Workfile 持久化
 *   launcher.ts    — Tmux 分屏启动
 *   monitor.ts     — 运行监控
 *   runner.ts      — 执行编排
 *   formatting.ts  — 结果格式化
 *   schemas.ts     — 参数 Schema
 */

import * as fs from "node:fs";
import * as path from "node:path";
import type { AgentToolResult, ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { AgentConfig, RunResult, SubagentDetails } from "./types.ts";
import { loadConfig } from "./config.ts";
import { discoverAgents, discoverPrompts } from "./discovery.ts";
import { ensureWorkfile } from "./workfile.ts";
import { getRunDir, launchSingle } from "./launcher.ts";
import { waitForCompletion, listRunning } from "./monitor.ts";
import { runParallelBatches, runChain } from "./runner.ts";
import { formatResults } from "./formatting.ts";
import { SubagentParams } from "./schemas.ts";

// ─── Plan Review Gate 提示词 ─────────────────────────────────────────────────

const PLAN_REVIEW_GATE_PROMPT = [
	"📋 提交前需要先让 planner 审查计划。",
	"请调用 subagent 工具：",
	'  subagent(agent: "planner", task: "审查实施计划...")',
	"",
	"审查任务内容：",
	"请审查以下实施计划，从架构合理性、完整性、风险和遗漏角度给出评估。",
	"如果计划整体可行只需指出小问题；如果存在重大缺陷请详细说明。",
	"计划文件路径：" /* + planFilePath */,
	"",
	"审查完成后，如果计划需要修改请修改后再提交。",
	"如果计划已通过审查，直接再次调用 plannotator_submit_plan 即可（不会再次被阻止）。",
].join("\n");

// ─── 辅助函数 ────────────────────────────────────────────────────────────────

/** 创建 makeDetails 工厂 */
const makeDetails =
	(mode: "single" | "parallel" | "chain" | "list" | "status") =>
	(results: RunResult[]): SubagentDetails => ({ mode, results });

// ─── Extension Entry ─────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
	const config = loadConfig();

	// ── 注册 subagent 工具 ──────────────────────────────────────────────────

	pi.registerTool({
		name: "subagent",
		label: "Subagent",
		description: [
			"通过 tmux 分屏可视化执行 subagent 任务。",
			"模式：single (agent + task)、parallel (tasks 数组)、chain (chain 数组)。",
			"管理：action: list 列出可用 agent 和 prompt 模板，action: status 查看运行状态。",
		].join(" "),
		parameters: SubagentParams,

		async execute(
			_toolCallId,
			params,
			signal,
			_onUpdate,
			_ctx,
		): Promise<AgentToolResult<SubagentDetails>> {
			const agents = discoverAgents();
			const prompts = discoverPrompts();
			const effectiveCwd = params.cwd ?? process.cwd();

			// ── action: list ─────────────────────────────────────────────────

			if (params.action === "list") {
				const agentLines = agents
					.map((a) => {
						const tools = a.tools ? a.tools.join(", ") : "all";
						const model = a.model ?? "default";
						return `| ${a.name} | ${a.description.slice(0, 40)}… | ${tools} | ${model} |`;
					})
					.join("\n");
				const promptLines = prompts
					.map(
						(p) =>
							`| ${p.name} | ${p.mode} | ${p.description.slice(0, 40)}… | /${p.name} <${p.param}> |`,
					)
					.join("\n");
				const list = [
					"## Agents",
					"| Name | Description | Tools | Model |",
					"|------|-------------|-------|-------|",
					agentLines || "| (none) | | | |",
					"",
					"## Prompt Templates",
					"| Name | Mode | Description | Usage |",
					"|------|------|-------------|-------|",
					promptLines || "| (none) | | | |",
				].join("\n");
				return {
					content: [{ type: "text", text: list }],
					details: makeDetails("list")([]),
				};
			}

			// ── action: status ───────────────────────────────────────────────

			if (params.action === "status") {
				if (params.id) {
					const runDir = getRunDir(params.id);
					let statusJson: Record<string, unknown>;
					try {
						statusJson = JSON.parse(
							fs.readFileSync(path.join(runDir, "status.json"), "utf-8"),
						);
					} catch {
						return {
							content: [{ type: "text", text: `未找到 run: ${params.id}` }],
							details: makeDetails("status")([]),
						};
					}
					return {
						content: [{ type: "text", text: JSON.stringify(statusJson, null, 2) }],
						details: makeDetails("status")([]),
					};
				}

				const running = listRunning();
				if (running.length === 0) {
					return {
						content: [{ type: "text", text: "无运行中的 subagent" }],
						details: makeDetails("status")([]),
					};
				}
				const lines = running.map(
					(r) => `- **${r.runId}**: ${r.output.slice(0, 80)}...`,
				);
				return {
					content: [{ type: "text", text: lines.join("\n") }],
					details: makeDetails("status")(running),
				};
			}

			// ── chain 模式 ──────────────────────────────────────────────────

			if (params.chain && params.chain.length > 0) {
				if (params.chain.length > config.maxTasks) {
					return {
						content: [
							{
								type: "text",
								text: `chain 任务数 ${params.chain.length} 超过上限 ${config.maxTasks}`,
							},
						],
						details: makeDetails("chain")([]),
						isError: true,
					};
				}

				const chainEntries: Array<{
					agent: AgentConfig;
					task: string;
					cwd?: string;
				}> = [];
				for (const t of params.chain) {
					const agent = agents.find((a) => a.name === t.agent);
					if (!agent) {
						const available = agents.map((a) => a.name).join(", ") || "none";
						return {
							content: [
								{
									type: "text",
									text: `未知 agent: "${t.agent}"。可用: ${available}`,
								},
							],
							details: makeDetails("chain")([]),
						};
					}
					chainEntries.push({ agent, task: t.task, cwd: params.cwd });
				}

				try {
					const results = await runChain(
						chainEntries,
						config,
						effectiveCwd,
						params.task,
						params.model,
						params.thinking,
						signal,
					);
					return {
						content: [{ type: "text", text: formatResults(results) }],
						details: makeDetails("chain")(results),
						isError: results.some((r) => r.status === "failed") || undefined,
					};
				} catch (err) {
					return {
						content: [
							{ type: "text", text: `启动失败: ${(err as Error).message}` },
						],
						details: makeDetails("chain")([]),
						isError: true,
					};
				}
			}

			// ── parallel 模式 ───────────────────────────────────────────────

			if (params.tasks && params.tasks.length > 0) {
				if (params.tasks.length > config.maxTasks) {
					return {
						content: [
							{
								type: "text",
								text: `parallel 任务数 ${params.tasks.length} 超过上限 ${config.maxTasks}`,
							},
						],
						details: makeDetails("parallel")([]),
						isError: true,
					};
				}

				const taskEntries: Array<{
					agent: AgentConfig;
					task: string;
					cwd?: string;
				}> = [];
				for (const t of params.tasks) {
					const agent = agents.find((a) => a.name === t.agent);
					if (!agent) {
						const available = agents.map((a) => a.name).join(", ") || "none";
						return {
							content: [
								{
									type: "text",
									text: `未知 agent: "${t.agent}"。可用: ${available}`,
								},
							],
							details: makeDetails("parallel")([]),
						};
					}
					taskEntries.push({ agent, task: t.task, cwd: params.cwd });
				}

				try {
					const results = await runParallelBatches(
						taskEntries,
						config,
						effectiveCwd,
						params.model,
						params.thinking,
						signal,
					);
					return {
						content: [{ type: "text", text: formatResults(results) }],
						details: makeDetails("parallel")(results),
						isError: results.some((r) => r.status === "failed") || undefined,
					};
				} catch (err) {
					return {
						content: [
							{ type: "text", text: `启动失败: ${(err as Error).message}` },
						],
						details: makeDetails("parallel")([]),
						isError: true,
					};
				}
			}

			// ── single 模式 ─────────────────────────────────────────────────

			if (params.agent && params.task) {
				const agent = agents.find((a) => a.name === params.agent);
				if (!agent) {
					const available = agents.map((a) => a.name).join(", ") || "none";
					return {
						content: [
							{
								type: "text",
								text: `未知 agent: "${params.agent}"。可用: ${available}`,
							},
						],
						details: makeDetails("single")([]),
					};
				}

				try {
					const startedAt = Date.now();
					const launch = launchSingle(
						agent,
						params.task,
						config,
						params.cwd,
						params.model,
						params.thinking,
					);
					const result = await waitForCompletion(launch, config, signal);
					if (result.status === "completed") {
						ensureWorkfile(result, effectiveCwd, startedAt);
					}
					return {
						content: [{ type: "text", text: result.output }],
						details: makeDetails("single")([result]),
						isError: result.status === "failed" || undefined,
					};
				} catch (err) {
					return {
						content: [
							{ type: "text", text: `启动失败: ${(err as Error).message}` },
						],
						details: makeDetails("single")([]),
						isError: true,
					};
				}
			}

			const available = agents.map((a) => a.name).join(", ") || "none";
			return {
				content: [{ type: "text", text: `参数无效。可用 agent: ${available}` }],
				details: makeDetails("single")([]),
			};
		},
	});

	// ── 为每个 agent 注册 /agentname 快捷命令 ──────────────────────────────

	const agents = discoverAgents();
	for (const agent of agents) {
		pi.registerCommand(agent.name, {
			description: `${agent.description}（/${agent.name} <任务描述>）`,
			handler: async (args, ctx) => {
				const task = args.trim();
				if (!task) {
					ctx.ui.notify(
						`用法: /${agent.name} <任务描述>\n例: /${agent.name} 审查当前修改的代码`,
						"warn",
					);
					return;
				}

				try {
					const startedAt = Date.now();
					const launch = launchSingle(
						agent,
						task,
						config,
						ctx.cwd,
						agent.model,
						agent.thinking,
					);
					ctx.ui.notify(`⏳ ${agent.name} 已启动 (run: ${launch.runId})...`, "info");
					const result = await waitForCompletion(launch, config);
					if (result.status === "completed") {
						ensureWorkfile(result, ctx.cwd, startedAt);
						const workfileNote = result.workfilePath
							? `\n📄 ${result.workfilePath}`
							: "";
						ctx.ui.notify(
							`✅ ${agent.name} 完成 (${(result.durationMs / 1000).toFixed(1)}s)${workfileNote}\n\n${result.output.slice(0, 4000)}${result.output.length > 4000 ? "\n...（截断）" : ""}`,
							"info",
						);
					} else {
						ctx.ui.notify(
							`❌ ${agent.name} 失败 (run: ${launch.runId}): ${result.error ?? "未知错误"}`,
							"error",
						);
					}
				} catch (err) {
					ctx.ui.notify(
						`启动 ${agent.name} 失败: ${(err as Error).message}`,
						"error",
					);
				}
			},
		});
	}

	// ── 为每个 prompt 模板注册快捷命令 ─────────────────────────────────────

	const prompts = discoverPrompts();
	const agentNames = new Set(agents.map((a) => a.name));
	for (const prompt of prompts) {
		if (agentNames.has(prompt.name)) continue; // 与 agent 命令冲突，跳过
		pi.registerCommand(prompt.name, {
			description: `${prompt.description}（/${prompt.name} <${prompt.param}>）`,
			handler: async (args, ctx) => {
				const paramValue = args.trim();
				if (!paramValue) {
					ctx.ui.notify(
						`用法: /${prompt.name} <${prompt.param}>\n例: /${prompt.name} 重构认证模块`,
						"warn",
					);
					return;
				}

				// 替换模板中的占位符
				const resolvedEntries = prompt.entries.map((e) => ({
					agent: e.agent,
					task: e.task.replaceAll(`{${prompt.param}}`, paramValue),
				}));

				try {
					let results: RunResult[];

					if (prompt.mode === "chain") {
						const chainEntries = resolvedEntries.map((e) => {
							const agent = agents.find((a) => a.name === e.agent);
							if (!agent) throw new Error(`未知 agent: ${e.agent}`);
							return { agent, task: e.task };
						});
						results = await runChain(chainEntries, config, ctx.cwd, paramValue);
					} else if (prompt.mode === "parallel") {
						const taskEntries = resolvedEntries.map((e) => {
							const agent = agents.find((a) => a.name === e.agent);
							if (!agent) throw new Error(`未知 agent: ${e.agent}`);
							return { agent, task: e.task };
						});
						results = await runParallelBatches(taskEntries, config, ctx.cwd);
					} else {
						const e = resolvedEntries[0];
						const agent = agents.find((a) => a.name === e.agent);
						if (!agent) throw new Error(`未知 agent: ${e.agent}`);
						const launch = launchSingle(agent, e.task, config, ctx.cwd);
						const result = await waitForCompletion(launch, config);
						results = [result];
					}

					const success = results.filter((r) => r.status === "completed").length;
					ctx.ui.notify(
						`${prompt.name}: ${success}/${results.length} 成功\n\n${formatResults(results).slice(0, 4000)}`,
						success === results.length ? "info" : "warn",
					);
				} catch (err) {
					ctx.ui.notify(
						`启动 ${prompt.name} 失败: ${(err as Error).message}`,
						"error",
					);
				}
			},
		});
	}

	// ── Plan review gate ──────────────────────────────────────────────────

	{
		const reviewedPlans = new Set<string>();
		pi.on("tool_call", async (event, _ctx) => {
			if (event.toolName !== "plannotator_submit_plan") return;
			const planFilePath = event.input?.filePath as string | undefined;
			if (!planFilePath) return;
			if (reviewedPlans.has(planFilePath)) {
				reviewedPlans.delete(planFilePath);
				return;
			}
			reviewedPlans.add(planFilePath);
			return {
				block: true,
				reason: PLAN_REVIEW_GATE_PROMPT + planFilePath,
			};
		});
		pi.on("session_shutdown", () => {
			reviewedPlans.clear();
		});
	}
}
