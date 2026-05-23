// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * custom-shortcuts extension
 *
 * 自定义快捷键覆盖，用于替换默认绑定。
 * 当前映射：
 *   - Shift+Tab → 切换 plannotator plan 模式（覆盖默认的 app.thinking.cycle）
 *
 * 需配合 ~/.pi/agent/keybindings.json 解除对应按键的默认绑定。
 *
 * ── 实现原理 ──────────────────────────────────────────────────────
 *
 * Pi 的斜杠命令（如 /plannotator）只在编辑器 onSubmit 流程中被解析。
 * 扩展 API（pi.sendUserMessage）会绕过命令解析，直接发给 LLM，
 * 所以我们必须走编辑器提交路径。
 *
 * onTerminalInput 在编辑器 handleInput 之前执行，可以拦截并替换输入数据：
 *   - 匹配到 Shift+Tab 时，先 setEditorText 写入 "/plannotator"
 *   - 返回 { data: "\r" } 将原始按键替换为回车键
 *   - 编辑器收到 "\r" 后走正常的 Enter → onSubmit → 斜杠命令解析流程
 *
 * 副作用：onSubmit 会同步调用 setText("") 清空编辑器，
 * 因此用户之前输入的内容会丢失。用 setTimeout 在清空后恢复。
 *
 * 使用 matchesKey 而非硬编码转义序列，兼容 Kitty 键盘协议。
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { matchesKey } from "@earendil-works/pi-tui";

export default function customShortcuts(pi: ExtensionAPI): void {
	let unsubscribe: (() => void) | undefined;

	pi.on("session_start", (_event, ctx) => {
		const ui = ctx.ui;

		unsubscribe = ui.onTerminalInput((data) => {
			if (!matchesKey(data, "shift+tab")) return undefined;

			// 保存用户当前输入
			const saved = ui.getEditorText();

			// 写入斜杠命令
			ui.setEditorText("/plannotator");

			// 将按键替换为回车，让编辑器走 onSubmit → 斜杠命令解析
			// onSubmit 会同步清空编辑器，用 setTimeout 在清空后恢复用户输入
			if (saved) {
				setTimeout(() => ui.setEditorText(saved), 0);
			}

			return { consume: false, data: "\r" };
		});
	});

	pi.on("session_shutdown", () => {
		unsubscribe?.();
		unsubscribe = undefined;
	});
}
