// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * tmux-subagents extension
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
 */

import { execFileSync } from "node:child_process";
import * as crypto from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
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

interface PromptConfig {
	name: string;
	mode: "single" | "parallel" | "chain";
	param: string;
	description: string;
	/** 解析后的 task 列表 */
	entries: Array<{ agent: string; task: string }>;
}

interface SubagentConfig {
	pollIntervalMs: number;
	panePrefix: string;
	keepResults: number;
	timeoutMs: number;
	maxTasks: number;
	maxConcurrency: number;
}

interface LaunchResult {
	runId: string;
	runDir: string;
	paneId: string;
	paneTitle: string;
	agent: AgentConfig;
}

interface RunResult {
	runId: string;
	agent: string;
	status: "completed" | "failed";
	exitCode: number;
	output: string;
	durationMs: number;
	tmuxPane: string;
	error?: string;
	workfilePath?: string;
}

interface SubagentDetails {
	mode: "single" | "parallel" | "chain" | "list" | "status";
	results: RunResult[];
}

interface StatusFile {
	status: "running" | "completed" | "failed";
	exitCode?: number;
	finishedAt?: number;
	startedAt?: number;
	error?: string;
}

// ─── Constants ────────────────────────────────────────────────────────────

const DEFAULT_CONFIG: SubagentConfig = {
	pollIntervalMs: 2000,
	panePrefix: "sub:",
	keepResults: 24,
	timeoutMs: 30 * 60 * 1000,
	maxTasks: 8,
	maxConcurrency: 4,
};

const TOP_ROW_PERCENT = "40";

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

function loadConfig(): SubagentConfig {
	const candidates = [
		path.join(getAgentDir(), "settings.json"),
		path.join(os.homedir(), ".config", "pi", "settings.json"),
	];

	let raw: Record<string, unknown> | undefined;
	for (const settingsPath of candidates) {
		if (!existsSync(settingsPath)) continue;
		try {
			raw = JSON.parse(readFileSync(settingsPath, "utf8"))?.tmuxSubagents as Record<string, unknown> | undefined;
			if (raw) break;
		} catch {
			continue;
		}
	}

	if (!raw) return DEFAULT_CONFIG;
	return {
		pollIntervalMs: typeof raw.pollIntervalMs === "number" ? raw.pollIntervalMs : DEFAULT_CONFIG.pollIntervalMs,
		panePrefix: typeof raw.panePrefix === "string" ? raw.panePrefix : DEFAULT_CONFIG.panePrefix,
		keepResults: typeof raw.keepResults === "number" ? raw.keepResults : DEFAULT_CONFIG.keepResults,
		timeoutMs: typeof raw.timeoutMs === "number" ? raw.timeoutMs : DEFAULT_CONFIG.timeoutMs,
		maxTasks: typeof raw.maxTasks === "number" ? raw.maxTasks : DEFAULT_CONFIG.maxTasks,
		maxConcurrency:
			typeof raw.maxConcurrency === "number" ? raw.maxConcurrency : DEFAULT_CONFIG.maxConcurrency,
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

// ─── Prompt Discovery ─────────────────────────────────────────────────────

/** 解析 prompt 文件的 frontmatter（跳过 SPDX 注释块，不依赖 parseFrontmatter 的文件起始约束） */
function parsePromptFrontmatter(content: string): { frontmatter: Record<string, string>; body: string } | null {
	// 跳过开头的 HTML 注释块（SPDX 头）
	let offset = 0;
	if (content.startsWith("<!--")) {
		const closeIdx = content.indexOf("-->");
		if (closeIdx >= 0) offset = closeIdx + 3;
	}
	// 跳过空白
	while (offset < content.length && /\s/.test(content[offset])) offset++;

	// 检查 frontmatter
	if (!content.startsWith("---", offset)) return null;
	const fmStart = offset + 3;
	const fmEnd = content.indexOf("\n---", fmStart);
	if (fmEnd < 0) return null;

	const fmText = content.slice(fmStart, fmEnd);
	const frontmatter: Record<string, string> = {};
	for (const line of fmText.split("\n")) {
		const m = line.match(/^(\w+):\s*(.*)/);
		if (m) frontmatter[m[1]] = m[2].trim();
	}

	const body = content.slice(fmEnd + 4); // skip \n---\n
	return { frontmatter, body };
}

function discoverPrompts(): PromptConfig[] {
	const promptsDir = path.join(getAgentDir(), "prompts");
	const prompts: PromptConfig[] = [];

	if (!fs.existsSync(promptsDir)) return prompts;

	let entries: fs.Dirent[];
	try {
		entries = fs.readdirSync(promptsDir, { withFileTypes: true });
	} catch {
		return prompts;
	}

	for (const entry of entries) {
		if (!entry.name.endsWith(".md")) continue;
		if (!entry.isFile() && !entry.isSymbolicLink()) continue;

		const filePath = path.join(promptsDir, entry.name);
		let content: string;
		try {
			content = fs.readFileSync(filePath, "utf-8");
		} catch {
			continue;
		}

		const parsed = parsePromptFrontmatter(content);
		if (!parsed || !parsed.frontmatter.name || !parsed.frontmatter.mode) continue;

		const mode = parsed.frontmatter.mode as "single" | "parallel" | "chain";
		if (!["single", "parallel", "chain"].includes(mode)) continue;

		// 从 body 中提取第一个 JSON 代码块
		const jsonMatch = parsed.body.match(/```json\s*\n([\s\S]*?)\n```/);
		if (!jsonMatch) continue;

		let template: Record<string, unknown>;
		try {
			template = JSON.parse(jsonMatch[1]);
		} catch {
			continue;
		}

		// 从 JSON 模板中提取 entries
		const promptEntries: Array<{ agent: string; task: string }> = [];
		const items = (template.chain ?? template.tasks ?? [template]) as Array<Record<string, string>>;
		for (const item of items) {
			if (item.agent && item.task) {
				promptEntries.push({ agent: item.agent, task: item.task });
			}
		}

		if (promptEntries.length === 0) continue;

		prompts.push({
			name: parsed.frontmatter.name,
			mode,
			param: parsed.frontmatter.param ?? "task",
			description: parsed.frontmatter.description ?? "",
			entries: promptEntries,
		});
	}

	return prompts;
}

// ─── Workfile Helpers ──────────────────────────────────────────────────────

function getWorkfileDir(cwd: string, agentName: string): string {
	return path.join(cwd, ".agents", "workfile", agentName);
}

function generateWorkfileName(): string {
	const date = new Date().toISOString().slice(0, 10);
	const hash = crypto.randomBytes(2).toString("hex");
	return `${date}-${hash}.md`;
}

/** 将 agent 运行结果持久化到 .agents/workfile/{agent}/ 目录 */
function persistToWorkfile(cwd: string, agentName: string, content: string): string | undefined {
	try {
		const dir = getWorkfileDir(cwd, agentName);
		fs.mkdirSync(dir, { recursive: true });
		const fileName = generateWorkfileName();
		const filePath = path.join(dir, fileName);
		fs.writeFileSync(filePath, content, "utf-8");
		return path.relative(cwd, filePath);
	} catch {
		return undefined;
	}
}

/** 检查 agent 是否已通过 write 工具自行写入了 workfile（对比任务开始时间） */
function checkWorkfileExists(cwd: string, agentName: string, startedAt: number): boolean {
	try {
		const dir = getWorkfileDir(cwd, agentName);
		if (!fs.existsSync(dir)) return false;
		const files = fs.readdirSync(dir).filter((f) => f.endsWith(".md"));
		// 检查是否有在本次任务开始后创建的文件
		return files.some((f) => {
			const stat = fs.statSync(path.join(dir, f));
			return stat.mtimeMs >= startedAt - 5000; // 5s 容差
		});
	} catch {
		return false;
	}
}

// ─── Launcher ─────────────────────────────────────────────────────────────

function generateRunId(): string {
	return `sa-${Date.now().toString(36)}-${crypto.randomBytes(3).toString("hex")}`;
}

function tmuxExec(args: string[]): string {
	return execFileSync("tmux", args, { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }).trim();
}

function tmuxExecMaybe(args: string[]): string | null {
	try {
		return tmuxExec(args);
	} catch {
		return null;
	}
}

function shellQuote(value: string): string {
	return `'${value.replace(/'/g, "'\\''")}'`;
}

function ensureWrapperExecutable(): string {
	const wrapper = path.join(getScriptsDir(), "subagent-wrapper.sh");
	try {
		fs.accessSync(wrapper, fs.constants.X_OK);
	} catch {
		throw new Error(`subagent wrapper is not executable: ${wrapper}`);
	}
	return wrapper;
}

function cleanupOldRuns(config: SubagentConfig): void {
	if (config.keepResults <= 0) return;

	const subagentsDir = getSubagentsDir();
	if (!fs.existsSync(subagentsDir)) return;

	const runs = fs
		.readdirSync(subagentsDir)
		.map((name) => {
			const runDir = path.join(subagentsDir, name);
			const status = readStatus(runDir);
			let mtimeMs = 0;
			try {
				mtimeMs = fs.statSync(runDir).mtimeMs;
			} catch {
				/* ignore */
			}
			return { name, runDir, status, mtimeMs };
		})
		.filter((run) => run.status?.status !== "running")
		.sort((a, b) => b.mtimeMs - a.mtimeMs);

	for (const run of runs.slice(config.keepResults)) {
		try {
			fs.rmSync(run.runDir, { recursive: true, force: true });
		} catch {
			/* ignore */
		}
	}
}

function writeFailedStatus(runDir: string, exitCode: number, error: string, startedAt?: number): void {
	const now = Date.now();
	fs.writeFileSync(
		path.join(runDir, "status.json"),
		JSON.stringify({
			status: "failed",
			exitCode,
			error,
			startedAt: startedAt ?? now,
			finishedAt: now,
		}),
		"utf-8",
	);
}

function paneIsAlive(paneId: string): boolean {
	return tmuxExecMaybe(["display-message", "-p", "-t", paneId, "#{pane_id}"]) === paneId;
}

function killPane(paneId: string): void {
	tmuxExecMaybe(["kill-pane", "-t", paneId]);
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
	const wrapper = ensureWrapperExecutable();
	const args: string[] = [runId, agent.name, path.join(runDir, "task.md")];
	const effectiveModel = model ?? agent.model;
	if (effectiveModel) args.push("--model", effectiveModel);
	if (thinking ?? agent.thinking) args.push("--thinking", (thinking ?? agent.thinking)!);
	if (cwd) args.push("--cwd", cwd);
	if (agent.tools && agent.tools.length > 0) args.push("--tools", agent.tools.join(","));
	return [wrapper, ...args].map(shellQuote).join(" ");
}

function splitAboveCurrentPane(cmd: string): string {
	return tmuxExec(["split-window", "-v", "-b", "-p", TOP_ROW_PERCENT, "-P", "-F", "#{pane_id}", cmd]);
}

function splitRightOfPane(targetPaneId: string, cmd: string, percent: number): string {
	return tmuxExec([
		"split-window",
		"-t",
		targetPaneId,
		"-h",
		"-p",
		String(Math.max(10, Math.min(90, percent))),
		"-P",
		"-F",
		"#{pane_id}",
		cmd,
	]);
}

function launchSingle(
	agent: AgentConfig,
	task: string,
	config: SubagentConfig,
	cwd?: string,
	model?: string,
	thinking?: string,
	topRowTargetPaneId?: string,
	splitPercent = 50,
): LaunchResult {
	if (!process.env.TMUX) {
		throw new Error("tmux-subagents requires Pi to run inside a tmux session");
	}

	cleanupOldRuns(config);
	const myPaneId = tmuxExec(["display-message", "-p", "#{pane_id}"]);
	const runId = generateRunId();
	const runDir = getRunDir(runId);
	prepareRunDir(runDir, task);

	const paneTitle = `${config.panePrefix}${agent.name}`;
	const cmd = buildWrapperCmd(runId, agent, runDir, cwd, model, thinking);

	const paneId = topRowTargetPaneId
		? splitRightOfPane(topRowTargetPaneId, cmd, splitPercent)
		: splitAboveCurrentPane(cmd);
	tmuxExec(["select-pane", "-t", paneId, "-T", paneTitle]);
	tmuxExec(["select-pane", "-t", myPaneId]);

	return { runId, runDir, paneId, paneTitle, agent };
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

	cleanupOldRuns(config);
	const myPaneId = tmuxExec(["display-message", "-p", "#{pane_id}"]);
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
			paneId = splitAboveCurrentPane(cmd);
		} else {
			const pct = Math.round(((count - i) / (count - i + 1)) * 100);
			paneId = splitRightOfPane(results[i - 1].paneId, cmd, pct);
		}

		tmuxExec(["select-pane", "-t", paneId, "-T", paneTitle]);
		results.push({ runId, runDir, paneId, paneTitle, agent });
	}

	tmuxExec(["select-pane", "-t", myPaneId]);
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
			const agent = launch.paneTitle.replace(config.panePrefix, "");
			const finishFailed = (exitCode: number, output: string, error?: string) => {
				clearInterval(interval);
				writeFailedStatus(launch.runDir, exitCode, error ?? output, startedAt);
				resolve({
					runId: launch.runId,
					agent,
					status: "failed",
					exitCode,
					output,
					durationMs: Date.now() - startedAt,
					tmuxPane: launch.paneTitle,
					error,
				});
			};

			if (signal?.aborted) {
				killPane(launch.paneId);
				finishFailed(-1, "Aborted", "Aborted");
				return;
			}

			if (Date.now() - startedAt > config.timeoutMs) {
				killPane(launch.paneId);
				finishFailed(124, `Timed out after ${config.timeoutMs}ms`, "timeout");
				return;
			}

			const status = readStatus(launch.runDir);
			if (status && status.status !== "running") {
				clearInterval(interval);
				const output = readResult(launch.runDir);
				resolve({
					runId: launch.runId,
					agent,
					status: status.status,
					exitCode: status.exitCode ?? 1,
					output,
					durationMs: (status.finishedAt ?? Date.now()) - (status.startedAt ?? startedAt),
					tmuxPane: launch.paneTitle,
					error: status.error,
				});
				return;
			}

			if (!paneIsAlive(launch.paneId)) {
				const stderrPath = path.join(launch.runDir, "stderr.log");
				let stderr = "";
				try {
					stderr = fs.readFileSync(stderrPath, "utf-8").trim();
				} catch {
					/* ignore */
				}
				finishFailed(127, stderr || "tmux pane exited before writing final status", stderr || undefined);
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

/** 任务完成后验证 workfile，若 agent 未自行写入则由扩展兜底持久化 */
function ensureWorkfile(result: RunResult, cwd: string, startedAt: number): void {
	// 检查 agent 是否已自行写入 workfile
	if (checkWorkfileExists(cwd, result.agent, startedAt)) return;

	// agent 未写入（可能未遵循指令），由扩展兜底持久化
	const workfilePath = persistToWorkfile(cwd, result.agent, result.output);
	if (workfilePath) {
		result.workfilePath = workfilePath;
	}
}

/** 并行执行多批任务，每批不超过 maxConcurrency，完成后验证 workfile */
async function runParallelBatches(
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

	for (let i = 0; i < tasks.length; i += concurrency) {
		const batch = tasks.slice(i, i + concurrency);
		const launches = launchParallel(batch, config, model, thinking);
		const batchResults = await waitForAll(launches, config, signal);
		results.push(...batchResults);
	}

	// 验证 workfile
	for (const r of results) {
		if (r.status === "completed") {
			ensureWorkfile(r, cwd, startedAt);
		}
	}

	return results;
}

/** 串行执行任务链，{previous} 替换为上一步输出，完成后注入 workfile 路径并验证 */
async function runChain(
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
		const task = step.task.replaceAll("{previous}", previous).replaceAll("{task}", rootTask ?? previous);
		const pct = Math.round(((steps.length - i) / (steps.length - i + 1)) * 100);
		const launch = launchSingle(step.agent, task, config, step.cwd ?? cwd, model, thinking, topRowTargetPaneId, pct);
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

/** 格式化单个 agent 的运行结果（含 workfile 路径提示） */
function formatResult(r: RunResult): string {
	const icon = r.status === "completed" ? "✓" : "✗";
	const workfile = r.workfilePath ? `\n📄 工作产物: ${r.workfilePath}` : "";
	return `### [${r.agent}] ${icon} (${r.durationMs}ms)${workfile}\n\n${r.output}`;
}

/** 格式化多个 agent 运行结果的汇总 */
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
	task: Type.Optional(Type.String({ description: "任务描述（single 模式，或 chain 模式的根任务）" })),
	tasks: Type.Optional(Type.Array(TaskItem, { description: "并行任务数组" })),
	chain: Type.Optional(Type.Array(TaskItem, { description: "串行任务链；可在 task 中使用 {previous} 和 {task}" })),
	action: Type.Optional(
		Type.Union([Type.Literal("list"), Type.Literal("status")], { description: "管理动作" }),
	),
	id: Type.Optional(Type.String({ description: "查看指定 run-id 的状态" })),
	cwd: Type.Optional(Type.String({ description: "工作目录覆盖" })),
	model: Type.Optional(Type.String({ description: "模型覆盖" })),
	thinking: Type.Optional(
		Type.Union([
			Type.Literal("off"),
			Type.Literal("minimal"),
			Type.Literal("low"),
			Type.Literal("medium"),
			Type.Literal("high"),
			Type.Literal("xhigh"),
		], {
			description: "思考级别",
		}),
	),
});

export default function (pi: ExtensionAPI) {
	const config = loadConfig();

	pi.registerTool({
		name: "subagent",
		label: "Subagent",
		description: [
			"通过 tmux 分屏可视化执行 subagent 任务。",
			"模式：single (agent + task)、parallel (tasks 数组)、chain (chain 数组)。",
			"管理：action: list 列出可用 agent 和 prompt 模板，action: status 查看运行状态。",
		].join(" "),
		parameters: SubagentParams,

		async execute(_toolCallId, params, signal, _onUpdate, _ctx): Promise<AgentToolResult<SubagentDetails>> {
			const agents = discoverAgents();
			const prompts = discoverPrompts();
			const effectiveCwd = params.cwd ?? process.cwd();
			const makeDetails =
				(mode: "single" | "parallel" | "chain" | "list" | "status") =>
				(results: RunResult[]): SubagentDetails => ({ mode, results });

			if (params.action === "list") {
				const agentLines = agents
					.map((a) => {
						const tools = a.tools ? a.tools.join(", ") : "all";
						const model = a.model ?? "default";
						return `| ${a.name} | ${a.description.slice(0, 40)}… | ${tools} | ${model} |`;
					})
					.join("\n");
				const promptLines = prompts
					.map((p) => `| ${p.name} | ${p.mode} | ${p.description.slice(0, 40)}… | /${p.name} <${p.param}> |`)
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

			if (params.chain && params.chain.length > 0) {
				if (params.chain.length > config.maxTasks) {
					return {
						content: [{ type: "text", text: `chain 任务数 ${params.chain.length} 超过上限 ${config.maxTasks}` }],
						details: makeDetails("chain")([]),
						isError: true,
					};
				}

				const chainEntries: Array<{ agent: AgentConfig; task: string; cwd?: string }> = [];
				for (const t of params.chain) {
					const agent = agents.find((a) => a.name === t.agent);
					if (!agent) {
						const available = agents.map((a) => a.name).join(", ") || "none";
						return {
							content: [{ type: "text", text: `未知 agent: "${t.agent}"。可用: ${available}` }],
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
						content: [{ type: "text", text: `启动失败: ${(err as Error).message}` }],
						details: makeDetails("chain")([]),
						isError: true,
					};
				}
			}

			if (params.tasks && params.tasks.length > 0) {
				if (params.tasks.length > config.maxTasks) {
					return {
						content: [{ type: "text", text: `parallel 任务数 ${params.tasks.length} 超过上限 ${config.maxTasks}` }],
						details: makeDetails("parallel")([]),
						isError: true,
					};
				}

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
					taskEntries.push({ agent, task: t.task, cwd: params.cwd });
				}

				try {
					const results = await runParallelBatches(taskEntries, config, effectiveCwd, params.model, params.thinking, signal);
					return {
						content: [{ type: "text", text: formatResults(results) }],
						details: makeDetails("parallel")(results),
						isError: results.some((r) => r.status === "failed") || undefined,
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
					const startedAt = Date.now();
					const launch = launchSingle(agent, params.task, config, params.cwd, params.model, params.thinking);
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

	// ── 为每个 agent 注册 /agentname 快捷命令（启动单个 agent 执行任务） ──
	const agents = discoverAgents();
	for (const agent of agents) {
		pi.registerCommand(agent.name, {
			description: `${agent.description}（/${agent.name} <任务描述>）`,
			handler: async (args, ctx) => {
				const task = args.trim();
				if (!task) {
					ctx.ui.notify(`用法: /${agent.name} <任务描述>\n例: /${agent.name} 审查当前修改的代码`, "warn");
					return;
				}

				try {
					const startedAt = Date.now();
					const launch = launchSingle(agent, task, config, ctx.cwd, agent.model, agent.thinking);
					ctx.ui.notify(`⏳ ${agent.name} 已启动 (run: ${launch.runId})...`, "info");
					const result = await waitForCompletion(launch, config);
					if (result.status === "completed") {
						ensureWorkfile(result, ctx.cwd, startedAt);
						const workfileNote = result.workfilePath ? `\n📄 ${result.workfilePath}` : "";
						ctx.ui.notify(`✅ ${agent.name} 完成 (${(result.durationMs / 1000).toFixed(1)}s)${workfileNote}\n\n${result.output.slice(0, 4000)}${result.output.length > 4000 ? "\n...（截断）" : ""}`, "info");
					} else {
						ctx.ui.notify(`❌ ${agent.name} 失败 (run: ${launch.runId}): ${result.error ?? "未知错误"}`, "error");
					}
				} catch (err) {
					ctx.ui.notify(`启动 ${agent.name} 失败: ${(err as Error).message}`, "error");
				}
			},
		});
	}

	// ── 为每个 prompt 模板注册快捷命令（与 agent 命令同一命名空间，冲突时跳过） ──
	const prompts = discoverPrompts();
	const agentNames = new Set(agents.map((a) => a.name));
	for (const prompt of prompts) {
		if (agentNames.has(prompt.name)) continue; // 与 agent 命令冲突，跳过
		pi.registerCommand(prompt.name, {
			description: `${prompt.description}（/${prompt.name} <${prompt.param}>）`,
			handler: async (args, ctx) => {
				const paramValue = args.trim();
				if (!paramValue) {
					ctx.ui.notify(`用法: /${prompt.name} <${prompt.param}>\n例: /${prompt.name} 重构认证模块`, "warn");
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
						// chain 模式：串行执行，{previous} 自动替换为上一步输出
						const chainEntries = resolvedEntries.map((e) => {
							const agent = agents.find((a) => a.name === e.agent);
							if (!agent) throw new Error(`未知 agent: ${e.agent}`);
							return { agent, task: e.task };
						});
						results = await runChain(chainEntries, config, ctx.cwd, paramValue);
					} else if (prompt.mode === "parallel") {
						// parallel 模式：并行执行，互不依赖
						const taskEntries = resolvedEntries.map((e) => {
							const agent = agents.find((a) => a.name === e.agent);
							if (!agent) throw new Error(`未知 agent: ${e.agent}`);
							return { agent, task: e.task };
						});
						results = await runParallelBatches(taskEntries, config, ctx.cwd);
					} else {
						// single 模式：单个 agent 执行
						const e = resolvedEntries[0];
						const agent = agents.find((a) => a.name === e.agent);
						if (!agent) throw new Error(`未知 agent: ${e.agent}`);
						const launch = launchSingle(agent, e.task, config, ctx.cwd);
						const result = await waitForCompletion(launch, config);
						results = [result];
					}

					const success = results.filter((r) => r.status === "completed").length;
					ctx.ui.notify(`${prompt.name}: ${success}/${results.length} 成功\n\n${formatResults(results).slice(0, 4000)}`, success === results.length ? "info" : "warn");
				} catch (err) {
					ctx.ui.notify(`启动 ${prompt.name} 失败: ${(err as Error).message}`, "error");
				}
			},
		});
	}

	// ── Plan review gate（拦截 plannotator 提交，首次提交 block，要求 LLM 先调用 planner 审查） ──
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
