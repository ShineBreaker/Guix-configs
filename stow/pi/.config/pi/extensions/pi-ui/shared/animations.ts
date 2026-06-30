// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

import type { PetMood } from "./types.ts";

/**
 * 动画原语集合
 *
 * pi TUI 是事件驱动 + 差分渲染，动画通过：
 *   1. 组件内 setInterval 更新内部 state（相位 / 帧号）
 *   2. 调 tui.requestRender() 触发重绘
 *   3. render() 方法用当前 state 输出 ANSI 转义
 *
 * 60fps 上限（MIN_RENDER_INTERVAL_MS = 16），动画不需更高帧率。
 *
 * 模块导出：
 *   - hslToRgb() / fg() — HSL→24-bit ANSI 前景色
 *   - createAnimation() — 通用 setInterval + requestRender 驱动
 *   - phase/01-05 配色方案常量
 */

// ═══════════════════════════════════════════════════════════════════════════
// 类型
// ═══════════════════════════════════════════════════════════════════════════

/** 24-bit ANSI 前景色转义码（不含 reset） */
export type FgAnsi = string;

/** 调色板入口：每行 logo 一个 HSL 起点 */
export interface GradientStop {
  /** 色相 0-360（动画时为基准相位，加上 phase*speed 循环） */
  h: number;
  s: number;
  l: number;
}

/** 全局动画状态（被 welcome-box factory 引用） */
export interface AnimationState {
  /** 启动后累计帧（每 50ms +1） */
  phase: number;
  /** 启动后累计毫秒数（用于 tips 打字机） */
  elapsedMs: number;
  /** 1=动画活跃, 0=已停止（停止后 freeze 在最后帧） */
  active: number;
  /** model_select 闪烁剩余次数（0=不闪） */
  modelFlash: number;
  /** tips 索引 → 已展开字符数（typewriter 进度） */
  tipRevealed: number[];
  /** tips 启动时间偏移（ms）—— staggered 出现 */
  tipStartMs: number[];
  petMood: PetMood;
  petMoodStartMs: number;
  inputFlash: number;
}

// ═══════════════════════════════════════════════════════════════════════════
// 颜色
// ═══════════════════════════════════════════════════════════════════════════

/**
 * 是否启用动画。
 *
 * 决策顺序（前者覆盖后者）：
 *   1. 显式覆盖：PI_UI_ANIMATIONS=0/false → 关；=1/true → 开
 *   2. 自动检测：SSH / CI / 非交互终端 → 关
 *   3. 默认：开
 *
 * 远程 SSH、低带宽 CI、子进程管道等场景关掉动画，可减少 setInterval
 * 频率和 requestRender 风暴。
 */
export function shouldAnimate(): boolean {
  const override = process.env.PI_UI_ANIMATIONS?.toLowerCase();
  if (override === "0" || override === "false") return false;
  if (override === "1" || override === "true") return true;

  if (process.env.SSH_CONNECTION || process.env.SSH_TTY) return false;
  if (
    process.env.CI ||
    process.env.GITHUB_ACTIONS ||
    process.env.GITLAB_CI ||
    process.env.CIRCLECI ||
    process.env.BUILDKITE
  ) {
    return false;
  }
  // Node.js: 管道 / 重定向 / 非 tty stdin 时 isTTY 为 undefined
  if (!process.stdin.isTTY) return false;

  return true;
}

/** HSL → RGB（0-255） */
export function hslToRgb(
  h: number,
  s: number,
  l: number,
): [number, number, number] {
  // h ∈ [0, 360), s,l ∈ [0, 1]
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const hp = (((h % 360) + 360) % 360) / 60;
  const x = c * (1 - Math.abs((hp % 2) - 1));
  let r1 = 0;
  let g1 = 0;
  let b1 = 0;
  if (hp < 1) {
    r1 = c;
    g1 = x;
  } else if (hp < 2) {
    r1 = x;
    g1 = c;
  } else if (hp < 3) {
    g1 = c;
    b1 = x;
  } else if (hp < 4) {
    g1 = x;
    b1 = c;
  } else if (hp < 5) {
    r1 = x;
    b1 = c;
  } else {
    r1 = c;
    b1 = x;
  }
  const m = l - c / 2;
  return [
    Math.round((r1 + m) * 255),
    Math.round((g1 + m) * 255),
    Math.round((b1 + m) * 255),
  ];
}

/** HSL → 24-bit ANSI 前景色转义码（不含 reset） */
export function fg(h: number, s: number, l: number): FgAnsi {
  const [r, g, b] = hslToRgb(h, s, l);
  return `\x1b[38;2;${r};${g};${b}m`;
}

/** ANSI reset */
export const RESET = "\x1b[0m";

// ═══════════════════════════════════════════════════════════════════════════
// 调色板
// ═══════════════════════════════════════════════════════════════════════════

/**
 * 6 段彩虹渐变（PI Logo 自上而下）。
 * 动画时每段 h + phase*speed，整体效果是颜色循环滚动。
 * 静态时直接用基准色（speed=0）。
 */
export const LOGO_GRADIENT: readonly GradientStop[] = [
  { h: 200, s: 0.85, l: 0.6 }, // 蓝
  { h: 220, s: 0.85, l: 0.6 }, // 蓝紫
  { h: 260, s: 0.75, l: 0.65 }, // 紫
  { h: 300, s: 0.75, l: 0.65 }, // 品红
  { h: 320, s: 0.75, l: 0.65 }, // 粉
  { h: 340, s: 0.75, l: 0.65 }, // 暖红
];

/** 每段色相循环速度（度数 / 帧 @50ms），越大越快 */
export const LOGO_COLOR_SPEED = 6;

/** Agenote 状态图标的脉冲基色（HSL） */
export const STATUS_BASE = {
  ok: { h: 140, s: 0.6, l: 0.55 }, // 绿
  warn: { h: 45, s: 0.85, l: 0.55 }, // 黄
  error: { h: 0, s: 0.85, l: 0.6 }, // 红
} as const;

/** Model flash 时的循环色（蓝→品红→青） */
export const MODEL_FLASH_COLORS: readonly [number, number, number][] = [
  [200, 0.85, 0.65], // 蓝
  [320, 0.85, 0.65], // 品红
  [180, 0.85, 0.65], // 青
];

// ═══════════════════════════════════════════════════════════════════════════
// 动画驱动
// ═══════════════════════════════════════════════════════════════════════════

/**
 * 启动全局动画循环。
 *  - 每 50ms（~20fps）更新 AnimationState
 *  - 调 ui.requestRender() 触发重绘
 *  - 5 秒后自动 stop（welcome box 已稳定）
 *  - 返回 stop() 用于在 session_shutdown 主动清理
 */
export function startAnimation(
  state: AnimationState,
  requestRender: () => void,
  activeMs: number = 5000,
): () => void {
  // 关闭动画：保持 state.active=0（=静态渲染），不启动 tick
  if (!shouldAnimate()) {
    state.active = 0;
    state.elapsedMs = activeMs;
    return () => {};
  }

  const startMs = Date.now();
  const interval = setInterval(() => {
    const elapsed = Date.now() - startMs;
    state.elapsedMs = elapsed;
    state.phase += 1;

    // 启动动画窗口结束后冻结（保留最后状态，但不再递增）
    if (elapsed >= activeMs) {
      state.active = 0;
      clearInterval(interval);
    }

    requestRender();
  }, 50);

  return () => clearInterval(interval);
}

/**
 * 触发 model_select 闪烁动画。
 * 持续 1 秒，期间 modelFlash 计数递减；render 时按模 3 切换颜色。
 */
export function triggerModelFlash(
  state: AnimationState,
  requestRender: () => void,
): void {
  if (!shouldAnimate()) return;
  state.modelFlash = 3; // 3 次切换（共 600ms）
  let elapsed = 0;
  const interval = setInterval(() => {
    elapsed += 200;
    if (elapsed >= 600) {
      state.modelFlash = 0;
      clearInterval(interval);
    } else {
      state.modelFlash = Math.max(0, state.modelFlash - 1);
    }
    requestRender();
  }, 200);
}
