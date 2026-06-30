// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * plugin-bridge.ts — 与本地插件的最小化交互层 + 数据采集。
 *
 * 设计约束（来自 reviewer 2026-06-25-0716.md CRITICAL #1）：
 * - 不复制 global-context 扩展的 listConfiguredFiles() 完整逻辑（100 行）
 * - 仅读 settings.json 的 globalContext 配置，解析 contextDir 后
 *   用 readdirSync 统计 .md 文件数
 * - 从 pi API 拿真实的工具/命令/主题列表（不重新扫描文件系统）
 *
 * collectRecentSessions 用 SessionManager.list(cwd)（pi 公开 API），
 * 不再 readdirSync sessions 目录（plan v2 里 pi-powerline-footer 的反模式）。
 */
import { execSync } from "node:child_process";
import { existsSync, readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { homedir } from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { SessionManager } from "@earendil-works/pi-coding-agent";
import { expandEnvPath, type Settings } from "./settings.ts";
import { formatTimeAgo } from "../shared/format.ts";

/** global-context 实际会注入的 context 文件摘要 */
export interface ContextFileSummary {
  /** 解析后的绝对路径 */
  resolved: string;
  /** 文件大小（字节），不存在时为 0 */
  size: number;
  /** 是否能读取（存在 + 可读 + 实际是文件） */
  readable: boolean;
}

/** Loaded 区段总览 */
export interface LoadedCounts {
  contextFiles: ContextFileSummary[];
  /** pi 报告的工具总数（包含内置 + 扩展） */
  tools: number;
  /** pi 报告的斜杠命令总数 */
  commands: number;
  /** 已加载的技能数 */
  skills: number;
  /** 本地扩展数（~/.config/pi/extensions/） */
  extensions: number;
  /** pi prompt templates 数（~/.config/pi/prompts/） */
  templates: number;
}

/** 当前项目下最近 N 个会话的展示信息（供 welcome 屏 Recent 区） */
export interface RecentSessionInfo {
  /** 显示名（优先 session name，回退首条消息摘要，再回退 id） */
  name: string;
  /** 相对时间（如 "5m ago"），供 UI 展示；null 表示无法判断 */
  age: string | null;
}

// ═══════════════════════════════════════════════════════════════════════════
// 本地扩展与模板目录扫描
// ═══════════════════════════════════════════════════════════════════════════

/** 计算本地扩展目录里的扩展数 */
export function discoverLocalExtensions(): number {
  const dir = join(homedir(), ".config", "pi", "extensions");
  if (!existsSync(dir)) return 0;
  try {
    const entries = readdirSync(dir);
    return entries.filter((e) => {
      if (e.startsWith(".")) return false;
      const full = join(dir, e);
      try {
        const stat = statSync(full);
        if (!stat.isDirectory()) return false;
        return (
          existsSync(join(full, "index.ts")) ||
          existsSync(join(full, "index.js")) ||
          existsSync(join(full, "package.json"))
        );
      } catch {
        return false;
      }
    }).length;
  } catch {
    return 0;
  }
}

/** 计算本地 prompt template 数（~/.config/pi/prompts/ 与 ~/.config/pi/commands/） */
export function discoverLocalTemplates(): number {
  const candidates = [
    join(homedir(), ".config", "pi", "prompts"),
    join(homedir(), ".config", "pi", "commands"),
  ];
  let count = 0;
  const seen = new Set<string>();
  for (const dir of candidates) {
    if (!existsSync(dir)) continue;
    try {
      const entries = readdirSync(dir);
      for (const entry of entries) {
        if (!entry.endsWith(".md")) continue;
        const name = entry.slice(0, -3);
        if (seen.has(name)) continue;
        seen.add(name);
        count++;
      }
    } catch {
      // skip
    }
  }
  return count;
}

// ═══════════════════════════════════════════════════════════════════════════
// Recent sessions（SessionManager.list 公开 API）
// ═══════════════════════════════════════════════════════════════════════════

/**
 * 列出当前项目目录下最近 N 个会话。
 *
 * 用 pi 公开的 SessionManager.list(cwd)（静态方法），按 modified 降序取前 N。
 * 展示名优先级：name → firstMessage 首行截断 → id。
 *
 * 异步：SessionManager.list 返回 Promise，调用方（index.ts session_start）
 * 需 await；首次渲染用空数组占位，加载完成后由调用方触发 requestRender。
 *
 * 失败（session 目录不可读等）静默返回 []，不影响 welcome 屏渲染。
 */
export async function collectRecentSessions(
  cwd: string,
  limit = 3,
): Promise<RecentSessionInfo[]> {
  try {
    const sessions = await SessionManager.list(cwd);
    // 过滤掉无修改时间的脏数据，按 modified 降序
    const sorted = sessions
      .filter((s) => s.modified instanceof Date)
      .sort((a, b) => b.modified.getTime() - a.modified.getTime())
      .slice(0, limit);
    return sorted.map((s) => {
      const name = pickSessionName(s);
      const age = formatTimeAgo(s.modified.getTime());
      return { name, age };
    });
  } catch {
    return [];
  }
}

/** 从 SessionInfo 选展示名：name → firstMessage 首行 → id */
function pickSessionName(s: {
  name?: string;
  firstMessage: string;
  id: string;
}): string {
  if (s.name && s.name.trim()) return s.name.trim();
  // firstMessage 可能含换行，取首行并截断
  const firstLine = s.firstMessage.split("\n")[0]?.trim() ?? "";
  if (firstLine) {
    return firstLine.length > 40 ? `${firstLine.slice(0, 37)}...` : firstLine;
  }
  return s.id;
}

// ═══════════════════════════════════════════════════════════════════════════
// Agenote 健康度（运行 agenote_cli health 解析）
// ═══════════════════════════════════════════════════════════════════════════

export type MetricStatus = "ok" | "warn" | "error";

/** 单个健康度指标 */
export interface AgenoteMetric {
  /** 中文名（孤立率/过时率/类型偏斜/薄弱类别） */
  name: string;
  /** 数值（可能含百分号、千分位） */
  value: string;
  /** 阈值描述（如 "<15%" / "≥3"） */
  threshold: string;
  /** 阈值方向（lt: 值越小越好; gt: 值越大越好; le: 值≤阈值 ok） */
  direction: "lt" | "gt" | "le" | "ge";
  /** 阈值（从 threshold 中解析出的数字） */
  thresholdNum: number;
  /** 状态 */
  status: MetricStatus;
}

/** 卡片状态计数 */
export interface AgenoteCardStats {
  total: number;
  done: number;
  stable: number;
  stale: number;
  archived: number;
}

export interface AgenoteHealth {
  available: boolean;
  cards: AgenoteCardStats;
  metrics: AgenoteMetric[];
  feedback: { total: number; stale: number };
  projectCount: number;
  /** 加载错误信息（available=false 时设置） */
  error?: string;
}

const KB_SCRIPT = join(homedir(), ".local", "bin", "agenote_cli.py");

/**
 * 运行 `agenote_cli health`，解析输出。
 * 失败时返回 available=false 的结果（不抛错）。
 *
 * 注意：agenote 已改造为 MCP server，agent 主循环经 MCP tool 调用。
 * 但 pi-ui 扩展（ExtensionAPI 无 MCP 调用接口）走轻量 CLI shim。
 */
export function runAgenoteHealth(): AgenoteHealth {
  const empty: AgenoteHealth = {
    available: false,
    cards: { total: 0, done: 0, stable: 0, stale: 0, archived: 0 },
    metrics: [],
    feedback: { total: 0, stale: 0 },
    projectCount: 0,
  };

  let raw: string;
  try {
    raw = execSync(`python3 "${KB_SCRIPT}" health`, {
      encoding: "utf-8",
      timeout: 15000,
      stdio: ["pipe", "pipe", "pipe"],
    });
  } catch (err) {
    return {
      ...empty,
      error: `agenote_cli 命令失败：${(err as Error).message.split("\n")[0]}`,
    };
  }

  return parseAgenoteHealth(raw);
}

/** 解析 agenote_cli health 的输出文本 */
function parseAgenoteHealth(raw: string): AgenoteHealth {
  const result: AgenoteHealth = {
    available: true,
    cards: { total: 0, done: 0, stable: 0, stale: 0, archived: 0 },
    metrics: [],
    feedback: { total: 0, stale: 0 },
    projectCount: 0,
  };

  const lines = raw.split("\n");

  for (const line of lines) {
    const trimmed = line.trim();

    // 卡片计数行：总卡片: 2 | done: 2 | stable: 0 | stale: 0 | archived: 0
    if (trimmed.startsWith("总卡片:")) {
      const cards = trimmed.split("|").map((s) => s.trim());
      for (const card of cards) {
        const m = card.match(/^(.+?):\s*(\d+)/);
        if (!m) continue;
        const key = m[1].trim();
        const val = Number(m[2]);
        if (key === "总卡片") result.cards.total = val;
        else if (key === "done") result.cards.done = val;
        else if (key === "stable") result.cards.stable = val;
        else if (key === "stale") result.cards.stale = val;
        else if (key === "archived") result.cards.archived = val;
      }
      continue;
    }

    // 健康指标行：孤立率: 100% [阈值 <15%] ❌
    // emoji 可能是单个 codepoint 或 + variation selector (U+FE0F)
    const metricMatch = trimmed.match(
      /^(.+?):\s*(.+?)\s*\[阈值\s*(.+?)\]\s*([\u2705\u26A0\u274C]\uFE0F?)$/,
    );
    if (metricMatch) {
      const name = metricMatch[1].trim();
      const value = metricMatch[2].trim();
      const threshold = metricMatch[3].trim();
      const icon = metricMatch[4];

      const directionMatch = threshold.match(/^([<>≤≥]=?)\s*(.+)$/);
      let direction: AgenoteMetric["direction"] = "lt";
      let thresholdNum = 0;
      if (directionMatch) {
        const op = directionMatch[1];
        const numStr = directionMatch[2].replace("%", "");
        thresholdNum = Number(numStr);
        if (op === "<" || op === "≤") direction = "lt";
        else if (op === "≥") direction = "ge";
      }

      // 根据 icon 确定状态（去掉可选的 variation selector U+FE0F）
      const iconBase = icon.replace(/\uFE0F$/, "");
      let status: MetricStatus = "ok";
      if (iconBase === "\u2705") status = "ok";
      else if (iconBase === "\u26A0") status = "warn";
      else if (iconBase === "\u274C") status = "error";

      result.metrics.push({
        name,
        value,
        threshold,
        direction,
        thresholdNum,
        status,
      });
      continue;
    }

    // feedback: 0 (stale: 0) ⚠️
    const feedbackMatch = trimmed.match(
      /^feedback:\s*(\d+)\s*\(stale:\s*(\d+)\)/,
    );
    if (feedbackMatch) {
      result.feedback = {
        total: Number(feedbackMatch[1]),
        stale: Number(feedbackMatch[2]),
      };
      continue;
    }
    // project: 0
    const projectMatch = trimmed.match(/^project:\s*(\d+)/);
    if (projectMatch) {
      result.projectCount = Number(projectMatch[1]);
    }
  }

  return result;
}

/**
 * 从 settings.json 读取 globalContext 配置，列出 contextDir 内的 .md 文件。
 *
 * 与 global-context 扩展的区别：
 * - 这里只看 contextDir + files 列表，不复制 listConfiguredFiles 的
 *   extraFiles / maxBytes 截断等完整注入逻辑
 * - 只为欢迎屏展示"已加载 N 个 context 文件"
 * - 实际注入哪些文件以 global-context 扩展自身的 before_agent_start
 *   hook 为准 —— 我们只在 UI 上展示，不替代其行为
 */
export function discoverContextFiles(settings: Settings): ContextFileSummary[] {
  const config = settings.globalContext;
  if (!config) return [];

  const maxFiles = config.maxFiles ?? 8;
  const results: ContextFileSummary[] = [];

  // 1) 解析 contextDir
  if (config.contextDir) {
    const dirRaw = expandEnvPath(config.contextDir);
    const contextDir = resolve(
      dirRaw.startsWith("~") ? dirRaw.replace(/^~/, homedir()) : dirRaw,
    );

    let candidates: string[];
    if (config.files && config.files.length > 0) {
      // 显式 files[] 模式
      candidates = config.files.map((f) =>
        f.startsWith("/") || f.startsWith("~") || f.includes("$")
          ? expandEnvPath(f)
          : join(contextDir, f),
      );
    } else {
      // 扫 contextDir 下所有 .md
      try {
        const entries = readdirSync(contextDir).sort();
        candidates = entries
          .filter((f) => f.endsWith(".md"))
          .map((f) => join(contextDir, f));
      } catch {
        candidates = [];
      }
    }

    for (const filePath of candidates.slice(0, maxFiles)) {
      try {
        const stat = statSync(filePath);
        if (stat.isFile()) {
          results.push({
            resolved: filePath,
            size: stat.size,
            readable: true,
          });
          continue;
        }
      } catch {
        // 文件不存在或不可读
      }
      results.push({
        resolved: filePath,
        size: 0,
        readable: false,
      });
    }
  }

  // 2) extraFiles（追加，不替换）
  if (config.extraFiles && config.extraFiles.length > 0) {
    const remaining = Math.max(0, maxFiles - results.length);
    for (const raw of config.extraFiles.slice(0, remaining)) {
      const resolved = resolve(expandEnvPath(raw));
      try {
        const stat = statSync(resolved);
        if (stat.isFile()) {
          results.push({ resolved, size: stat.size, readable: true });
          continue;
        }
      } catch {
        // skip
      }
      results.push({ resolved, size: 0, readable: false });
    }
  }

  return results;
}

/**
 * 从 pi API 收集 Loaded 数据。
 *
 * 关键发现（runtime 调研）：getAllTools / getCommands 在 0.78.1 实际挂在
 * ExtensionAPI（pi）上，由 loader.js 通过共享 runtime 代理：
 *   bindCore() 时 → this.runtime.getAllTools = actions.getAllTools
 *   ExtensionContext（事件回调里的 ctx）只暴露 model/getContextUsage
 *   等数据查询方法，不含工具/命令 API。
 *
 * 因此必须在 factory 闭包里捕获 pi 引用，在事件回调（session_start
 * 已 bindCore 之后）通过 pi.getAllTools() 调用。
 *
 * 技能 = commands 中 source === "skill" 的子集（SlashCommandSource 字面量联合）。
 */
export function collectLoaded(
  pi: ExtensionAPI,
): Pick<LoadedCounts, "tools" | "commands" | "skills"> {
  const tools = pi.getAllTools();
  const commands = pi.getCommands();

  // 技能 = commands 中 source === "skill" 的子集
  const skills = commands.filter((c) => c.source === "skill").length;

  return {
    tools: tools.length,
    commands: commands.length,
    skills,
  };
}
