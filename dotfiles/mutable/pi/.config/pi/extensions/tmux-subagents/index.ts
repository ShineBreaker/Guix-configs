/**
 * tmux-subagents extension
 *
 * 通过 tmux 分屏可视化执行 subagent 任务，替代 npm:pi-subagents。
 *
 * 模式：
 *   - single: { agent: "name", task: "..." }
 *   - parallel: { tasks: [{ agent: "name", task: "..." }, ...] }
 *   - list: { action: "list" }
 *   - status: { action: "status" [, id: "run-id"] }
 */

import { execSync } from "node:child_process";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { AgentToolResult, ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getAgentDir, parseFrontmatter } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

// ─── Types ────────────────────────────────────────────────────────────────

interface AgentConfig {
	name: string;
	description: string;
	tools?: string[];
	model?: string;
	thinking?: string;
	systemPrompt: string;
	filePath: string;
}

interface SubagentConfig {
	pollIntervalMs: number;
	panePrefix: string;
	keepResults: number;
}

interface LaunchResult {
	runId: string;
	runDir: string;
	paneId: string;
	paneTitle: string;
}

interface RunResult {
	runId: string;
	agent: string;
	status: "completed" | "failed";
	exitCode: number;
	output: string;
	durationMs: number;
	tmuxPane: string;
}

interface SubagentDetails {
	mode: "single" | "parallel" | "list" | "status";
	results: RunResult[];
}

interface StatusFile {
	status: "running" | "completed" | "failed";
	exitCode?: number;
	finishedAt?: number;
	startedAt?: number;
}

const DEFAULT_CONFIG: SubagentConfig = {
	pollIntervalMs: 2000,
	panePrefix: "sub:",
	keepResults: 24,
};

// ─── XDG Paths ────────────────────────────────────────────────────────────

function resolveXdgCache(): string {
	return process.env.XDG_CACHE_HOME ?? path.join(os.homedir(), ".cache");
}

function resolveXdgData(): string {
	return process.env.XDG_DATA_HOME ?? path.join(os.homedir(), ".local", "share");
}

function getSubagentsDir(): string {
	return path.join(resolveXdgCache(), "pi", "subagents");
}

function getRunDir(runId: string): string {
	return path.join(getSubagentsDir(), runId);
}

function getScriptsDir(): string {
	return path.join(resolveXdgData(), "pi", "scripts");
}

// ─── Config ───────────────────────────────────────────────────────────────

function loadConfig(settings: Record<string, unknown>): SubagentConfig {
	const raw = settings.tmuxSubagents as Record<string, unknown> | undefined;
	if (!raw) return DEFAULT_CONFIG;
	return {
		pollIntervalMs: typeof raw.pollIntervalMs === "number" ? raw.pollIntervalMs : DEFAULT_CONFIG.pollIntervalMs,
		panePrefix: typeof raw.panePrefix === "string" ? raw.panePrefix : DEFAULT_CONFIG.panePrefix,
		keepResults: typeof raw.keepResults === "number" ? raw.keepResults : DEFAULT_CONFIG.keepResults,
	};
}

// ─── Agent Discovery ──────────────────────────────────────────────────────

function discoverAgents(): AgentConfig[] {
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

		const { frontmatter, body } = parseFrontmatter<Record<string, string>>(content);
		if (!frontmatter.name || !frontmatter.description) continue;

		const tools = frontmatter.tools
			?.split(",")
			.map((t: string) => t.trim())
			.filter(Boolean);

		agents.push({
			name: frontmatter.name,
			description: frontmatter.description,
			tools: tools && tools.length > 0 ? tools : undefined,
			model: frontmatter.model,
			thinking: frontmatter.thinking,
			systemPrompt: body,
			filePath,
		});
	}

	return agents;
}

// ─── Launcher ─────────────────────────────────────────────────────────────

function generateRunId(): string {
	return `sa-${Date.now().toString(36)}-${crypto.randomBytes(3).toString("hex")}`;
}

function tmuxExec(cmd: string): string {
	return execSync(`tmux ${cmd}`, { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }).trim();
}

function prepareRunDir(runDir: string, task: string): void {
	fs.mkdirSync(runDir, { recursive: true });
	fs.writeFileSync(path.join(runDir, "task.md"), task, "utf-8");
	fs.writeFileSync(
		path.join(runDir, "status.json"),
		JSON.stringify({ status: "running", startedAt: Date.now() }),
		"utf-8",
	);
}

function buildWrapperCmd(
	runId: string,
	agent: AgentConfig,
	runDir: string,
	cwd?: string,
	model?: string,
	thinking?: string,
): string {
	const wrapper = path.join(getScriptsDir(), "subagent-wrapper.sh");
	const args: string[] = [runId, agent.name, path.join(runDir, "task.md")];
	const effectiveModel = model ?? agent.model;
	if (effectiveModel) args.push("--model", effectiveModel);
	if (thinking ?? agent.thinking) args.push("--thinking", (thinking ?? agent.thinking)!);
	if (cwd) args.push("--cwd", cwd);
	const escapedArgs = args.map((a) => `'${a.replace(/'/g, "'\\''")}'`).join(" ");
	return `${wrapper} ${escapedArgs}`;
}

function launchSingle(
	agent: AgentConfig,
	task: string,
	config: SubagentConfig,
	cwd?: string,
	model?: string,
	thinking?: string,
): LaunchResult {
	if (!process.env.TMUX) {
		throw new Error("tmux-subagents requires Pi to run inside a tmux session");
	}

	const myPaneId = tmuxExec("display-message -p '#{pane_id}'");
	const runId = generateRunId();
	const runDir = getRunDir(runId);
	prepareRunDir(runDir, task);

	const paneTitle = `${config.panePrefix}${agent.name}`;
	const cmd = buildWrapperCmd(runId, agent, runDir, cwd, model, thinking);

	const paneId = tmuxExec(`split-window -h -p 50 -P -F '#{pane_id}' ${cmd}`);
	tmuxExec(`select-pane -t ${paneId} -T "${paneTitle}"`);
	tmuxExec(`select-pane -t ${myPaneId}`);

	return { runId, runDir, paneId, paneTitle };
}

function launchParallel(
	tasks: Array<{ agent: AgentConfig; task: string; cwd?: string }>,
	config: SubagentConfig,
	model?: string,
	thinking?: string,
): LaunchResult[] {
	if (!process.env.TMUX) {
		throw new Error("tmux-subagents requires Pi to run inside a tmux session");
	}

	const myPaneId = tmuxExec("display-message -p '#{pane_id}'");
	const results: LaunchResult[] = [];
	const count = tasks.length;

	for (let i = 0; i < count; i++) {
		const { agent, task, cwd } = tasks[i];
		const runId = generateRunId();
		const runDir = getRunDir(runId);
		prepareRunDir(runDir, task);

		const agentCountForName = tasks.filter((t, j) => j <= i && t.agent.name === agent.name).length;
		const paneTitle =
			tasks.filter((t) => t.agent.name === agent.name).length > 1
				? `${config.panePrefix}${agent.name}:${agentCountForName}`
				: `${config.panePrefix}${agent.name}`;

		const cmd = buildWrapperCmd(runId, agent, runDir, cwd, model, thinking);

		let paneId: string;
		if (i === 0) {
			const pct = Math.max(10, Math.round(((count - i) / (count + 1)) * 100));
			paneId = tmuxExec(`split-window -h -p ${pct} -P -F '#{pane_id}' ${cmd}`);
		} else {
			paneId = tmuxExec(
				`split-window -t ${results[i - 1].paneId} -v -p 50 -P -F '#{pane_id}' ${cmd}`,
			);
		}

		tmuxExec(`select-pane -t ${paneId} -T "${paneTitle}"`);
		results.push({ runId, runDir, paneId, paneTitle });
	}

	tmuxExec(`select-pane -t ${myPaneId}`);
	return results;
}

// ─── Monitor ──────────────────────────────────────────────────────────────

function readStatus(runDir: string): StatusFile | null {
	const statusPath = path.join(runDir, "status.json");
	try {
		return JSON.parse(fs.readFileSync(statusPath, "utf-8"));
	} catch {
		return null;
	}
}

function readResult(runDir: string): string {
	const resultPath = path.join(runDir, "result.md");
	try {
		return fs.readFileSync(resultPath, "utf-8");
	} catch {
		return "(no output)";
	}
}

async function waitForCompletion(
	launch: LaunchResult,
	config: SubagentConfig,
	signal?: AbortSignal,
): Promise<RunResult> {
	const startedAt = Date.now();

	return new Promise<RunResult>((resolve) => {
		const interval = setInterval(() => {
			if (signal?.aborted) {
				clearInterval(interval);
				resolve({
					runId: launch.runId,
					agent: launch.paneTitle.replace(config.panePrefix, ""),
					status: "failed",
					exitCode: -1,
					output: "Aborted",
					durationMs: Date.now() - startedAt,
					tmuxPane: launch.paneTitle,
				});
				return;
			}

			const status = readStatus(launch.runDir);
			if (status && status.status !== "running") {
				clearInterval(interval);
				const output = readResult(launch.runDir);
				resolve({
					runId: launch.runId,
					agent: launch.paneTitle.replace(config.panePrefix, ""),
					status: status.status,
					exitCode: status.exitCode ?? 1,
					output,
					durationMs: (status.finishedAt ?? Date.now()) - (status.startedAt ?? startedAt),
					tmuxPane: launch.paneTitle,
				});
			}
		}, config.pollIntervalMs);
	});
}

function waitForAll(
	launches: LaunchResult[],
	config: SubagentConfig,
	signal?: AbortSignal,
): Promise<RunResult[]> {
	return Promise.all(launches.map((l) => waitForCompletion(l, config, signal)));
}

function listRunning(): RunResult[] {
	const subagentsDir = getSubagentsDir();
	if (!fs.existsSync(subagentsDir)) return [];

	const results: RunResult[] = [];
	for (const entry of fs.readdirSync(subagentsDir)) {
		const runDir = path.join(subagentsDir, entry);
		const status = readStatus(runDir);
		if (!status || status.status !== "running") continue;

		let task = "";
		try {
			task = fs.readFileSync(path.join(runDir, "task.md"), "utf-8");
		} catch {
			/* ignore */
		}

		results.push({
			runId: entry,
			agent: "(unknown)",
			status: "running",
			exitCode: -1,
			output: task.slice(0, 200),
			durationMs: Date.now() - (status.startedAt ?? Date.now()),
			tmuxPane: "",
		});
	}
	return results;
}

// ─── Formatting ───────────────────────────────────────────────────────────

function formatResult(r: RunResult): string {
	const icon = r.status === "completed" ? "✓" : "✗";
	return `### [${r.agent}] ${icon} (${r.durationMs}ms)\n\n${r.output}`;
}

function formatResults(results: RunResult[]): string {
	const success = results.filter((r) => r.status === "completed").length;
	return `${success}/${results.length} succeeded\n\n${results.map(formatResult).join("\n\n---\n\n")}`;
}

// ─── Extension Entry ──────────────────────────────────────────────────────

const TaskItem = Type.Object({
	agent: Type.String({ description: "Agent 名称" }),
	task: Type.String({ description: "任务描述" }),
	cwd: Type.Optional(Type.String({ description: "工作目录" })),
});

const SubagentParams = Type.Object({
	agent: Type.Optional(Type.String({ description: "Agent 名称（single 模式）" })),
	task: Type.Optional(Type.String({ description: "任务描述（single 模式）" })),
	tasks: Type.Optional(Type.Array(TaskItem, { description: "并行任务数组" })),
	action: Type.Optional(
		Type.Union([Type.Literal("list"), Type.Literal("status")], { description: "管理动作" }),
	),
	id: Type.Optional(Type.String({ description: "查看指定 run-id 的状态" })),
	cwd: Type.Optional(Type.String({ description: "工作目录覆盖" })),
	model: Type.Optional(Type.String({ description: "模型覆盖" })),
	thinking: Type.Optional(
		Type.Union([Type.Literal("low"), Type.Literal("medium"), Type.Literal("high")], {
			description: "思考级别",
		}),
	),
});

export default function (pi: ExtensionAPI) {
	const config = loadConfig((pi.settings as Record<string, unknown>) ?? {});

	pi.registerTool({
		name: "subagent",
		label: "Subagent",
		description: [
			"通过 tmux 分屏可视化执行 subagent 任务。",
			"模式：single (agent + task)、parallel (tasks 数组)。",
			"管理：action: list 列出可用 agent，action: status 查看运行状态。",
		].join(" "),
		parameters: SubagentParams,

		async execute(_toolCallId, params, signal, _onUpdate, ctx): Promise<AgentToolResult<SubagentDetails>> {
			const agents = discoverAgents();
			const makeDetails =
				(mode: "single" | "parallel" | "list" | "status") =>
				(results: RunResult[]): SubagentDetails => ({ mode, results });

			if (params.action === "list") {
				const list = agents.map((a) => `- **${a.name}**: ${a.description}`).join("\n");
				return {
					content: [{ type: "text", text: list || "无可用 agent" }],
					details: makeDetails("list")([]),
				};
			}

			if (params.action === "status") {
				if (params.id) {
					const runDir = getRunDir(params.id);
					let statusJson: Record<string, unknown>;
					try {
						statusJson = JSON.parse(fs.readFileSync(path.join(runDir, "status.json"), "utf-8"));
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
				const lines = running.map((r) => `- **${r.runId}**: ${r.output.slice(0, 80)}...`);
				return {
					content: [{ type: "text", text: lines.join("\n") }],
					details: makeDetails("status")(running),
				};
			}

			if (params.tasks && params.tasks.length > 0) {
				const taskEntries: Array<{ agent: AgentConfig; task: string; cwd?: string }> = [];
				for (const t of params.tasks) {
					const agent = agents.find((a) => a.name === t.agent);
					if (!agent) {
						const available = agents.map((a) => a.name).join(", ") || "none";
						return {
							content: [{ type: "text", text: `未知 agent: "${t.agent}"。可用: ${available}` }],
							details: makeDetails("parallel")([]),
						};
					}
					taskEntries.push({ agent, task: t.task, cwd: t.cwd });
				}

				try {
					const launches = launchParallel(taskEntries, config, params.model, params.thinking);
					const results = await waitForAll(launches, config, signal);
					return {
						content: [{ type: "text", text: formatResults(results) }],
						details: makeDetails("parallel")(results),
					};
				} catch (err) {
					return {
						content: [{ type: "text", text: `启动失败: ${(err as Error).message}` }],
						details: makeDetails("parallel")([]),
						isError: true,
					};
				}
			}

			if (params.agent && params.task) {
				const agent = agents.find((a) => a.name === params.agent);
				if (!agent) {
					const available = agents.map((a) => a.name).join(", ") || "none";
					return {
						content: [{ type: "text", text: `未知 agent: "${params.agent}"。可用: ${available}` }],
						details: makeDetails("single")([]),
					};
				}

				try {
					const launch = launchSingle(agent, params.task, config, params.cwd, params.model, params.thinking);
					const result = await waitForCompletion(launch, config, signal);
					return {
						content: [{ type: "text", text: result.output }],
						details: makeDetails("single")([result]),
						isError: result.status === "failed" || undefined,
					};
				} catch (err) {
					return {
						content: [{ type: "text", text: `启动失败: ${(err as Error).message}` }],
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
}
