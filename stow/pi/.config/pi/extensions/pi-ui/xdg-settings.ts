// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * xdg-settings.ts — settings.json 读取工具
 *
 * 设计原则：
 * - 不重新发明轮子：复用 pi 的 getAgentDir() 确定配置文件位置
 * - 静默降级：文件不存在、不可读、JSON 损坏时返回 {}，不抛错
 * - 类型友好：暴露的 Settings interface 是 union typed，避免 pi-ui 内部到处断言
 *
 * 注：早期版本曾用 ~/.pi/agent/settings.json 硬编码路径（来自
 * pi-powerline-footer 0.5.6 的做法），已删除。详见 .agents/workfile/reviewer/
 * 2026-06-25-0716.md 的"条件批准"审查报告 CRITICAL #2。
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

/**
 * Settings schema — 仅声明 pi-ui 实际读取的字段，其他原样透传。
 */
export interface Settings {
  readonly quietStartup?: boolean;
  readonly globalContext?: {
    enabled?: boolean;
    contextDir?: string;
    files?: readonly string[];
    extraFiles?: readonly string[];
    maxFiles?: number;
    maxBytesPerFile?: number;
    maxTotalBytes?: number;
  };
  readonly [key: string]: unknown;
}

/**
 * 解析 settings.json 路径。
 * 优先 pi 的 getSettingsPath()（其内部走 $PI_AGENT_DIR / $XDG_CONFIG_HOME/pi），
 * 兜底用 join(getAgentDir(), "settings.json")。
 */
export function resolveSettingsPath(): string {
  // getAgentDir() 已经返回 XDG 兼容路径（~/.config/pi）
  // join 出来就是 $XDG_CONFIG_HOME/pi/settings.json
  return join(getAgentDir(), "settings.json");
}

/**
 * 读取 settings.json，失败时返回空对象。
 *
 * 不抛错。错误一律静默吞掉，因为 pi-ui 是纯装饰性扩展，任何
 * 配置问题都不应该导致 pi 启动失败。
 */
export function readSettings(): Settings {
  const path = resolveSettingsPath();
  try {
    const raw = readFileSync(path, "utf8");
    const parsed: unknown = JSON.parse(raw);
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      return {};
    }
    return parsed as Settings;
  } catch {
    // ENOENT / EACCES / JSON.parse error — 静默降级
    return {};
  }
}

/**
 * 展开路径中的环境变量引用。轻量版：只支持 $HOME、$XDG_*、${...} 包裹。
 *
 * 不替代 global-context 插件内部的 resolveConfiguredPath —— 这里只用于
 * 解析 settings.json 中写的路径字符串，不解析嵌套别名或上下文。
 */
export function expandEnvPath(input: string): string {
  const home = process.env.HOME ?? "";
  let expanded = input;
  if (expanded === "~") expanded = home;
  else if (expanded.startsWith("~/")) expanded = home + expanded.slice(1);
  expanded = expanded.replace(
    /\$([A-Z_][A-Z0-9_]*)|\$\{([A-Z_][A-Z0-9_]*)\}/g,
    (_match, bare, braced) => {
      const key: string = bare ?? braced ?? "";
      const value = process.env[key];
      if (value !== undefined) return value;
      switch (key) {
        case "HOME":
          return home;
        case "XDG_CONFIG_HOME":
          return home + "/.config";
        case "XDG_DATA_HOME":
          return home + "/.local/share";
        case "XDG_CACHE_HOME":
          return home + "/.cache";
        default:
          return "";
      }
    },
  );
  return expanded;
}
