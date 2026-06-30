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
import type { AnimationState } from "../shared/animations.ts";
import type { FooterState, PetMood } from "../shared/types.ts";
import { NERD_FONTS } from "../shared/nerd-font.ts";
import { fmtDuration, fmtTokens, makeBar, shortModel } from "../shared/format.ts";

// ═══════════════════════════════════════════════════════════════════════════
// 图标（pet widget 专用；与 status-bar.ts 的 IC 不同 codepoint，不强行合并）
// ═══════════════════════════════════════════════════════════════════════════

// ASCII 降级用单字母前缀（避免与 widget 内容其他字符冲突）。
const IC = {
  model: NERD_FONTS ? "\uEC19" : "M", // chip
  think: NERD_FONTS ? "\uF0E7" : "T", // lightning bolt
  ctx: NERD_FONTS ? "\uE70F" : "C", // database
  clock: NERD_FONTS ? "\uF017" : "t", // clock
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
