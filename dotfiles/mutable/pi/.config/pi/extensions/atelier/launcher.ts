// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Tmux 启动器 — 通过 tmux split-window 创建子 pane 运行 subagent
 *
 * 布局策略：
 *   single:  在当前 pane 上方创建一个子 pane（占 40%）
 *   parallel: 先创建上方行，再水平分割为 N 个等宽子 pane
 *   chain:    复用 single，每步在前一步的 pane 位置继续分割
 */

import { execFileSync } from "node:child_process";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { AgentConfig, LaunchResult, StatusFile, SubagentConfig } from "./types.ts";
import { TOP_ROW_PERCENT } from "./types.ts";

// ─── XDG 路径 ────────────────────────────────────────────────────────────────

function resolveXdgCache(): string {
	return process.env.XDG_CACHE_HOME ?? path.join(os.homedir(), ".cache");
}

function resolveXdgData(): string {
	return process.env.XDG_DATA_HOME ?? path.join(os.homedir(), ".local", "share");
}

/** 所有运行数据的根目录 */
export function getSubagentsDir(): string {
	return path.join(resolveXdgCache(), "pi", "subagents");
}

/** 单次运行的目录 */
export function getRunDir(runId: string): string {
	return path.join(getSubagentsDir(), runId);
}

/** wrapper 脚本所在目录 */
function getScriptsDir(): string {
	return path.join(resolveXdgData(), "pi", "scripts");
}

// ─── Tmux 命令封装 ──────────────────────────────────────────────────────────

/** 同步执行 tmux 命令，返回 stdout */
function tmuxExec(args: string[]): string {
	return execFileSync("tmux", args, {
		encoding: "utf-8",
		stdio: ["pipe", "pipe", "pipe"],
	}).trim();
}

/** 同步执行 tmux 命令，失败返回 null */
function tmuxExecMaybe(args: string[]): string | null {
	try {
		return tmuxExec(args);
	} catch {
		return null;
	}
}

/** Shell 单引号转义 */
function shellQuote(value: string): string {
	return `'${value.replace(/'/g, "'\\''")}'`;
}

// ─── Run 目录管理 ────────────────────────────────────────────────────────────

/** 生成唯一 run ID */
export function generateRunId(): string {
	return `sa-${Date.now().toString(36)}-${crypto.randomBytes(3).toString("hex")}`;
}

/** 确保 wrapper 脚本可执行 */
function ensureWrapperExecutable(): string {
	const wrapper = path.join(getScriptsDir(), "subagent-wrapper.sh");
	try {
		fs.accessSync(wrapper, fs.constants.X_OK);
	} catch {
		throw new Error(`subagent wrapper is not executable: ${wrapper}`);
	}
	return wrapper;
}

/** 清理过期的运行记录 */
export function cleanupOldRuns(config: SubagentConfig): void {
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

/** 向 run 目录写入失败状态 */
export function writeFailedStatus(
	runDir: string,
	exitCode: number,
	error: string,
	startedAt?: number,
): void {
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

/** 检查 tmux pane 是否仍存活 */
export function paneIsAlive(paneId: string): boolean {
	return (
		tmuxExecMaybe(["display-message", "-p", "-t", paneId, "#{pane_id}"]) === paneId
	);
}

/** 终止 tmux pane */
export function killPane(paneId: string): void {
	tmuxExecMaybe(["kill-pane", "-t", paneId]);
}

/** 创建 run 目录并写入初始状态 */
function prepareRunDir(runDir: string, task: string): void {
	fs.mkdirSync(runDir, { recursive: true });
	fs.writeFileSync(path.join(runDir, "task.md"), task, "utf-8");
	fs.writeFileSync(
		path.join(runDir, "status.json"),
		JSON.stringify({ status: "running", startedAt: Date.now() }),
		"utf-8",
	);
}

/** 读取 run 目录下的 status.json */
export function readStatus(runDir: string): StatusFile | null {
	const statusPath = path.join(runDir, "status.json");
	try {
		return JSON.parse(fs.readFileSync(statusPath, "utf-8"));
	} catch {
		return null;
	}
}

/** 读取 run 目录下的 result.md */
export function readResult(runDir: string): string {
	const resultPath = path.join(runDir, "result.md");
	try {
		return fs.readFileSync(resultPath, "utf-8");
	} catch {
		return "(no output)";
	}
}

// ─── Wrapper 命令构造 ────────────────────────────────────────────────────────

/** 构造 wrapper 脚本的完整命令行 */
function buildWrapperCmd(
	runId: string,
	agent: AgentConfig,
	runDir: string,
	cwd?: string,
	model?: string,
	thinking?: string,
	images?: string[],
): string {
	const wrapper = ensureWrapperExecutable();
	const args: string[] = [runId, agent.name, path.join(runDir, "task.md")];
	const effectiveModel = model ?? agent.model;
	if (effectiveModel) args.push("--model", effectiveModel);
	if (thinking ?? agent.thinking) args.push("--thinking", (thinking ?? agent.thinking)!);
	if (cwd) args.push("--cwd", cwd);
	if (agent.tools && agent.tools.length > 0) args.push("--tools", agent.tools.join(","));
	if (images && images.length > 0) args.push("--image", images.join(","));
	return [wrapper, ...args].map(shellQuote).join(" ");
}

// ─── 分屏操作 ────────────────────────────────────────────────────────────────

/** 在当前 pane **上方**垂直分割一个新 pane，返回新 pane ID */
function splitAboveCurrentPane(cmd: string): string {
	return tmuxExec([
		"split-window",
		"-v", // 垂直分割
		"-b", // 在当前 pane 之前（上方）
		"-p",
		TOP_ROW_PERCENT,
		"-P", // 打印新 pane 信息
		"-F",
		"#{pane_id}",
		cmd,
	]);
}

/** 在指定 pane **右侧**水平分割一个新 pane，返回新 pane ID */
function splitRightOfPane(
	targetPaneId: string,
	cmd: string,
	percent: number,
): string {
	return tmuxExec([
		"split-window",
		"-t",
		targetPaneId,
		"-h", // 水平分割
		"-p",
		String(Math.max(10, Math.min(90, percent))),
		"-P",
		"-F",
		"#{pane_id}",
		cmd,
	]);
}

// ─── 启动函数 ─────────────────────────────────────────────────────────────────

/**
 * 启动单个 subagent。
 *
 * 布局：
 *   - 无 topRowTargetPaneId → 在当前 pane 上方垂直分割
 *   - 有 topRowTargetPaneId → 在指定 pane 右侧水平分割（chain 模式复用）
 */
export function launchSingle(
	agent: AgentConfig,
	task: string,
	config: SubagentConfig,
	cwd?: string,
	model?: string,
	thinking?: string,
	topRowTargetPaneId?: string,
	splitPercent = 50,
	images?: string[],
): LaunchResult {
	if (!process.env.TMUX) {
		throw new Error("atelier requires Pi to run inside a tmux session");
	}

	cleanupOldRuns(config);
	const myPaneId = tmuxExec(["display-message", "-p", "#{pane_id}"]);
	const runId = generateRunId();
	const runDir = getRunDir(runId);
	prepareRunDir(runDir, task);

	const paneTitle = `${config.panePrefix}${agent.name}`;
	const cmd = buildWrapperCmd(runId, agent, runDir, cwd, model, thinking, images);

	const paneId = topRowTargetPaneId
		? splitRightOfPane(topRowTargetPaneId, cmd, splitPercent)
		: splitAboveCurrentPane(cmd);

	// 设置 pane 标题并切回主 pane
	tmuxExec(["select-pane", "-t", paneId, "-T", paneTitle]);
	tmuxExec(["select-pane", "-t", myPaneId]);

	return { runId, runDir, paneId, paneTitle, agent };
}

/**
 * 并行启动多个 subagent。
 *
 * 布局（修正后）：
 *   1. 第一个 task → 在当前 pane 上方垂直分割，创建顶部行
 *   2. 后续 task → 在前一个 pane 右侧水平分割，填满顶部行
 *
 * 效果：
 *   ┌──────────┬──────────┐
 *   │  sa1     │  sa2     │   ← 上方 40% 行，水平等分
 *   ├──────────┴──────────┤
 *   │  主 agent            │   ← 当前 pane
 *   └─────────────────────┘
 */
export function launchParallel(
	tasks: Array<{ agent: AgentConfig; task: string; cwd?: string }>,
	config: SubagentConfig,
	model?: string,
	thinking?: string,
	existingTopRowPaneId?: string,
): LaunchResult[] {
	if (!process.env.TMUX) {
		throw new Error("atelier requires Pi to run inside a tmux session");
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

		// 处理同名 agent 的 pane 标题编号
		const agentCountForName = tasks.filter(
			(t, j) => j <= i && t.agent.name === agent.name,
		).length;
		const paneTitle =
			tasks.filter((t) => t.agent.name === agent.name).length > 1
				? `${config.panePrefix}${agent.name}:${agentCountForName}`
				: `${config.panePrefix}${agent.name}`;

		const cmd = buildWrapperCmd(runId, agent, runDir, cwd, model, thinking);

		let paneId: string;
		if (i === 0 && !existingTopRowPaneId) {
			// 第一个且无已有顶部行：在当前 pane 上方垂直分割，创建顶部行
			paneId = splitAboveCurrentPane(cmd);
		} else if (i === 0 && existingTopRowPaneId) {
			// 跨 batch 续接：在已有顶部行最右 pane 右侧水平分割
			paneId = splitRightOfPane(existingTopRowPaneId, cmd, Math.round((count / (count + 1)) * 100));
		} else {
			// 后续：在前一个 pane 右侧水平分割，自动计算等分比例
			const pct = Math.round(((count - i) / (count - i + 1)) * 100);
			paneId = splitRightOfPane(results[i - 1].paneId, cmd, pct);
		}

		tmuxExec(["select-pane", "-t", paneId, "-T", paneTitle]);
		results.push({ runId, runDir, paneId, paneTitle, agent });
	}

	// 切回主 pane
	tmuxExec(["select-pane", "-t", myPaneId]);
	return results;
}
