// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 配置加载 — 从 settings.json 的 atelier 字段加载运行时配置
 *
 * 查找顺序：agent dir/settings.json → ~/.config/pi/settings.json
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

export function loadConfig(): SubagentConfig {
  const candidates = [
    path.join(getAgentDir(), "settings.json"),
    path.join(os.homedir(), ".config", "pi", "settings.json"),
  ];

  let raw: Record<string, unknown> | undefined;
  for (const settingsPath of candidates) {
    if (!existsSync(settingsPath)) continue;
    try {
      raw = JSON.parse(readFileSync(settingsPath, "utf8"))?.atelier as
        | Record<string, unknown>
        | undefined;
      if (raw) break;
    } catch {
      continue;
    }
  }

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
