// SPDX-License-Identifier: MIT
//
// agent-gate — pi-gate 的 DSH 等价物。
//
// 与 zcode/crush/hermes/pi 适配器同族：只做协议转换，判定语义集中在
// gate-core.sh（单一真相源，anchors 合并全局 + 项目级规则）。
//
// 映射关系（pi → dsh）：
//   tool_call(bash)      → tools/pre-execute + exec.name === 'bash'
//   tool_call(write|edit)→ tools/pre-execute + write/edit/str_replace_editor
//   BLOCK                → { kind: 'deny', reason }（原因随结果回给模型）
//   SENSITIVE            → { kind: 'ask', reason }（语义即「需用户确认」；
//                          客户端无审批通道时用 config.sensitiveDecision='deny' 退回硬拒）
//   REWRITTEN            → { kind: 'deny', reason } 附带改写命令 —— DSH 的
//                          pre-execute 参数已冻结（审计完整性），不支持原地改写，
//                          让模型用改写后的命令重试是唯一安全映射
//   RM_HINT/NOTES/REDIRECT/HINT → tools/post-execute 的 additionalContexts
//                          （模型可见，比 pi 的瞬时 UI notify 更贴近会话语义）
//   AUTO_ALLOW           → 忽略（DSH 无 auto-approve 通道，走默认审批链）
//   gate-core 异常       → sudo 保底拦截，其余放行（与 pi 一致）
//   /run/agent-gate.off  → 跳过全部检查，静默放行（不向 agent 暴露暂停态）

import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { createUserMessage } from "./lib.js";

export const name = "agent-gate";
export const inject = ["tools"];

// 会话格式 v4 要求 producer-owned source kind：`kind: "plugin"` 包装已退役，
// 第三方生产者按迁移器规则（producerKind）直接写 `plugin:<名>`。
const SOURCE = { kind: "plugin:agent-gate" };
const SUDO_PATTERN = /\bsudo\b/;
// 写文件类工具：写盘内容送 gate-core edit 子命令做敏感信息/保护路径判定
const WRITE_TOOLS = new Set(["write", "edit", "str_replace_editor"]);

function xdgConfigHome() {
	return process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
}
function xdgStateHome() {
	return process.env.XDG_STATE_HOME || join(homedir(), ".local", "state");
}

function logGateError(logPath, line) {
	try {
		mkdirSync(dirname(logPath), { recursive: true });
		appendFileSync(logPath, `[${new Date().toISOString()}] ${line}\n`);
	} catch {
		/* 日志不可写时静默，避免反噬工具执行 */
	}
}

// gate-core 行协议：每行 `TYPE<TAB>payload`；与 pi-gate 的解析保持一致。
function parseGateOutput(stdout) {
	const verdict = { block: null, sensitive: false, rewritten: null, hints: [] };
	for (const line of (stdout ?? "").split("\n")) {
		if (!line) continue;
		const tab = line.indexOf("\t");
		const type = tab === -1 ? line : line.slice(0, tab);
		const payload = tab === -1 ? "" : line.slice(tab + 1);
		switch (type) {
			case "BLOCK":
				verdict.block = payload;
				return verdict;
			case "SENSITIVE":
				verdict.block = payload;
				verdict.sensitive = true;
				return verdict;
			case "REWRITTEN":
				verdict.rewritten = payload;
				break;
			case "RM_HINT":
			case "NOTES":
			case "REDIRECT":
			case "HINT":
				if (payload) verdict.hints.push(payload);
				break;
			// AUTO_ALLOW：走默认审批链即可
		}
	}
	return verdict;
}

export function apply(ctx, config = {}) {
	const cfg = {
		enabled: config.enabled ?? true,
		gateCore: config.gateCore ?? join(xdgConfigHome(), "agents", "gate-core.sh"),
		pauseFile: config.pauseFile ?? process.env.GATE_PAUSE_FILE ?? "/run/agent-gate.off",
		errorLog: config.errorLog ?? join(xdgStateHome(), "dsh", "agent-gate-errors.log"),
		timeoutMs: config.timeoutMs ?? 10_000,
		sensitiveDecision: config.sensitiveDecision === "deny" ? "deny" : "ask",
	};

	// callId → 待下发的非阻塞提示（pre 收集，post 转 additionalContexts 随结果入会话）
	const pendingHints = new Map();

	const pushHints = (exec, hints) => {
		if (!hints?.length) return;
		const key = String(exec.callId ?? "");
		if (!key) return;
		const list = pendingHints.get(key) ?? [];
		list.push(...hints);
		pendingHints.set(key, list);
	};

	const cwdOf = (exec) => {
		const workdir = exec.arguments?.workdir;
		if (typeof workdir === "string" && workdir.trim()) return workdir;
		return exec.agent?.session?.header?.cwd ?? process.cwd();
	};

	const runCore = (argv, cwd, stdin) => {
		const res = spawnSync("bash", [cfg.gateCore, ...argv], {
			input: stdin,
			encoding: "utf8",
			timeout: cfg.timeoutMs,
			env: { ...process.env, GATE_CWD: cwd },
			maxBuffer: 1024 * 1024,
		});
		if (res.error || res.status !== 0) {
			const detail = res.error ? String(res.error.message ?? res.error) : `exit ${res.status}`;
			logGateError(cfg.errorLog, `agent-gate: gate-core failed: ${detail}`);
			ctx.logger.warn(`agent-gate: gate-core failed: ${detail}`);
			return null;
		}
		return parseGateOutput(res.stdout);
	};

	const blockDecision = (v) => ({
		kind: v.sensitive && cfg.sensitiveDecision === "ask" ? "ask" : "deny",
		reason: v.block,
	});

	ctx.on("tools/pre-execute", async (exec, next) => {
		if (!cfg.enabled) return next();
		const paused = existsSync(cfg.pauseFile);

		if (exec.name === "bash") {
			const command = String(exec.arguments?.command ?? "");
			if (!command.trim()) return next();
			if (paused) return next();
			const v = runCore(["bash", command], cwdOf(exec));
			if (!v) {
				if (SUDO_PATTERN.test(command)) {
					return { kind: "deny", reason: "冻结命令「sudo」禁止执行（gate-core 异常，保底拦截）。" };
				}
				return next();
			}
			if (v.block) return blockDecision(v);
			if (v.rewritten) {
				const hintsText = v.hints.length ? `\n${v.hints.join("\n")}` : "";
				return {
					kind: "deny",
					reason: `命令已按本机约定改写为：\`${v.rewritten}\`（DSH 参数已冻结，不支持原地改写；请改用改写后的命令重新发起）${hintsText}`,
				};
			}
			pushHints(exec, v.hints);
			return next();
		}

		if (WRITE_TOOLS.has(exec.name)) {
			const args = exec.arguments ?? {};
			const filePath = String(args.file_path ?? args.path ?? "");
			if (!filePath) return next();
			if (paused) return next();
			const content = String(args.new_string ?? args.content ?? "");
			const v = runCore(["edit", filePath], cwdOf(exec), content);
			if (!v) return next();
			if (v.block) return blockDecision(v);
			pushHints(exec, v.hints);
			return next();
		}

		return next();
	});

	ctx.on("tools/post-execute", async (exec, result, next) => {
		const downstream = await next();
		const key = String(exec.callId ?? "");
		const texts = pendingHints.get(key);
		if (texts) pendingHints.delete(key);
		if (!texts?.length) return downstream;
		if (downstream.kind !== "accept" && downstream.kind !== "block") return downstream;
		const contexts = texts.map((text) =>
			createUserMessage({ content: [{ type: "text", text }], source: SOURCE }),
		);
		return {
			...downstream,
			additionalContexts: [...contexts, ...(downstream.additionalContexts ?? [])],
		};
	});
}
