// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * plugin-bridge.ts — 与本地插件的最小化交互层
 *
 * 设计约束（来自 reviewer 2026-06-25-0716.md CRITICAL #1）：
 * - 不复制 global-context 扩展的 listConfiguredFiles() 完整逻辑（100 行）
 * - 仅读 settings.json 的 globalContext 配置，解析 contextDir 后
 *   用 readdirSync 统计 .md 文件数
 * - 从 pi API 拿真实的工具/命令/主题列表（不重新扫描文件系统）
 *
 * 未来扩展点（占位，未启用）：
 * - atelier subagent 状态：需要 atelier 暴露 status 接口
 * - agenote-hooks 健康度：需要其暴露健康度 API
 * 第一版不实现，避免凭空推测 API 形状。
 */
import { execSync } from "node:child_process";
import { existsSync, readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { homedir } from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { expandEnvPath, type Settings } from "./xdg-settings.ts";

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

  // 静默使用 existsSync 检测（避免 IDE 警告）
  void existsSync;

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
 */
export function collectLoaded(
  pi: ExtensionAPI,
): Pick<LoadedCounts, "tools" | "commands" | "skills"> {
  const tools = pi.getAllTools();
  const commands = pi.getCommands();

  // 技能 = commands 中 source === "skill" 的子集
  const skills = commands.filter((c: unknown) => {
    const src = (c as { source?: string }).source;
    return src === "skill";
  }).length;

  return {
    tools: tools.length,
    commands: commands.length,
    skills,
  };
}

/**
 * 当前项目目录下最近 N 个会话。
 * 第一版未使用 — 完整实现需要 ctx.sessionManager.list(ctx.cwd)，
 * 但 sessionManager 在 session_start 时 cwd 可能尚未稳定。
 */
export interface RecentSessionInfo {
  name: string;
  age: string | null;
}

/**
 * 把 mtime ms 转成 "5m ago" / "2h ago" / "3d ago" / "just now" 格式。
 */
export function formatTimeAgo(ms: number): string {
  const now = Date.now();
  const seconds = Math.floor((now - ms) / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  if (days < 30) return `${Math.floor(days / 7)}w ago`;
  return `${Math.floor(days / 30)}mo ago`;
}
