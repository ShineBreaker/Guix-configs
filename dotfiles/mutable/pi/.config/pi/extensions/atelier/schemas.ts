// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 参数 Schema — 使用 TypeBox 定义 subagent 工具的输入参数类型
 */

import { Type } from "typebox";

/** 单个任务条目：agent 名 + 任务描述 + 可选 cwd */
const TaskItem = Type.Object({
	agent: Type.String({ description: "Agent 名称" }),
	task: Type.String({ description: "任务描述" }),
	cwd: Type.Optional(Type.String({ description: "工作目录" })),
});

/** subagent 工具的完整参数 schema */
export const SubagentParams = Type.Object({
	agent: Type.Optional(Type.String({ description: "Agent 名称（single 模式）" })),
	task: Type.Optional(
		Type.String({ description: "任务描述（single 模式，或 chain 模式的根任务）" }),
	),
	tasks: Type.Optional(Type.Array(TaskItem, { description: "并行任务数组" })),
	chain: Type.Optional(
		Type.Array(TaskItem, {
			description: "串行任务链；可在 task 中使用 {previous} 和 {task}",
		}),
	),
	action: Type.Optional(
		Type.Union([Type.Literal("list"), Type.Literal("status")], {
			description: "管理动作",
		}),
	),
	id: Type.Optional(Type.String({ description: "查看指定 run-id 的状态" })),
	cwd: Type.Optional(Type.String({ description: "工作目录覆盖" })),
	model: Type.Optional(Type.String({ description: "模型覆盖" })),
	thinking: Type.Optional(
		Type.Union(
			[
				Type.Literal("off"),
				Type.Literal("minimal"),
				Type.Literal("low"),
				Type.Literal("medium"),
				Type.Literal("high"),
				Type.Literal("xhigh"),
			],
			{
				description: "思考级别",
			},
		),
	),
	images: Type.Optional(
		Type.Array(Type.String(), {
			description: "图片文件路径数组，传递给 visual agent 分析",
		}),
	),
});
