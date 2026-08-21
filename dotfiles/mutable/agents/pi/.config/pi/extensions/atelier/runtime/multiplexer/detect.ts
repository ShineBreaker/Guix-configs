// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 后端检测 — 运行时按环境变量选择 tmux 或 herdr 后端
 *
 * 与 types.ts 分离：types.ts 只定义接口（零依赖），本文件 import 两个具体
 * 后端实现做检测。避免 types.ts ↔ 后端实现的循环依赖。
 */

import type { MultiplexerBackend } from "./types.ts";
import { TmuxBackend } from "./tmux.ts";
import { HerdrBackend } from "./herdr.ts";

/**
 * 运行时检测当前所处的多路复用器，返回对应后端实例。
 *
 * 优先级：
 *   1. HERDR_ENV=1 → HerdrBackend
 *   2. $TMUX 非空 → TmuxBackend
 *   3. 都没有 → 抛错（atelier 必须运行在多路复用器内）
 *
 * 每次调用返回新实例（开销极小，避免跨 session 状态泄漏）。
 *
 * @throws Error 当既不在 herdr 也不在 tmux 内时
 */
export function detectBackend(): MultiplexerBackend {
  if (process.env.HERDR_ENV === "1") {
    return new HerdrBackend();
  }
  if (process.env.TMUX) {
    return new TmuxBackend();
  }
  throw new Error(
    "atelier requires Pi to run inside a multiplexer (tmux or herdr)",
  );
}
