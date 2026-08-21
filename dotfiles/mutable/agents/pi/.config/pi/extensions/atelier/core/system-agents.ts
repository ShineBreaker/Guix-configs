// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * System-spawned Agent 分类 (PR-9)
 *
 * 参考 MiMoCode `agent/config.ts:5`:
 *   `SYSTEM_SPAWNED_AGENT_TYPES = { checkpoint-writer, dream, distill }`
 *
 * 系统子 agent 是"系统管家的子 agent",与"用户子 agent"分开管理:
 *   - 默认不出现在 `/atelier list` 里(避免污染)
 *   - 系统 agent 不触发 inbox 通知(自己通知自己无意义)
 *   - session-summary 默认排除(避免日志被系统噪音覆盖)
 *
 * 本机实际启动系统子 agent 的命令还未存在(等 PLAN.md 第一部分的
 * `atelier-dream` / `atelier-distill` 上线才会有代码触发);但本模块
 * 已定义类型、runId 生成、查询接口,系统命令接入时不需要改 schema。
 */

import * as crypto from "node:crypto";

/**
 * 系统子 agent 白名单。
 *
 * 未来真正运行这些 agent 的代码会在 `index.ts` 注册 `/atelier-dream`、
 * `/atelier-distill` 之类的系统命令,启动时通过 `registerRun({ isSystemSpawned: true })`
 * 显式标记。`isSystemAgent()` 同时支持按白名单判断(对未传入 isSystemSpawned 的场合)
 * 和直接根据传入判断。
 */
export const SYSTEM_SPAWNED_AGENT_TYPES: Set<string> = new Set([
  "atelier-dream",
  "atelier-distill",
  "atelier-checkpoint-writer",
]);

/**
 * 判断一个 agent 名是否属于系统子 agent。
 *
 * 判断维度(任一为真即 true):
 *   1. agentName 在白名单 SYSTEM_SPAWNED_AGENT_TYPES 内(直接命名匹配)
 *   2. agentName 以 `atelier-` 前缀开头(约定俗成,未来的 atelier-* 都视为系统 agent)
 *
 * 用法:
 *   - registerRun 时: `isSystemSpawned: isSystemAgent(agent.name)`
 *   - 查询时: `listRunning({ includeSystem: isSystemAgent(name) })`
 */
export function isSystemAgent(agentName: string): boolean {
  if (!agentName) return false;
  if (SYSTEM_SPAWNED_AGENT_TYPES.has(agentName)) return true;
  // 命名约定:atelier-* 前缀的 agent 默认视为系统 agent
  return agentName.startsWith("atelier-");
}

/**
 * 生成系统子 agent 的 runId(区别于用户的 sa- 前缀)。
 *
 * 格式:`sys-{agent}-{yyyymmdd}-{3bytehex}`
 *   - sys- 前缀便于在 registry/目录扫描时一眼区分
 *   - date 部分便于人按日期排序
 *   - 3bytehex 与 launcher.generateRunId() 兼容(避免撞 hash 空间)
 *
 * 与 launcher.generateRunId() (sa- 前缀) 不冲突,因为前缀不同。
 */
export function generateSystemRunId(agentName: string): string {
  const now = new Date();
  const yyyymmdd =
    now.getFullYear().toString() +
    String(now.getMonth() + 1).padStart(2, "0") +
    String(now.getDate()).padStart(2, "0");
  const hash = crypto.randomBytes(3).toString("hex");
  // agent 名中可能含连字符,只保留基本字符避免文件名问题
  const safeAgent = agentName.replace(/[^a-zA-Z0-9_-]/g, "_");
  return `sys-${safeAgent}-${yyyymmdd}-${hash}`;
}

/** debug helper */
export function listSystemAgentTypes(): string[] {
  return Array.from(SYSTEM_SPAWNED_AGENT_TYPES);
}
