// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Workfile 持久化 — 将 agent 运行结果保存到 .agents/workfile/{agent}/ 目录
 *
 * 机制：
 * 1. 检查 agent 是否已通过 write 工具自行写入 workfile
 * 2. 若 agent 未写入，由扩展兜底持久化完整输出
 */

import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";

/** 获取 agent workfile 目录 */
function getWorkfileDir(cwd: string, agentName: string): string {
	return path.join(cwd, ".agents", "workfile", agentName);
}

/** 生成唯一 workfile 文件名：日期-随机hex.md */
function generateWorkfileName(): string {
	const date = new Date().toISOString().slice(0, 10);
	const hash = crypto.randomBytes(2).toString("hex");
	return `${date}-${hash}.md`;
}

/**
 * 将 agent 运行结果持久化到 .agents/workfile/{agent}/ 目录。
 * @returns 相对于 cwd 的文件路径，失败返回 undefined
 */
export function persistToWorkfile(
	cwd: string,
	agentName: string,
	content: string,
): string | undefined {
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

/**
 * 检查 agent 是否已在任务开始后自行写入了 workfile。
 * @param startedAt 任务开始时间戳，容差 5 秒
 */
export function checkWorkfileExists(
	cwd: string,
	agentName: string,
	startedAt: number,
): boolean {
	try {
		const dir = getWorkfileDir(cwd, agentName);
		if (!fs.existsSync(dir)) return false;
		const files = fs.readdirSync(dir).filter((f) => f.endsWith(".md"));
		return files.some((f) => {
			const stat = fs.statSync(path.join(dir, f));
			return stat.mtimeMs >= startedAt - 5000; // 5s 容差
		});
	} catch {
		return false;
	}
}

/**
 * 验证 workfile：若 agent 未自行写入，由扩展兜底持久化。
 * 成功持久化时更新 result.workfilePath。
 */
export function ensureWorkfile(
	result: { agent: string; output: string; workfilePath?: string; status: string },
	cwd: string,
	startedAt: number,
): void {
	if (checkWorkfileExists(cwd, result.agent, startedAt)) return;
	const workfilePath = persistToWorkfile(cwd, result.agent, result.output);
	if (workfilePath) {
		result.workfilePath = workfilePath;
	}
}
