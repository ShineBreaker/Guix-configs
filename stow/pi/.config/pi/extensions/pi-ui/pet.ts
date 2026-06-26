// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * pi-pet widget — 桌面宠物 + 会话信息侧栏
 *
 * Placement: belowEditor（紧贴 editor 之下、footer 之上）。
 * 原因：pi 的 aboveEditor widget 顺序由 setWidget 注册顺序决定（Map.values()），
 * pet startup 注册在前、agent 创建的 todos widget 注册在后，todos 会插到 pet 之下、
 * 把 pet 推离 editor。改用 belowEditor 与 chat 区域隔离，永远紧贴 editor。
 *
 * 内容：左列 4 行会话信息（model / thinking / context bar / duration），
 * 右列 5 行猫猫 pet ASCII art（无边框、无 emoji）。
 * 极窄终端退化：放不下 info 列时只显示 pet；放不下 pet 时整个 widget 隐藏。
 */

import type { ExtensionUIContext } from "@earendil-works/pi-coding-agent";
import type { AnimationState } from "./animations.ts";
import type { FooterState } from "./status-bar.ts";

// ═══════════════════════════════════════════════════════════════════════════
// 类型
// ═══════════════════════════════════════════════════════════════════════════

export type PetMood =
  | "idle"
  | "listening"
  | "thinking"
  | "happy"
  | "worried"
  | "error";

// ═══════════════════════════════════════════════════════════════════════════
// Nerd Font 检测 + 图标
// ═══════════════════════════════════════════════════════════════════════════

/**
 * 与 welcome-box.ts / status-bar.ts 重复定义；提到 animations.ts 是未来
 * 重构方向，目前三处独立以避免循环依赖。
 */
function detectNerdFont(): boolean {
  if (process.env.POWERLINE_NERD_FONTS === "1") return true;
  if (process.env.POWERLINE_NERD_FONTS === "0") return false;
  if (process.env.GHOSTTY_RESOURCES_DIR) return true;
  const term = (process.env.TERM_PROGRAM ?? "").toLowerCase();
  if (
    term.match(
      /iterm|wezterm|kitty|ghostty|alacritty|vscode|hyper|konsole|terminus|foot|tmux|apple_terminal/,
    )
  ) {
    return true;
  }
  if (process.env.TMUX) return true;
  const termName = (process.env.TERM ?? "").toLowerCase();
  return termName.includes("nerd") || termName.includes("nf-");
}

const NF = detectNerdFont();

/**
 * 4 个图标 codepoint 与 status-bar.ts IC 同源；这里独立定义一份避免循环依赖。
 * ASCII 降级用单字母前缀 + 冒号（避免与 widget 内容其他字符冲突）。
 */
const IC = {
  model: NF ? "\uEC19" : "M", // chip
  think: NF ? "\uF0E7" : "T", // lightning bolt
  ctx: NF ? "\uE70F" : "C", // database
  clock: NF ? "\uF017" : "t", // clock
} as const;

// ═══════════════════════════════════════════════════════════════════════════
// Pet 帧表（5 行 × 11 字符，无边框）
// ═══════════════════════════════════════════════════════════════════════════

const FRAMES: Record<PetMood, string[]> = {
  idle: [
    "   /\\_/\\  ",
    "  ( o.o ) ",
    "   > ~ <  ",
    "  /|   |\\ ",
    " (_|   |_)",
  ],
  listening: [
    "   /\\_/\\  ",
    "  ( @.@ ) ",
    "   > ~ <  ",
    "  /|   |\\ ",
    " (_|   |_)",
  ],
  thinking: [
    "   /\\_/\\  ",
    "  ( O.O ) ",
    "   > ~ <  ",
    "  /|   |\\ ",
    " (_|   |_)",
  ],
  happy: [
    "   /\\_/\\  ",
    "  ( ^ω^ ) ",
    "   > ~ <  ",
    "  /|   |\\ ",
    " (_|   |_)",
  ],
  worried: [
    "   /\\_/\\  ",
    "  ( O.O )!",
    "   > △ <  ",
    "  /| ~ |\\ ",
    " (_|   |_)",
  ],
  error: [
    "   /\\_/\\  ",
    "  ( X.X )~",
    "   > △ <! ",
    "  /| ~ |\\ ",
    " (_| ~ |_)",
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// 格式化 helper
// ═══════════════════════════════════════════════════════════════════════════

/** 短模型名（去掉 "Claude " 前缀） */
function shortModel(name: string): string {
  return name.startsWith("Claude ") ? name.slice(7) : name;
}

/** 8 格字符画 */
function makeBar(pct: number): string {
  const filled = Math.max(0, Math.min(8, Math.round(pct / 12.5)));
  return "\u2593".repeat(filled) + "\u2591".repeat(8 - filled);
}

/** 时长格式 */
function fmtDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const h = Math.floor(m / 60);
  if (h > 0) return `${h}h${m % 60}m`;
  if (m > 0) return `${m}m${s % 60}s`;
  return `${s}s`;
}

/** token 数格式 */
function fmtTokens(n: number): string {
  if (n < 1000) return String(n);
  if (n < 10000) return `${(n / 1000).toFixed(1)}k`;
  if (n < 1000000) return `${Math.round(n / 1000)}k`;
  return `${(n / 1000000).toFixed(1)}M`;
}

// ═══════════════════════════════════════════════════════════════════════════
// Pet mood helper
// ═══════════════════════════════════════════════════════════════════════════

export function setPetMood(anim: AnimationState, mood: PetMood): void {
  anim.petMood = mood;
  anim.petMoodStartMs = Date.now();
}

// ═══════════════════════════════════════════════════════════════════════════
// Widget 注册
// ═══════════════════════════════════════════════════════════════════════════

const PET_WIDTH = 11; // pet art 每行宽（含末尾空格）
const INFO_LINES = 4; // 信息行数
const MIN_WIDTH_FOR_INFO = 28; // 显示左列信息需要的最小终端宽度

/**
 * 注册 aboveEditor 的 pi-pet widget。
 *
 * 签名：
 *   export function createPetWidget(
 *     ui: ExtensionUIContext,
 *     getState: () => FooterState,
 *     getAnim: () => AnimationState,
 *   ): void
 */
export function createPetWidget(
  ui: ExtensionUIContext,
  getState: () => FooterState,
  getAnim: () => AnimationState,
): void {
  ui.setWidget(
    "pi-pet",
    (_tui, _theme) => ({
      invalidate(): void {},
      render(width: number): string[] {
        // 极窄终端退化：连 pet 都放不下
        if (width < PET_WIDTH + 2) return [];

        const state = getState();
        const anim = getAnim();
        const petLines = FRAMES[anim.petMood] ?? FRAMES.idle;

        const showInfo = width >= MIN_WIDTH_FOR_INFO;
        const gap = showInfo ? 2 : 0;
        const leftWidth = showInfo ? width - PET_WIDTH - gap : 0;

        // 4 行信息（顶对齐：与 pet 前 4 行配对，第 5 行 pet 单独）
        const elapsed = Date.now() - state.sessionStartMs;
        const pct = state.contextPercent ?? 0;
        const pctStr = `${Math.round(pct)}%`;
        const thinkingLabel = state.thinkingLevel || "off";

        const infoLines: string[] = showInfo
          ? [
              `${IC.model} ${shortModel(state.modelName || "?")}`,
              `${IC.think} ${thinkingLabel}`,
              `${IC.ctx} ${makeBar(pct)} ${pctStr} / ${fmtTokens(state.contextWindow || 0)}`,
              `${IC.clock} ${fmtDuration(elapsed)}`,
            ]
          : [];

        // 5 行 widget 输出：info 行右填充到 leftWidth + pet 行
        const out: string[] = [];
        for (let i = 0; i < 5; i++) {
          const infoPart = (i < INFO_LINES ? (infoLines[i] ?? "") : "").padEnd(
            leftWidth,
          );
          const petPart = petLines[i] ?? "";
          out.push(infoPart + petPart);
        }
        return out;
      },
    }),
    { placement: "belowEditor" },
  );
}
