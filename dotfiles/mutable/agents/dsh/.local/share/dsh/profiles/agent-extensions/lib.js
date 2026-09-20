// SPDX-License-Identifier: MIT
//
// 内联的上游 helper —— 本包经 link: 部署，模块 realpath 落在仓库源目录，
// Node 的 node_modules 父级检索够不到 $DSH_HOME/profiles/node_modules 共享
// fallback，因此 @deepseek-ai/* 一律不导入，需要的纯函数在此复刻：
//   createUserMessage   ← @deepseek-ai/dsh-llm        （id + structuredClone + deepFreeze）
//   assembleContextFor  ← @deepseek-ai/dsh-agent      （{agent, scope:agent, signal?}）
//   renderPrompt        ← @deepseek-ai/dsh-system-prompt（section 渲染 + {{var}} 展开）
//   deadline/timeoutOf/TimeoutReason/TOOL_TIMEOUT
//                     ← @deepseek-ai/dsh-timeout + dsh-tool-call-timeout-policy
// 语义与上游保持一致；若上游改语义需手动同步（见各函数注释）。

import { randomUUID } from "node:crypto";

// ─── dsh-llm: createUserMessage ─────────────────────────────────────────────
// 上游：createMessage → freezeMessage = deepFreeze(structuredClone({...input, id}))
function deepFreeze(value) {
	if (value === null || typeof value !== "object") return value;
	for (const key of Object.keys(value)) deepFreeze(value[key]);
	return Object.freeze(value);
}

export function createUserMessage(input) {
	return deepFreeze(structuredClone({ ...input, role: "user", id: randomUUID() }));
}

// ─── dsh-agent: assembleContextFor ──────────────────────────────────────────
// 上游：{agent, scope: agent, ...signal?} —— scope 键即 agent 本体
export function assembleContextFor(agent, signal) {
	return { agent, scope: agent, ...(signal === undefined ? {} : { signal }) };
}

// ─── dsh-system-prompt: renderPrompt ────────────────────────────────────────
// 上游语义：section.interpolate===false → 原文；否则展开 {{name}} 引用
// assembly.variables；空 section 丢弃；非空按顺序 \n\n 连接。
const GROUP_AT = /^\{\{[^{}]*\}\}/;
const VARIABLE_NAME = /^[a-zA-Z0-9_-]+$/;

function interpolate(input, variables, kind) {
	const text = input.text;
	let result = "";
	let last = 0;
	for (let open = text.indexOf("{{"); open >= 0; open = text.indexOf("{{", last)) {
		const group = GROUP_AT.exec(text.slice(open));
		if (group === null) {
			if (text.indexOf("}}", open + 2) >= 0)
				throw new Error(`malformed prompt variable reference at "${text.slice(open, open + 16)}…" in ${kind} "${input.name}" (references are complete simple {{name}} groups)`);
			result += text.slice(last, open + 2);
			last = open + 2;
			continue;
		}
		const name = group[0].slice(2, -2);
		if (!VARIABLE_NAME.test(name))
			throw new Error(`malformed prompt variable reference "{{${name}}}" in ${kind} "${input.name}"`);
		if (!Object.hasOwn(variables, name)) {
			const known = Object.keys(variables);
			throw new Error(`unknown prompt variable "{{${name}}}" in ${kind} "${input.name}"; registered variables: ${known.length > 0 ? known.join(", ") : "(none)"}`);
		}
		const value = variables[name];
		if (value === undefined) throw new Error(`prompt variable "{{${name}}}" has no value for this assembly (${kind} "${input.name}")`);
		result += text.slice(last, open) + value;
		last = open + group[0].length;
	}
	return result + text.slice(last);
}

export function renderPrompt(assembly) {
	return assembly.sections
		.map((section) => (section.interpolate === false ? section.text : interpolate(section, assembly.variables, "section")))
		.filter((text) => text.length > 0)
		.join("\n\n");
}

// ─── dsh-timeout: TimeoutReason / deadline / timeoutOf ──────────────────────
// 上游语义：deadline 计时器触发时以 TimeoutReason(code, timeoutMs) 为 reason
// abort；timeoutOf 只认本插件 code 的 TimeoutReason（外来 code 走普通取消路径）。
export class TimeoutReason extends Error {
	constructor(code, timeoutMs) {
		super(`timed out after ${timeoutMs}ms`);
		this.name = "TimeoutError";
		this.code = code;
		this.timeoutMs = timeoutMs;
	}
}

export function deadline(upstream, timeoutMs, code) {
	if (timeoutMs <= 0) {
		return { signal: upstream ?? new AbortController().signal, [Symbol.dispose]() {} };
	}
	const timer = new AbortController();
	const id = setTimeout(() => timer.abort(new TimeoutReason(code, timeoutMs)), timeoutMs);
	return {
		signal: upstream !== undefined ? AbortSignal.any([upstream, timer.signal]) : timer.signal,
		[Symbol.dispose]() {
			clearTimeout(id);
		},
	};
}

export function timeoutOf(x, code) {
	const reason = x.reason;
	if (!(reason instanceof TimeoutReason)) return undefined;
	return code === undefined || reason.code === code ? reason : undefined;
}

// ─── dsh-tool-call-timeout-policy: TOOL_TIMEOUT ─────────────────────────────
export const TOOL_TIMEOUT = "TOOL_TIMEOUT";
