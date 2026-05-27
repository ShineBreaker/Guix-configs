// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 会话日志 — 记录每次 subagent 调用的摘要，会话结束时持久化
 *
 * 机制：
 *   1. 每次 subagent 工具执行完成后，调用 appendSessionLog() 追加记录
 *   2. 会话关闭时（session_shutdown），调用 finalizeSessionLog() 写入文件
 *   3. 日志文件保存到 .agents/workfile/session-summaries/ 目录
 */

import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import type { RunResult } from "./types.ts";

/** 单次 subagent 调用记录 */
interface SessionLogEntry {
	timestamp: string;
	mode: "single" | "parallel" | "chain";
	agents: string[];
	tasks: string[];
	statuses: Array<"completed" | "failed" | "running">;
	totalDurationMs: number;
	outputPreview: string;
}

/** 当前会话的日志缓冲 */
const sessionLog: SessionLogEntry[] = [];
/** 会话开始时间 */
const sessionStartedAt = new Date().toISOString();

/**
 * 追加一条 subagent 调用记录。
 * 在 subagent 工具 execute 返回前调用。
 */
export function appendSessionLog(
	mode: "single" | "parallel" | "chain",
	results: RunResult[],
): void {
	if (results.length === 0) return;

	const entry: SessionLogEntry = {
		timestamp: new Date().toISOString(),
		mode,
		agents: results.map((r) => r.agent),
		tasks: results.map((r) => r.output.slice(0, 100)),
		statuses: results.map((r) => r.status),
		totalDurationMs: results.reduce((sum, r) => sum + r.durationMs, 0),
		outputPreview:
			results.length === 1
				? results[0].output.slice(0, 200)
				: `${results.length} agents: ${results.map((r) => `${r.agent}(${r.status})`).join(", ")}`,
	};
	sessionLog.push(entry);
}

/**
 * 会话结束时将日志持久化到 workfile 目录。
 * 在 session_shutdown 事件中调用。
 */
export function finalizeSessionLog(cwd: string): string | undefined {
	if (sessionLog.length === 0) return undefined;

	const dir = path.join(cwd, ".agents", "workfile", "session-summaries");
	fs.mkdirSync(dir, { recursive: true });

	const date = new Date().toISOString().slice(0, 10);
	const hash = crypto.randomBytes(2).toString("hex");
	const fileName = `${date}-${hash}.md`;

	const totalCalls = sessionLog.length;
	const totalAgents = new Set(sessionLog.flatMap((e) => e.agents)).size;
	const completedCalls = sessionLog.filter((e) =>
		e.statuses.every((s) => s === "completed"),
	).length;
	const totalDurationMs = sessionLog.reduce(
		(sum, e) => sum + e.totalDurationMs,
		0,
	);

	const lines: string[] = [
		`# 会话摘要`,
		``,
		`- **会话开始**: ${sessionStartedAt}`,
		`- **会话结束**: ${new Date().toISOString()}`,
		`- **总调用次数**: ${totalCalls}`,
		`- **涉及 agent**: ${totalAgents}`,
		`- **全部成功**: ${completedCalls}/${totalCalls}`,
		`- **总耗时**: ${(totalDurationMs / 1000).toFixed(1)}s`,
		``,
		`## 调用记录`,
		``,
	];

	for (let i = 0; i < sessionLog.length; i++) {
		const entry = sessionLog[i];
		const status =
			entry.statuses.every((s) => s === "completed") ? "✅" : "❌";
		const duration = (entry.totalDurationMs / 1000).toFixed(1);
		lines.push(
			`### ${i + 1}. [${entry.mode}] ${status} (${duration}s)`,
			``,
			`- **Agent**: ${entry.agents.join(", ")}`,
			`- **状态**: ${entry.statuses.join(", ")}`,
			`- **输出预览**: ${entry.outputPreview}`,
			``,
		);
	}

	const filePath = path.join(dir, fileName);
	fs.writeFileSync(filePath, lines.join("\n"), "utf-8");

	// 清空缓冲
	sessionLog.length = 0;

	return path.relative(cwd, filePath);
}
