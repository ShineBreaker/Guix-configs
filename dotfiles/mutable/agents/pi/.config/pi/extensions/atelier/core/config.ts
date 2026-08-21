// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 配置加载 — 从独立 atelier.json 或 settings.json 的 atelier 字段加载运行时配置
 *
 * 查找顺序（先找到的赢，跳过剩余候选）：
 *   1. ~/.config/pi/atelier.json（独立配置文件，推荐）
 *   2. agent dir/settings.json 的 atelier 字段
 *   3. ~/.config/pi/settings.json 的 atelier 字段
 *
 * 独立文件优先：便于整体管理 atelier 配置（tier/schedule/timings 等），
 * 不与 pi 本身的 settings.json 混杂。两种路径解析出的对象结构一致，
 * 共用同一个 raw → SubagentConfig 的映射逻辑。
 */

import { existsSync, readFileSync } from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { getAgentDir } from "@earendil-works/pi-coding-agent";
import {
  DEFAULT_CONFIG,
  type AgentModelConfig,
  type SubagentConfig,
} from "./types.ts";

/**
 * 按优先级查找并解析 atelier 配置对象。
 *
 * 候选顺序：
 *   - `atelier.json` 独立文件：整个 JSON 即配置对象（无 atelier 包裹层）
 *   - `settings.json`：取 `atelier` 子字段（向后兼容）
 *
 * 返回第一个解析成功的候选；全部失败返回 undefined。
 */
function findRawConfig(): Record<string, unknown> | undefined {
  // 候选 [path, kind]：kind=standalone 整文件即配置；kind=nested 取 .atelier 子字段
  const candidates: Array<[string, "standalone" | "nested"]> = [
    [path.join(os.homedir(), ".config", "pi", "atelier.json"), "standalone"],
    [path.join(getAgentDir(), "settings.json"), "nested"],
    [path.join(os.homedir(), ".config", "pi", "settings.json"), "nested"],
  ];

  for (const [cfgPath, kind] of candidates) {
    if (!existsSync(cfgPath)) continue;
    try {
      const parsed = JSON.parse(readFileSync(cfgPath, "utf8"));
      const raw = kind === "standalone" ? parsed : parsed?.atelier;
      if (raw && typeof raw === "object") return raw as Record<string, unknown>;
    } catch {
      continue;
    }
  }
  return undefined;
}

export function loadConfig(): SubagentConfig {
  const raw = findRawConfig();
  if (!raw) return DEFAULT_CONFIG;
  return {
    pollIntervalMs:
      typeof raw.pollIntervalMs === "number"
        ? raw.pollIntervalMs
        : DEFAULT_CONFIG.pollIntervalMs,
    panePrefix:
      typeof raw.panePrefix === "string"
        ? raw.panePrefix
        : DEFAULT_CONFIG.panePrefix,
    keepResults:
      typeof raw.keepResults === "number"
        ? raw.keepResults
        : DEFAULT_CONFIG.keepResults,
    timeoutMs:
      typeof raw.timeoutMs === "number"
        ? raw.timeoutMs
        : DEFAULT_CONFIG.timeoutMs,
    maxTasks:
      typeof raw.maxTasks === "number" ? raw.maxTasks : DEFAULT_CONFIG.maxTasks,
    maxConcurrency:
      typeof raw.maxConcurrency === "number"
        ? raw.maxConcurrency
        : DEFAULT_CONFIG.maxConcurrency,
    defaultTier:
      typeof raw.defaultTier === "string"
        ? raw.defaultTier
        : DEFAULT_CONFIG.defaultTier,
    tiers: parseTiers(raw.tiers),
    modelSchedules: parseModelSchedules(raw.modelSchedules),
  };
}

/** 从 settings.json 的 atelier.tiers 段解析 tier 配置 */
function parseTiers(raw: unknown): Record<string, AgentModelConfig> {
  if (!raw || typeof raw !== "object") return DEFAULT_CONFIG.tiers;
  const result: Record<string, AgentModelConfig> = {};
  for (const [name, value] of Object.entries(raw)) {
    if (!value || typeof value !== "object") continue;
    const v = value as Record<string, unknown>;
    if (typeof v.model !== "string") continue;
    const fallback = Array.isArray(v.fallback)
      ? v.fallback.filter((f): f is string => typeof f === "string")
      : [];
    result[name] = { model: v.model, fallback };
  }
  return result;
}

/**
 * 从 atelier.modelSchedules 段解析 per-model 时段限制。
 *
 * 形状：`{ "zai/GLM-5.2": { deny: ["Mon-Fri 14:00-18:00"] } }`。
 * 非对象/缺字段 → 空对象（无限制）。条目语法错误由 schedule.ts 的
 * parseSchedule 在运行时兜底（warn + unrestricted），此处只做结构过滤。
 */
function parseModelSchedules(
  raw: unknown,
): Record<string, { allow?: string[]; deny?: string[] }> {
  if (!raw || typeof raw !== "object") return {};
  const result: Record<string, { allow?: string[]; deny?: string[] }> = {};
  for (const [model, value] of Object.entries(raw as Record<string, unknown>)) {
    if (!value || typeof value !== "object") continue;
    const v = value as { allow?: unknown; deny?: unknown };
    const allow = Array.isArray(v.allow)
      ? v.allow.filter((x): x is string => typeof x === "string")
      : undefined;
    const deny = Array.isArray(v.deny)
      ? v.deny.filter((x): x is string => typeof x === "string")
      : undefined;
    if (allow || deny) result[model] = { allow, deny };
  }
  return result;
}
