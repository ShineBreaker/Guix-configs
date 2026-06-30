// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * types.ts — 跨模块共享的类型定义。
 *
 * 把 FooterState / PetMood 放这里的动机：
 * - status-bar.ts 定义 FooterState，pet.ts 和 index.ts 都要 import →
 *   放 shared 消除 status-bar ↔ pet 的耦合
 * - PetMood 原在 pet.ts，但 animations.ts 的 AnimationState 引用它，
 *   而 pet.ts 又 import animations.ts 的 AnimationState → 循环依赖。
 *   提到 shared/types.ts 断环。
 */

/**
 * FooterState — footer + pet widget 共享的会话状态。
 * status-bar.ts 只用 cwd/gitBranch/sessionStartMs 三字段；
 * 其余字段供 pet.ts 读 modelName/thinkingLevel/contextPercent 等。
 */
export interface FooterState {
  cwd: string;
  gitBranch: string | null;
  sessionStartMs: number;
  /** pet widget 使用；status-bar 不读 */
  modelName?: string;
  thinkingLevel?: string;
  contextPercent?: number | null;
  contextTokens?: number | null;
  contextWindow?: number;
}

/** Pet widget 的情绪状态（影响 ASCII 帧选择） */
export type PetMood =
  | "idle"
  | "listening"
  | "thinking"
  | "happy"
  | "worried"
  | "error";
