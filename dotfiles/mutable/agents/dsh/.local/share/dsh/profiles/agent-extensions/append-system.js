// SPDX-License-Identifier: MIT
//
// append-system — 主会话行为教义注入（pi APPEND_SYSTEM.md 的 dsh 移植）。
//
// 把 APPEND_SYSTEM.md（与插件同目录的随包文本，或 config.file 指定的路径）
// 作为 systemPrompt section 追加到每个请求的末尾。与 global-context 的分层
// 域注入互补：global-context 管「环境/项目事实」，本模块管「委派与编排
// 行为教义」——后者是主会话固有的，不分 cwd 门控。
//
// 配置（cordis 行 config.appendSystem）：
//   enabled: boolean  — 默认 true
//   file:    string   — 覆盖文本路径；缺省读随包 APPEND_SYSTEM.md

import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const inject = ["systemPrompt"];

const SECTION_NAME = "agent-extensions.append-system";
// global-context(10300) 与 gate 注入声明(10301) 之后
const SECTION_ORDER = 10302;
const BUNDLED_FILE = join(dirname(fileURLToPath(import.meta.url)), "APPEND_SYSTEM.md");

function injectionText(file) {
	try {
		const body = readFileSync(file, "utf8").trim();
		return body || "";
	} catch {
		return "";
	}
}

export function apply(ctx, config = {}) {
	if (config.enabled === false) return;
	const file = typeof config.file === "string" && config.file ? resolve(config.file) : BUNDLED_FILE;

	ctx.systemPrompt.section({
		name: SECTION_NAME,
		order: SECTION_ORDER,
		interpolate: false,
		text: () => {
			try {
				return injectionText(file);
			} catch (error) {
				ctx.logger.warn(`agent-append-system: injection failed: ${String(error)}`);
				return "";
			}
		},
	});
}
