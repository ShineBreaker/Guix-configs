// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Completion Gate (PR-8)
 *
 * 参考 MiMoCode `actor/spawn.ts:407-466` + `task/gate.ts`:
 *   即便 worker 在 return header 里写 "**Status**: success",
 *   也要扫 task list（pi task 工具创建的），若仍有 open/in_progress 就降级为 partial 并自动 re-run。
 *
 * 当前项目现实（2026-06-29 实测）:
 *   - 6 个 agent (worker / scout / oracle / reviewer / researcher / planner / visual) 都没用过 pi 的 task 工具
 *   - 因此 `isTaskToolAvailable()` 当前**总是返回 false** → gate 永远 no-op
 *   - 架构保留是为未来 task tool 接入时不需要重写
 *
 * oracle 评估: 本阶段 gate 触发场景可能为 0。但用户决策**实施**(作为预防基建),
 * 故本模块保留完整接口 + agent 白名单 + MAX_REENTRY 硬上限,降低未来改造成本。
 *
 * 设计:
 *   - MAX_REENTRY = 2: 硬上限(抄 MiMoCode `MAX_TASK_GATE_SUBAGENT_REACT = 2`)
 *   - READ_ONLY_AGENTS: 这些 agent 永远不触发 gate(就算将来 isTaskToolAvailable=true)
 *   - decide() 三种返回:
 *       { needReentry: false }                              — 放过(常态)
 *       { needReentry: true,  reentryText: "..." }          — 自动 re-run 一次
 *       { needReentry: false, downgradedTo: "partial" }     — 已知 incomplete,降级
 */

import type { RunStatus } from "./registry.ts";

/** PR-8: 防止无限 reentry 的硬上限(抄 MiMoCode `MAX_TASK_GATE_SUBAGENT_REACT = 2`) */
export const MAX_REENTRY = 2;

/**
 * 只读 agent 白名单——这些 agent 不可能"留了 task 没完成",永不走 gate。
 *
 * 设计动机:
 *   - scout 只读,扫一圈就给结果;没有"task"
 *   - oracle 审查型,产出是建议而非任务
 *   - reviewer 验证型,产出是 verdict
 *   - visual 感知型,产出是图片描述
 */
export const READ_ONLY_AGENTS: Set<string> = new Set([
  "scout",
  "oracle",
  "reviewer",
  "visual",
]);

/**
 * 检查当前 pi 主进程是否引入了 task 工具(创建/管理 task list)。
 *
 * 本阶段此函数**总是返回 false**:
 *   - pi 当前没有 task 工具绑定;agent 不会用 task 工具
 *   - return false 让 gate 永远 no-op;架构保留待未来接入
 *
 * 接入 task tool 时,这里改为读 ctx.model / plugin / MCP 配置判断。
 */
export function isTaskToolAvailable(): boolean {
  return false;
}

/** decide 返回值 */
export type GateDecision =
  | { needReentry: false; downgradedTo?: RunStatus }
  | { needReentry: true; reentryText: string; downgradedTo?: RunStatus };

/**
 * 是否对当前 run 调用 completion gate。
 *
 * @param runId          当前 run 的 ID(诊断用)
 * @param agentName      agent 名(如 "worker" / "scout")
 * @param currentReentryCount 当前已经 reentry 过的次数
 * @returns GateDecision
 *
 * no-op 路径(`isTaskToolAvailable=false`):
 *   - 永远返回 { needReentry: false }
 *
 * reentry cap(`currentReentryCount >= MAX_REENTRY`):
 *   - 即使将来 task tool 接入了,达到硬上限也降级 partial 而不无限循环
 */
export function decide(
  runId: string,
  agentName: string,
  currentReentryCount: number,
): GateDecision {
  // 1. 硬上限检查(任何情况下都生效,防止未来 task tool 接入时死循环)
  if (currentReentryCount >= MAX_REENTRY) {
    return {
      needReentry: false,
      downgradedTo: "partial",
    };
  }

  // 2. 只读 agent 永远不 gate
  if (READ_ONLY_AGENTS.has(agentName)) {
    return { needReentry: false };
  }

  // 3. 任务工具未接入 → 架构保留路径,no-op
  if (!isTaskToolAvailable()) {
    return { needReentry: false };
  }

  // 4. 接入 task tool 后的真实分支(本阶段未激活):
  // 这里会调 task_registry.listOpenTasksForActor(runId) 查 open/in_progress tasks,
  // 若有 open → 返回 { needReentry: true, reentryText: "..." }
  // 若已完成 → { needReentry: false }
  // 接口已备好,等待 task tool 真实落地时填充
  return { needReentry: false };
}

/** debug helper:报告当前 gate 状态(供 status / debug 使用) */
export function gateStatus(): {
  taskToolAvailable: boolean;
  maxReentry: number;
  readOnlyAgents: string[];
} {
  return {
    taskToolAvailable: isTaskToolAvailable(),
    maxReentry: MAX_REENTRY,
    readOnlyAgents: Array.from(READ_ONLY_AGENTS),
  };
}
