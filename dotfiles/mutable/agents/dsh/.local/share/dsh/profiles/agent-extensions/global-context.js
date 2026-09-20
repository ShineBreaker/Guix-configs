// SPDX-License-Identifier: MIT
//
// agent-global-context — global-context 的 DSH 等价物。
//
// 注入内容仍由 context-select.sh 裁决（zcode/omp/crush/hermes/dsh 共享单一真相源），
// 本插件只做 DSH 侧协议转换：
//   - system-prompt section provider（order 10300，置于内置 personaSuffix 之后，
//     语义等同 pi 的「append 到 systemPrompt 末尾」；interpolate:false 防注入文本
//     里的 {{…}} 被当变量展开而炸）
//   - /global-context 命令（显示当前 cwd 下的启用状态与选中文件）
//   - /fetchcontext 命令（导出当前 agent 的拼装 system prompt + 会话消息到 markdown，
//     落在 session cwd）
//
// 配置：cordis 行 config 覆盖 ~/.config/omp/global-context.json（共享文件，与 omp
// 扩展同源），字段语义一致（enabled/separator/maxFiles/maxBytesPerFile/maxTotalBytes）。

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { assembleContextFor, renderPrompt } from "./lib.js";

export const name = "agent-global-context";
export const inject = ["systemPrompt", "commands"];

const HEADER = "The following is global context injected by the global-context extension:";
// DEPLOYMENT_PERSONA_SUFFIX=10200 之后，保证追加在所有内置 section 末尾
const SECTION_ORDER = 10300;
const SECTION_NAME = "agents-global-context";

function xdgConfigHome() {
	return process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
}

// 共享配置文件（与 omp 扩展读取的同一文件）；读不到用默认值，行 config 仍可覆盖
function sharedConfig() {
	try {
		return JSON.parse(readFileSync(join(xdgConfigHome(), "omp", "global-context.json"), "utf8")) ?? {};
	} catch {
		return {};
	}
}

function normalize(cfg) {
	return {
		enabled: cfg.enabled ?? true,
		selector: cfg.selector ?? process.env.CONTEXT_SELECT_BIN ?? join(xdgConfigHome(), "agents", "context-select.sh"),
		separator: typeof cfg.separator === "string" ? cfg.separator : "\n\n",
		maxFiles: Number.isFinite(cfg.maxFiles) && cfg.maxFiles > 0 ? Math.floor(cfg.maxFiles) : 20,
		maxBytesPerFile: Number.isFinite(cfg.maxBytesPerFile) && cfg.maxBytesPerFile > 0 ? Math.floor(cfg.maxBytesPerFile) : 16 * 1024,
		maxTotalBytes: Number.isFinite(cfg.maxTotalBytes) && cfg.maxTotalBytes > 0 ? Math.floor(cfg.maxTotalBytes) : 64 * 1024,
		timeoutMs: Number.isFinite(cfg.timeoutMs) && cfg.timeoutMs > 0 ? Math.floor(cfg.timeoutMs) : 5_000,
	};
}

// 由 selector 裁决文件集；选择器缺失/失败/空结果都静默降级为「无注入」
function selectFiles(cfg, cwd) {
	if (!existsSync(cfg.selector)) return [];
	const res = spawnSync("bash", [cfg.selector, "--platform", "dsh", "--cwd", cwd], {
		encoding: "utf8",
		timeout: cfg.timeoutMs,
		maxBuffer: 1024 * 1024,
	});
	if (res.error || res.status !== 0) return [];
	return res.stdout.split("\n").map((l) => l.trim()).filter(Boolean);
}

// 读取 + 预算裁剪，与 pi 版相同的文件包装格式
function readParts(cfg, files) {
	const parts = [];
	let total = 0;
	for (const file of files.slice(0, cfg.maxFiles)) {
		try {
			const size = statSync(file).size;
			if (size === 0 || size > cfg.maxBytesPerFile) continue;
			if (total + size > cfg.maxTotalBytes) break;
			const text = readFileSync(file, "utf8");
			total += size;
			parts.push(`<global_context_file path="${file}">\n${text}\n</global_context_file>`);
		} catch {
			/* 单文件读取失败跳过 */
		}
	}
	return parts;
}

function injectionText(cfg, cwd) {
	const parts = readParts(cfg, selectFiles(cfg, cwd));
	return parts.length === 0 ? "" : [HEADER, ...parts].join(cfg.separator);
}

function sessionCwd(agent) {
	return agent?.session?.header?.cwd ?? process.cwd();
}

// 会话事件 → markdown 片段（导出用，尽力而为）
function messageSection(ev) {
	const data = ev.data;
	if (ev.type === "user/message") return { role: data.source?.kind === "plugin" ? `user(${data.source.plugin ?? "plugin"})` : "user", message: data };
	if (ev.type === "assistant/message") return { role: "assistant", message: data.message };
	if (ev.type === "tool/result") return { role: "tool", message: data.message };
	if (ev.type === "system/message") return { role: "system", message: data.message };
	return null;
}

function textOf(message) {
	return (message?.content ?? [])
		.map((b) => (b?.type === "text" ? b.text : b?.type ? `<${b.type}>` : ""))
		.filter(Boolean)
		.join("\n");
}

export function apply(ctx, config = {}) {
	const cfg = normalize({ ...sharedConfig(), ...config });

	ctx.systemPrompt.section({
		name: SECTION_NAME,
		order: SECTION_ORDER,
		interpolate: false,
		text: (context) => {
			try {
				return injectionText(cfg, sessionCwd(context?.agent));
			} catch (error) {
				ctx.logger.warn(`agent-global-context: injection failed: ${String(error)}`);
				return "";
			}
		},
	});

	ctx.commands.register({
		definitionId: "agent-extensions.global-context",
		name: "global-context",
		description: "Show global-context injection status for this session's cwd",
		handler: (invocation) => {
			const cwd = sessionCwd(invocation.agent);
			if (!cfg.enabled) return { kind: "success", text: "global-context: disabled" };
			const files = selectFiles(cfg, cwd);
			const parts = readParts(cfg, files);
			const lines = [
				`global-context: enabled=${cfg.enabled} selector=${cfg.selector}`,
				`cwd=${cwd}`,
				files.length === 0
					? "selected: (none)"
					: `selected (${files.length}, injecting ${parts.length}):`,
				...files.map((f) => `  ${f}`),
				`budgets: maxFiles=${cfg.maxFiles} maxBytesPerFile=${cfg.maxBytesPerFile} maxTotalBytes=${cfg.maxTotalBytes}`,
			];
			return { kind: "success", text: lines.join("\n") };
		},
	});

	ctx.commands.register({
		definitionId: "agent-extensions.fetchcontext",
		name: "fetchcontext",
		description: "Export the assembled system prompt and session messages to a markdown file in the session cwd",
		handler: async (invocation) => {
			const agent = invocation.agent;
			if (!agent) return { kind: "error", text: "当前会话没有可导出的 agent。" };
			const assembly = await ctx.systemPrompt.assemble(assembleContextFor(agent, invocation.signal));
			const prompt = renderPrompt(assembly);
			const cwd = sessionCwd(agent);
			const events = agent.session?.snapshotEvents?.() ?? [];
			const chunks = ["# system prompt", "", "```", prompt, "```", "", "# messages", ""];
			for (const ev of events) {
				const m = messageSection(ev);
				if (!m) continue;
				const body = textOf(m.message).trim();
				if (!body) continue;
				chunks.push(`## ${m.role} (seq ${ev.seq})`, "", body, "");
			}
			const outPath = join(cwd, `dsh-context-${new Date().toISOString().replace(/[:.]/g, "-")}.md`);
			writeFileSync(outPath, chunks.join("\n"), "utf8");
			return { kind: "success", text: `上下文已导出到 ${outPath}` };
		},
	});
}
