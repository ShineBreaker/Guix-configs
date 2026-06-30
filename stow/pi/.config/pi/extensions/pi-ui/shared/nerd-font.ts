// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * nerd-font.ts — Nerd Font 检测的单一真相源。
 *
 * 重构前 detectNerdFont() 在 pet.ts / status-bar.ts / welcome-box.ts
 * 重复 3 份且实现不一致（reviewer 2026-06-25-0716.md WARNING #6 早就警告）：
 *   - pet.ts：正则 match，覆盖 terminus，无 COLORTERM truecolor 检测
 *   - status-bar.ts：includes，无 terminus
 *   - welcome-box.ts：includes，覆盖 terminus，含 COLORTERM truecolor 检测（最全）
 * 统一采用 welcome-box.ts 版本。
 *
 * 检测策略（按可信度排序）：
 *   1. 显式环境变量 POWERLINE_NERD_FONTS 强制开/关
 *   2. Ghostty 终端（GHOSTTY_RESOURCES_DIR 存在）→ 开
 *   3. 已知默认带 Nerd Font 的终端程序（TERM_PROGRAM 匹配）
 *   4. GNOME/xterm + COLORTERM=truecolor（truecolor 通常伴随 Nerd Font 主题）
 *   5. TERM 含 "nerd"/"nf-"
 *   6. tmux 内假定外层终端支持
 */

/** 检测当前终端是否支持 Nerd Font 图标。 */
export function detectNerdFont(): boolean {
  // 1. 显式覆盖
  if (process.env.POWERLINE_NERD_FONTS === "1") return true;
  if (process.env.POWERLINE_NERD_FONTS === "0") return false;

  // 2. Ghostty 暴露的资源目录
  if (process.env.GHOSTTY_RESOURCES_DIR) return true;

  // 3. 已知默认带 Nerd Font 的终端程序
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

  // 4. GNOME/xterm + truecolor
  if (term.includes("gnome") && colorTerm.includes("truecolor")) return true;
  if (term.includes("xterm") && colorTerm.includes("truecolor")) return true;

  // 5. TERM 名字直标
  const termName = (process.env.TERM ?? "").toLowerCase();
  if (termName.includes("nerd") || termName.includes("nf-")) return true;

  // 6. tmux 内的 terminal 通常来自外层 terminal，假定支持
  if (process.env.TMUX) return true;

  return false;
}

/**
 * 进程级缓存：Nerd Font 支持在单次 pi 进程内不会变化。
 * 各 widget 模块 import 此常量，避免重复检测。
 */
export const NERD_FONTS: boolean = detectNerdFont();
