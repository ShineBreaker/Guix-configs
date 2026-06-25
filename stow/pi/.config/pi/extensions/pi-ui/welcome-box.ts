// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * welcome-box.ts — WelcomeHeader 组件（启动时 header 区）
 *
 * 两栏布局：
 *   左栏：Welcome back! + pi 渐变 logo + 模型名 + 提供者
 *   右栏：Tips + Loaded + RecentSessions 三个分节
 *
 * 与 pi-powerline-footer 的 WelcomeHeader 区别：
 * - 永不渲染为 overlay 覆盖层（用户明确要求"打开直接进主界面"）
 * - Loaded 数据来自 plugin-bridge.collectLoaded() + pi API（真实数据）
 * - Tips 从 pi keybindings 动态读取，不硬编码
 * - 颜色用 pi theme 系统，不引入自己的 THEME 表
 * - Nerd Font 图标：与 status-bar.ts 同一检测函数（reviewer WARNING #6：合并）
 *
 * 关键 API（reviewer 2026-06-25-0716.md WARNING #7/#8）：
 * - setHeader 接收 factory：((tui, theme) => Component & {dispose?})
 * - Component.invalidate() 是 required 方法
 */

import type { Theme } from "@earendil-works/pi-coding-agent";
import type { Component } from "@earendil-works/pi-tui";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import type {
  AgenoteHealth,
  LoadedCounts,
  RecentSessionInfo,
} from "./plugin-bridge.ts";

// ═══════════════════════════════════════════════════════════════════════════
// Nerd Font 检测（与 status-bar.ts 一致，单一真相源）
// ═══════════════════════════════════════════════════════════════════════════

function detectNerdFont(): boolean {
  if (process.env.POWERLINE_NERD_FONTS === "1") return true;
  if (process.env.POWERLINE_NERD_FONTS === "0") return false;
  if (process.env.GHOSTTY_RESOURCES_DIR) return true;
  const term = (process.env.TERM_PROGRAM ?? "").toLowerCase();
  const colorTerm = (process.env.COLORTERM ?? "").toLowerCase();
  if (
    term.includes("iterm") ||
    term.includes("wezterm") ||
    term.includes("kitty") ||
    term.includes("ghostty") ||
    term.includes("alacritty") ||
    term.includes("vscode") ||
    term.includes("hyper") ||
    term.includes("konsole") ||
    term.includes("terminus") ||
    term.includes("foot") ||
    term.includes("tmux") ||
    term.includes("apple_terminal")
  ) {
    return true;
  }
  if (term.includes("gnome") && colorTerm.includes("truecolor")) return true;
  if (term.includes("xterm") && colorTerm.includes("truecolor")) return true;
  const termName = (process.env.TERM ?? "").toLowerCase();
  if (termName.includes("nerd") || termName.includes("nf-")) return true;
  // tmux 内的 terminal 通常来自外层 terminal，假定支持
  if (process.env.TMUX) return true;
  return false;
}

const NERD_FONTS = detectNerdFont();

const ICON = {
  // 灯泡（tips）
  tips:      NERD_FONTS ? "\uF0EB" : "",
  // 立方体（loaded）
  loaded:    NERD_FONTS ? "\uF1B3" : "",
  // 时钟（recent）
  recent:    NERD_FONTS ? "\uF017" : "",
// 记事本（agenote）— nf-md-notebook
  agenote:   NERD_FONTS ? "\uF562" : "kb",
  // 小点
  dot:       NERD_FONTS ? "\uF192" : "*",
  // 扩展（cube）
  ext:       NERD_FONTS ? "\uF1B2" : "ext",
  // prompt template
  template:  NERD_FONTS ? "\uF0F6" : "tpl",
  // context file
  ctxFile:   NERD_FONTS ? "\uF15B" : "ctx",
  // tool
  tool:      NERD_FONTS ? "\uEC19" : "tool",
  // skill
  skill:     NERD_FONTS ? "\uF13D" : "skl",
  // 健康状态图标
  ok:        "\u2705",
  warn:      "\u26A0\uFE0F",
  error:     "\u274C",
} as const;

// ═══════════════════════════════════════════════════════════════════════════
// Pi logo（6 行 ASCII，渐变填充）
// 参照 pi-powerline-footer welcome.ts 的 PI_LOGO + gradientLine，
// 但颜色改用 pi theme 的 accent/muted（统一风格）
// ═══════════════════════════════════════════════════════════════════════════

const PI_LOGO = [
  "██████████    ",
  "████  ████    ",
  "████  ████    ",
  "████████  ████",
  "████      ████",
  "████      ████",
] as const;

/**
 * 将渐变色应用到一行 logo。空格保留为不可见字符。
 * 使用 pi theme 的 accent → muted 渐变（与 theme 一致）。
 */
function gradientLine(line: string, theme: Theme): string {
  const colors: readonly string[] = [
    theme.fg("accent", ""), // 占位以保持索引对齐
    theme.fg("accent", ""),
    theme.fg("muted", ""),
    theme.fg("muted", ""),
    theme.fg("dim", ""),
    theme.fg("dim", ""),
  ];
  const reset = "\x1b[0m";
  const step = Math.max(1, Math.floor(line.length / colors.length));
  let result = "";
  let colorIdx = 0;
  for (let i = 0; i < line.length; i++) {
    if (i > 0 && i % step === 0 && colorIdx < colors.length - 1) colorIdx++;
    const char = line[i];
    if (char === " ") {
      result += char;
    } else {
      // ANSI 转义码包裹单个字符
      const ansi = colors[colorIdx] ?? "";
      // 去掉 colors[] 的 ANSI reset（theme.fg 自带 reset）
      // 这里直接用 ansi 即可
      result += ansi.replace(/\x1b\[0m$/, "") + char + reset;
    }
  }
  return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// 数据类型
// ═══════════════════════════════════════════════════════════════════════════

export interface WelcomeData {
  modelName: string;
  providerName: string;
  /** 启动提示列表（如 "/ commands"、"! bash"），由调用方注入 */
  tips: readonly string[];
  loaded: LoadedCounts;
  recent: readonly RecentSessionInfo[];
  /** Agenote 记事本健康度（plugin-bridge.runAgenoteHealth 返回） */
  agenote: AgenoteHealth | null;
}

// ═══════════════════════════════════════════════════════════════════════════
// 渲染辅助
// ═══════════════════════════════════════════════════════════════════════════

function centerText(text: string, width: number): string {
  const vis = visibleWidth(text);
  if (vis >= width) return truncateToWidth(text, width, "");
  const left = Math.floor((width - vis) / 2);
  const right = width - vis - left;
  return " ".repeat(left) + text + " ".repeat(right);
}

function fitToWidth(text: string, width: number): string {
  const vis = visibleWidth(text);
  if (vis >= width) return truncateToWidth(text, width, "");
  return text + " ".repeat(width - vis);
}

// ═══════════════════════════════════════════════════════════════════════════
// 左栏 + 右栏构造
// ═══════════════════════════════════════════════════════════════════════════

function buildLeftColumn(data: WelcomeData, theme: Theme, width: number): string[] {
  const logo = PI_LOGO.map((line) => centerText(gradientLine(line, theme), width));
  return [
    "",
    centerText(theme.bold(theme.fg("accent", "Welcome back!")), width),
    "",
    ...logo,
    "",
    centerText(theme.fg("accent", data.modelName), width),
    centerText(theme.fg("muted", data.providerName), width),
  ];
}

function buildRightColumn(data: WelcomeData, theme: Theme, width: number): string[] {
  const sep = ` ${theme.fg("dim", "─".repeat(Math.max(0, width - 2)))}`;
  const lines: string[] = [];

  // Tips 区
  lines.push(sectionHeader(theme, ICON.tips, "Tips"));
  for (const tip of data.tips) {
    lines.push(` ${theme.fg("muted", tip)}`);
  }
  lines.push(sep);

  // Loaded 区
  lines.push(sectionHeader(theme, ICON.loaded, "Loaded"));
  const ctxCount = data.loaded.contextFiles.length;
  const ctxReadable = data.loaded.contextFiles.filter((f) => f.readable).length;
  const ctxBytes = data.loaded.contextFiles
    .filter((f) => f.readable)
    .reduce((sum, f) => sum + f.size, 0);
  const ctxStr =
    ctxCount === 0
      ? "no context files"
      : ctxReadable === ctxCount
        ? `${ctxCount} context file${ctxCount === 1 ? "" : "s"} (${formatBytes(ctxBytes)})`
        : `${ctxReadable}/${ctxCount} context files`;
// fastfetch 风格：图标 + 值，无圆点前缀
  lines.push(` ${theme.fg("muted", `${ICON.ctxFile} ${ctxStr}`)}`);
  lines.push(` ${theme.fg("muted", `${ICON.tool} ${data.loaded.tools} tools`)}`);
  lines.push(` ${theme.fg("muted", `${ICON.skill} ${data.loaded.skills} skills`)}`);
  if (data.loaded.extensions > 0) {
    lines.push(` ${theme.fg("muted", `${ICON.ext} ${data.loaded.extensions} extensions`)}`);
  }
  if (data.loaded.templates > 0) {
    lines.push(` ${theme.fg("muted", `${ICON.template} ${data.loaded.templates} templates`)}`);
  }
  lines.push(sep);

  // Agenote 区
  if (data.agenote && data.agenote.available) {
    lines.push(sectionHeader(theme, ICON.agenote, "Agenote"));
    const a = data.agenote;
    // 卡片总数 + 状态
    lines.push(
      ` ${theme.fg("muted", `${a.cards.total} cards (done: ${a.cards.done}, stable: ${a.cards.stable})`)}`,
    );
    // 健康指标：每个一行（fastfetch 风格）
    for (const m of a.metrics) {
      const iconColor = m.status === "ok" ? "success" : m.status === "warn" ? "warning" : "error";
      const statusIcon = m.status === "ok" ? ICON.ok : m.status === "warn" ? ICON.warn : ICON.error;
      // 指标名 + 值 + [阈值] + 状态图标（紧凑、与 fastfetch 一致）
      const name = theme.fg("muted", m.name);
      const value = theme.fg(iconColor, m.value);
      const thr = theme.fg(iconColor, `[${m.threshold}]`);
      const icon = theme.fg(iconColor, statusIcon);
      lines.push(` ${name} ${value} ${thr} ${icon}`);
    }
    // feedback 状态
    if (a.feedback.total > 0) {
      lines.push(` ${theme.fg("muted", `feedback: ${a.feedback.total} (stale: ${a.feedback.stale})`)}`);
    } else {
      lines.push(` ${theme.fg("dim", `feedback: 0 (stale: ${a.feedback.stale})`)}`);
    }
    lines.push(sep);
  }
  // Recent 区
  lines.push(sectionHeader(theme, ICON.recent, "Recent"));
  if (data.recent.length === 0) {
    lines.push(` ${theme.fg("dim", "no recent sessions")}`);
  } else {
    for (const session of data.recent.slice(0, 3)) {
      const namePart = theme.fg("accent", session.name);
      const agePart =
        session.age !== null ? theme.fg("muted", ` (${session.age})`) : "";
      lines.push(` ${theme.fg("muted", `${ICON.dot}`)} ${namePart}${agePart}`);
    }
  }

  return lines;
}

/** 区段标题：Nerd Font 图标（可选）+ 加粗 accent 色文字 */
function sectionHeader(theme: Theme, icon: string, label: string): string {
  const iconPart = icon ? `${icon} ` : "";
  return ` ${theme.bold(theme.fg("accent", `${iconPart}${label}`))}`;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// ═══════════════════════════════════════════════════════════════════════════
// 整体欢迎框渲染
// ═══════════════════════════════════════════════════════════════════════════

function renderWelcomeBox(
  data: WelcomeData,
  theme: Theme,
  termWidth: number,
): string[] {
  // 极窄终端直接跳过（< 44 列放不下两栏）
  const minLayoutWidth = 44;
  if (termWidth < minLayoutWidth) return [];

  const minWidth = 76;
  const maxWidth = 96;
  const boxWidth = Math.min(
    termWidth,
    Math.max(minWidth, Math.min(termWidth - 2, maxWidth)),
  );
  const leftCol = 26;
  const rightCol = Math.max(1, boxWidth - leftCol - 3);

  const hChar = "─";
  const v = theme.fg("dim", "│");
  const tl = theme.fg("dim", "╭");
  const tr = theme.fg("dim", "╮");
  const bl = theme.fg("dim", "╰");
  const br = theme.fg("dim", "╯");

  const leftLines = buildLeftColumn(data, theme, leftCol);
  const rightLines = buildRightColumn(data, theme, rightCol);

  const lines: string[] = [];

  // 顶边：pi agent 标题
  const title = " pi agent ";
  const titleStyled = theme.fg("accent", title);
  const titleVisLen = visibleWidth(title);
  const afterTitle = boxWidth - 2 - titleVisLen;
  const afterText = afterTitle > 0 ? theme.fg("dim", hChar.repeat(afterTitle)) : "";
  lines.push(tl + titleStyled + afterText + tr);

  // 内容行
  const maxRows = Math.max(leftLines.length, rightLines.length);
  for (let i = 0; i < maxRows; i++) {
    const left = fitToWidth(leftLines[i] ?? "", leftCol);
    const right = fitToWidth(rightLines[i] ?? "", rightCol);
    lines.push(v + left + v + right + v);
  }

  // 底边（无倒计时 —— 用户要求仅 header 模式）
  const bottomInner = hChar.repeat(Math.max(0, boxWidth - 2));
  lines.push(bl + theme.fg("dim", bottomInner) + br);

  return lines;
}

// ═══════════════════════════════════════════════════════════════════════════
// Component 工厂：setHeader 的 factory 模式
// ═══════════════════════════════════════════════════════════════════════════

export function createWelcomeHeader(getData: () => WelcomeData) {
  return function welcomeHeaderFactory(
    _tui: unknown,
    theme: Theme,
  ): Component {
    return {
      invalidate(): void {
        // welcome header 启动后基本不变，invalidate 仅在主题切换时调用，
        // 依赖 theme 闭包即时重算即可
      },
      render(width: number): string[] {
        return renderWelcomeBox(getData(), theme, width);
      },
    };
  };
}
