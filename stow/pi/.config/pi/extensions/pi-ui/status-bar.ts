// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * status-bar.ts — starship 风格状态栏（替换 footer）
 *
 * 设计参考：
 *   - Emacs modeline.el：4 档宽度 (wide/medium/narrow/compact)、`·` 分隔、
 *     语义颜色、Nerd Font 图标优先 + 降级到空串
 *   - starship.toml：`·` 分隔符
 *   - pi-powerline-footer icons.ts：Nerd Font 图标码位
 *
 * 段顺序（按重要度）：model · path · git · thinking · context · tokens · timeSpent · time
 *
 * 宽度档（同 Emacs modeline）：
 *   - wide    (>= 120): 全部 8 段，完整信息
 *   - medium  (100-119): 省略 time，压缩次要段
 *   - narrow   (80-99):  省略 time + timeSpent + tokens，git 只显分支名
 *   - compact  (< 80):   只显 model · context%
 *
 * 颜色阈值（同 Emacs modeline + powerline-footer）：
 *   - context >90% → error（红色）
 *   - context >70% → warning（黄色）
 *   - context  ≤70% → dim
 *   - thinking high/xhigh → rainbow
 */

import { homedir } from "node:os";
import { basename } from "node:path";
import type {
  Theme,
  ReadonlyFooterDataProvider,
} from "@earendil-works/pi-coding-agent";
import type { Component } from "@earendil-works/pi-tui";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// ═══════════════════════════════════════════════════════════════════════════
// Nerd Font 检测 + 图标（与 welcome-box.ts 共享检测逻辑）
// ═══════════════════════════════════════════════════════════════════════════

function detectNerdFont(): boolean {
  if (process.env.POWERLINE_NERD_FONTS === "1") return true;
  if (process.env.POWERLINE_NERD_FONTS === "0") return false;
  if (process.env.GHOSTTY_RESOURCES_DIR) return true;
  const term = (process.env.TERM_PROGRAM ?? "").toLowerCase();
  if (
    term.includes("iterm") ||
    term.includes("wezterm") ||
    term.includes("kitty") ||
    term.includes("ghostty") ||
    term.includes("alacritty") ||
    term.includes("vscode") ||
    term.includes("hyper") ||
    term.includes("konsole") ||
    term.includes("foot") ||
    term.includes("tmux") ||
    term.includes("apple_terminal")
  ) {
    return true;
  }
  const colorTerm = (process.env.COLORTERM ?? "").toLowerCase();
  if (term.includes("gnome") && colorTerm.includes("truecolor")) return true;
  if (term.includes("xterm") && colorTerm.includes("truecolor")) return true;
  const termName = (process.env.TERM ?? "").toLowerCase();
  if (termName.includes("nerd") || termName.includes("nf-")) return true;
  // tmux 内假定外层 terminal 支持 Nerd Font
  if (process.env.TMUX) return true;
  return false;
}

const NF = detectNerdFont();

/**
 * 图标集：Nerd Font codepoint 从 pi-powerline-footer icons.ts 搬运，
 * 保证视觉一致性。ASCII 降级到简短的纯文本标识。
 */
const IC = {
  // model / AI chip
  model:         NF ? "\uEC19" : "m",
  // folder open
  folder:        NF ? "\uF115" : "dir",
  // git branch (code fork)
  branch:        NF ? "\uF126" : "b",
  // thinking/minimal: lightning bolt
  thinkMin:      NF ? "\uF0E7" : "T_",
  // thinking/low: circle outline
  thinkLow:      NF ? "\uF10C" : "T-",
  // thinking/medium: dot circle
  thinkMed:      NF ? "\uF192" : "T",
  // thinking/high: filled circle
  thinkHigh:     NF ? "\uF111" : "T+",
  // thinking/xhigh: fire
  thinkXHigh:    NF ? "\uF06D" : "T!",
  // tokens
  tokens:        NF ? "\uE26B" : "t",
  // context / database
  context:       NF ? "\uE70F" : "c",
  // dollar / cost
  cost:          NF ? "\uF155" : "$",
  // clock
  clock:         NF ? "\uF017" : "t",
  // separator（starship 风格 · ）
  sep:           " · ",
} as const;

// ═══════════════════════════════════════════════════════════════════════════
// 类型 + 宽度档
// ═══════════════════════════════════════════════════════════════════════════

export interface FooterState {
  modelName: string;
  thinkingLevel: string;
  cwd: string;
  gitBranch: string | null;
  contextPercent: number | null;
  contextTokens: number | null;
  contextWindow: number;
  sessionStartMs: number;
}

export type WidthTier = "wide" | "medium" | "narrow" | "compact";

export function getTier(width: number): WidthTier {
  if (width >= 120) return "wide";
  if (width >= 100) return "medium";
  if (width >= 80) return "narrow";
  return "compact";
}

export type ContextColor = "dim" | "warning" | "error";

export function contextColor(percent: number | null): ContextColor {
  if (percent === null) return "dim";
  if (percent >= 90) return "error";
  if (percent >= 70) return "warning";
  return "dim";
}

// ═══════════════════════════════════════════════════════════════════════════
// 各段渲染器
// ═══════════════════════════════════════════════════════════════════════════

function fmtTokens(n: number): string {
  if (n < 1000) return String(n);
  if (n < 10000) return `${(n / 1000).toFixed(1)}k`;
  if (n < 1000000) return `${Math.round(n / 1000)}k`;
  return `${(n / 1000000).toFixed(1)}M`;
}

function fmtDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const h = Math.floor(m / 60);
  if (h > 0) return `${h}h${m % 60}m`;
  if (m > 0) return `${m}m${s % 60}s`;
  return `${s}s`;
}

function iconText(icon: string, text: string): string {
  if (!text) return "";
  if (!icon) return text;
  return `${icon} ${text}`;
}

/** 模型名缩写（去掉 "Claude " 前缀） */
function shortModel(name: string): string {
  if (name.startsWith("Claude ")) return name.slice(7);
  return name;
}

// ── 各段 ──

function segPath(state: FooterState, theme: Theme): string {
  const pwd = basename(state.cwd || homedir()) || "?";
  return theme.fg("accent", iconText(IC.folder, pwd));
}

function segGit(state: FooterState, theme: Theme, tier: WidthTier): string {
  if (!state.gitBranch) return "";
  const branch = tier === "narrow"
    ? state.gitBranch
    : state.gitBranch;
  return theme.fg("accent", iconText(IC.branch, branch));
}

function segThinking(state: FooterState, theme: Theme): string {
  const level = state.thinkingLevel || "off";
  if (level === "off") return "";

  const map: Record<string, { icon: string; label: string }> = {
    minimal: { icon: IC.thinkMin, label: "min" },
    low: { icon: IC.thinkLow, label: "low" },
    medium: { icon: IC.thinkMed, label: "med" },
    high: { icon: IC.thinkHigh, label: "high" },
    xhigh: { icon: IC.thinkXHigh, label: "xhi" },
  };
  const info = map[level];
  if (!info) return "";

  // high / xhigh → rainbow（模拟：多色拼接，简单化用绿色警告色）
  if (level === "high" || level === "xhigh") {
    // rainbow：用成功色（绿）= pi theme 没有 true rainbow，用 success 代替
    return `${theme.fg("success", info.icon)} ${theme.fg("success", info.label)}`;
  }
  if (level === "minimal") {
    return `${theme.fg("dim", info.icon)} ${theme.fg("dim", info.label)}`;
  }
  return `${theme.fg("accent", info.icon)} ${theme.fg("accent", info.label)}`;
}

function segModel(state: FooterState, theme: Theme): string {
  return theme.fg("accent", iconText(IC.model, shortModel(state.modelName)));
}

function segTokenTotal(state: FooterState, theme: Theme): string {
  const n = state.contextTokens;
  if (n === null || n === undefined || n <= 0) return "";
  return theme.fg("dim", iconText(IC.tokens, fmtTokens(n)));
}

function segContext(state: FooterState, theme: Theme, tier: WidthTier): string {
  const pct = state.contextPercent;
  const window = state.contextWindow;
  const color = contextColor(pct);

  if (pct === null) {
    return theme.fg("dim", iconText(IC.context, "n/a"));
  }

  const pctStr = `${Math.round(pct)}%`;
  const text = tier === "wide" || tier === "medium"
    ? `${pctStr}/${fmtTokens(window)}`
    : pctStr;

  return `${theme.fg(color, IC.context)} ${theme.fg(color, text)}`;
}

function segTimeSpent(state: FooterState, theme: Theme): string {
  const elapsed = Date.now() - state.sessionStartMs;
  if (elapsed < 1000) return "";
  return theme.fg("dim", iconText(IC.clock, fmtDuration(elapsed)));
}

function segTime(_state: FooterState, theme: Theme): string {
  const now = new Date();
  const h = now.getHours().toString().padStart(2, "0");
  const m = now.getMinutes().toString().padStart(2, "0");
  const s = now.getSeconds().toString().padStart(2, "0");
  return theme.fg("dim", iconText(IC.clock, `${h}:${m}:${s}`));
}

// ═══════════════════════════════════════════════════════════════════════════
// 组装：按 tier 选段，超出宽度时从末尾按优先级省略
// ═══════════════════════════════════════════════════════════════════════════

interface SegSpec {
  id: string;
  /** 优先级：越大越不易被省略 */
  priority: number;
  render: () => string;
}

function buildSegments(state: FooterState, theme: Theme, tier: WidthTier): SegSpec[] {
  const all: SegSpec[] = [];

  // model 始终渲染
  all.push({ id: "model", priority: 99, render: () => segModel(state, theme) });

  // path（compact 省略）
  if (tier !== "compact") {
    all.push({ id: "path", priority: 60, render: () => segPath(state, theme) });
  }

  // git
  if (tier !== "compact" && state.gitBranch) {
    all.push({ id: "git", priority: 50, render: () => segGit(state, theme, tier) });
  }

  // thinking
  if (tier !== "compact" && state.thinkingLevel !== "off") {
    all.push({ id: "thinking", priority: 40, render: () => segThinking(state, theme) });
  }

  // context 始终渲染
  all.push({ id: "context", priority: 80, render: () => segContext(state, theme, tier) });

  // token total（narrow/compact 省略）
  if (tier === "wide" || tier === "medium") {
    const t = segTokenTotal(state, theme);
    if (t) all.push({ id: "tokens", priority: 30, render: () => t });
  }

  // timeSpent（narrow/compact 省略）
  if (tier !== "narrow" && tier !== "compact") {
    const ts = segTimeSpent(state, theme);
    if (ts) all.push({ id: "timeSpent", priority: 20, render: () => ts });
  }

  // time（仅 wide 显示）
  if (tier === "wide") {
    all.push({ id: "time", priority: 10, render: () => segTime(state, theme) });
  }

  // 按 priority 降序排列，确保高优先级段先被保留
  all.sort((a, b) => b.priority - a.priority);
  return all;
}

function assembleLine(segs: SegSpec[], sep: string, maxWidth: number): string {
  if (segs.length === 0) return "";

  // 重新按原始顺序排列（model · path · git · thinking · context · tokens · timeSpent · time）
  const order = ["model", "path", "git", "thinking", "context", "tokens", "timeSpent", "time"];
  const ordered = order
    .map((id) => segs.find((s) => s.id === id))
    .filter((s): s is SegSpec => !!s);

  // 从后往前尝试省略，直到整行能放进 maxWidth
  let parts = ordered.map((s) => s.render());
  const sepVw = visibleWidth(sep);

  for (let dropCount = 0; dropCount < ordered.length; dropCount++) {
    // 不能省略 model 或 context
    const toDrop = ordered[ordered.length - 1 - dropCount];
    if (!toDrop) break;
    if (toDrop.id === "model" || toDrop.id === "context") continue;

    const totalVw = parts.reduce((sum, p) => sum + visibleWidth(p), 0)
      + (parts.length - 1) * sepVw;

    if (totalVw <= maxWidth) break;

    // 省略当前最低优先级段
    const idx = ordered.indexOf(toDrop);
    if (idx >= 0) parts.splice(idx, 1);
  }

  return parts.join(sep);
}

// ═══════════════════════════════════════════════════════════════════════════
// Footer factory
// ═══════════════════════════════════════════════════════════════════════════

export function createStatusBar(getState: () => FooterState) {
  return function statusBarFactory(
    _tui: unknown,
    theme: Theme,
    footerData: ReadonlyFooterDataProvider,
  ): Component {
    let lastTier: WidthTier = "wide";
    let lastWidth = -1;
    let cached: string[] = [];

    return {
      invalidate(): void {
        lastWidth = -1;
        cached = [];
      },
      render(width: number): string[] {
        const branch = footerData.getGitBranch();
        const s = getState();
        const state: FooterState = {
          ...s,
          gitBranch: branch,
        };

        const tier = getTier(width);
        const segs = buildSegments(state, theme, tier);
        let line = assembleLine(segs, theme.fg("muted", IC.sep), width);

        // 如果仍然超宽，强制截断
        if (visibleWidth(line) > width) {
          line = truncateToWidth(line, width, "");
        }

        // 填充到终端宽度（status bar 始终占满一行）
        const vw = visibleWidth(line);
        const padded = vw < width ? line + " ".repeat(width - vw) : line;

        if (tier !== lastTier || width !== lastWidth || cached[0] !== padded) {
          lastTier = tier;
          lastWidth = width;
          cached = [padded];
        }
        return cached;
      },
    };
  };
}
