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
import { DEFAULT_CONFIG, type SubagentConfig } from "./types.ts";

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
  };
}
