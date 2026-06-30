// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * status-bar.ts — 精简版 status bar（footer）
 *
 * 设计参考：
 *   - Emacs modeline.el：4 档宽度 (wide/medium/narrow/compact)、`·` 分隔、
 *     语义颜色、Nerd Font 图标优先 + 降级到空串
 *   - starship.toml：`·` 分隔符
 *
 * 段顺序：path · git · time
 *
 * model / thinking / context / tokens 已搬到 pet widget 左列展示，
 * footer 只保留位置信息（path/git）和时间信息（time）。会话时长由 pet widget 左列展示。
 *
 * 宽度档（同 Emacs modeline）：
 *   - wide    (>= 120): 全部 4 段
 *   - medium  (100-119): 省略 time
 *   - narrow   (80-99):  只显 path · git
 *   - compact  (< 80):   只显 path
 */

import { homedir } from "node:os";
import { basename, join } from "node:path";
import { existsSync } from "node:fs";
import { execSync } from "node:child_process";
import type {
  Theme,
  ReadonlyFooterDataProvider,
} from "@earendil-works/pi-coding-agent";
import type { Component } from "@earendil-works/pi-tui";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { NERD_FONTS } from "../shared/nerd-font.ts";
import {
  createKeyedTtlCache,
  createTtlCache,
  iconText,
} from "../shared/format.ts";
import type { FooterState } from "../shared/types.ts";
// FooterState re-export：历史调用方仍可从本模块导入
export type { FooterState };

// ═══════════════════════════════════════════════════════════════════════════
// 图标
// ═══════════════════════════════════════════════════════════════════════════

const IC = {
  // folder open
  folder: NERD_FONTS ? "\uF115" : "dir",
  // git branch (code fork)
  branch: NERD_FONTS ? "\uF126" : "b",
  // git ahead (upload) / behind (download) — ↑ ↓ 是 BMP 符号，非 emoji
  ahead: "\u2191", // ↑
  behind: "\u2193", // ↓
  // commit (bullet / circle-dot)
  commit: NERD_FONTS ? "\uF418" : "@",
  // clock
  clock: NERD_FONTS ? "\uF017" : "t",
  // separator（starship 风格 · ）
  sep: " · ",
} as const;

// ═══════════════════════════════════════════════════════════════════════════
// 宽度档
// ═══════════════════════════════════════════════════════════════════════════

export type WidthTier = "wide" | "medium" | "narrow" | "compact";

export function getTier(width: number): WidthTier {
  if (width >= 120) return "wide";
  if (width >= 100) return "medium";
  if (width >= 80) return "narrow";
  return "compact";
}

// Git 查询缓存：避免每帧 fork git 子进程。各 TTL 见各 helper。
const dirtyCache = createTtlCache<number>(5000);
function getGitDirtyCount(): number {
  return dirtyCache.get(() => {
    try {
      const out = execSync("git status --porcelain 2>/dev/null | wc -l", {
        encoding: "utf-8",
        timeout: 1000,
      }).trim();
      return parseInt(out, 10) || 0;
    } catch {
      return 0;
    }
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// 各段渲染器
// ═══════════════════════════════════════════════════════════════════════════

function segPath(state: FooterState, theme: Theme): string {
  const pwd = basename(state.cwd || homedir()) || "?";
  return theme.fg("accent", iconText(IC.folder, pwd));
}

function segGit(state: FooterState, theme: Theme): string {
  if (!state.gitBranch) return "";
  const dirty = getGitDirtyCount();
  const dirtyMark = dirty > 0 ? ` ${theme.fg("warning", `●${dirty}`)}` : "";
  return theme.fg("accent", iconText(IC.branch, state.gitBranch)) + dirtyMark;
}
// Git ahead/behind：本地与 @{u} 的差距（仅当 branch 存在时），5s 缓存
const aheadBehindCache = createTtlCache<string>(5000);
function getAheadBehind(): string {
  return aheadBehindCache.get(() => {
    try {
      const out = execSync(
        "git rev-list --count --left-right @{u}...HEAD 2>/dev/null",
        {
          encoding: "utf-8",
          timeout: 1000,
        },
      ).trim();
      // 输出格式 "behind\t ahead"（左=behind, 右=ahead）
      const [behind, ahead] = out
        .split(/\s+/)
        .map((n) => parseInt(n, 10) || 0);
      let text = "";
      if (ahead > 0) text += `\u2191${ahead}`;
      if (behind > 0) text += (text ? " " : "") + `\u2193${behind}`;
      return text;
    } catch {
      return "";
    }
  });
}
function segAheadBehind(state: FooterState, theme: Theme): string {
  if (!state.gitBranch) return "";
  const text = getAheadBehind();
  if (!text) return "";
  return theme.fg("muted", text);
}

// Git HEAD commit 短 hash：8s 缓存
const hashCache = createTtlCache<string>(8000);
function getHeadHash(): string {
  return hashCache.get(() => {
    try {
      return execSync("git rev-parse --short HEAD 2>/dev/null", {
        encoding: "utf-8",
        timeout: 1000,
      }).trim();
    } catch {
      return "";
    }
  });
}
function segHash(state: FooterState, theme: Theme): string {
  if (!state.gitBranch) return "";
  const h = getHeadHash();
  if (!h) return "";
  return theme.fg("muted", `${IC.commit}${h}`);
}

// 项目语言检测：按 cwd 扫特征文件，1h 缓存（项目类型极少变化）
const langCache = createKeyedTtlCache<string>(3_600_000);
// 优先级排序：具体语言 > 通用
const LANG_PROBES: ReadonlyArray<readonly [string, string, string]> = [
  ["package.json", "\uE712", "Node"],
  ["Cargo.toml", "\uE7A8", "Rust"],
  ["pyproject.toml", "\uE73C", "Python"],
  ["go.mod", "\uE626", "Go"],
  ["flake.nix", "\uF313", "Nix"],
  ["channel.scm", "\uF0CB", "Guix"],
  ["manifest.scm", "\uF0CB", "Guix"],
];
function detectProjectLang(cwd: string): string {
  return langCache.get(cwd, () => {
    for (const [file, icon, label] of LANG_PROBES) {
      if (existsSync(join(cwd, file))) {
        return `${icon} ${label}`;
      }
    }
    return "";
  });
}
function segLanguage(state: FooterState, theme: Theme): string {
  const text = detectProjectLang(state.cwd || process.cwd());
  if (!text) return "";
  return theme.fg("dim", text);
}

function segTime(_state: FooterState, theme: Theme): string {
  const now = new Date();
  const h = now.getHours().toString().padStart(2, "0");
  const m = now.getMinutes().toString().padStart(2, "0");
  const s = now.getSeconds().toString().padStart(2, "0");
  return theme.fg("dim", iconText(IC.clock, `${h}:${m}:${s}`));
}

// ═══════════════════════════════════════════════════════════════════════════
// 组装：按 tier 选段
// ═══════════════════════════════════════════════════════════════════════════

interface SegSpec {
  id: string;
  render: () => string;
}

function buildSegments(
  state: FooterState,
  theme: Theme,
  tier: WidthTier,
): SegSpec[] {
  const all: SegSpec[] = [];

  // path（compact 也保留）
  all.push({ id: "path", render: () => segPath(state, theme) });
  // git（compact 省略）
  if (tier !== "compact" && state.gitBranch) {
    all.push({ id: "git", render: () => segGit(state, theme) });

    // ahead/behind（narrow 省略）
    if (tier !== "narrow") {
      const ab = segAheadBehind(state, theme);
      if (ab) all.push({ id: "aheadBehind", render: () => ab });
    }

    // commit hash（仅 wide）
    if (tier === "wide") {
      const h = segHash(state, theme);
      if (h) all.push({ id: "hash", render: () => h });
    }
  }

  // 项目语言（wide/medium 保留）
  if (tier === "wide" || tier === "medium") {
    const l = segLanguage(state, theme);
    if (l) all.push({ id: "lang", render: () => l });
  }

  // time（narrow/compact 省略）
  if (tier === "wide" || tier === "medium") {
    all.push({ id: "time", render: () => segTime(state, theme) });
  }

  // 段顺序由 assembleLine 的固定 order 数组决定，这里不排序
  return all;
}

function assembleLine(segs: SegSpec[], sep: string, maxWidth: number): string {
  if (segs.length === 0) return "";

  // 按原始顺序排列（path · git · aheadBehind · hash · lang · time）
  const order = ["path", "git", "aheadBehind", "hash", "lang", "time"];
  const ordered = order
    .map((id) => segs.find((s) => s.id === id))
    .filter((s): s is SegSpec => !!s);

  // 从后往前尝试省略，直到整行能放进 maxWidth
  let parts = ordered.map((s) => s.render());
  const sepVw = visibleWidth(sep);

  for (let dropCount = 0; dropCount < ordered.length; dropCount++) {
    const toDrop = ordered[ordered.length - 1 - dropCount];
    if (!toDrop) break;

    const totalVw =
      parts.reduce((sum, p) => sum + visibleWidth(p), 0) +
      (parts.length - 1) * sepVw;

    if (totalVw <= maxWidth) break;

    const idx = ordered.indexOf(toDrop);
    if (idx >= 0) parts.splice(idx, 1);
  }

  return parts.join(sep);
}

// ═══════════════════════════════════════════════════════════════════════════
// Widget factory（aboveEditor placement，status bar 渲染到 editor 之上）
// ═══════════════════════════════════════════════════════════════════════════
//
// 参考 pi-powerline-footer：不用 setExtensionFooter 替换内置 footer，
// 而是用 setExtensionFooter(emptyFactory) 隐藏内置 footer + setWidget
// 把状态栏注册到 aboveEditor。setExtensionFooter 工厂闭包内捕获
// footerData 引用，由 getGitBranch() 在每次 render 时实时读。
// 内部 setInterval(1000) 调 tui.requestRender() 触发 time / * time 自动更新。
//
export function createStatusBarWidget(
  getState: () => FooterState,
  getGitBranch: () => string | null,
): (_tui: unknown, theme: Theme) => Component {
  return (_tui, theme) => {
    // 每秒 requestRender：tui.requestRender 内部有 renderRequested 防重入，
    // time/duration 每秒变化时 widget render 会重画，与聊天输出不会冲突。
    const tui = _tui as { requestRender: () => void } | null;
    const interval = setInterval(() => tui?.requestRender?.(), 1000);
    let lastTier: WidthTier = "wide";
    let lastWidth = -1;
    let cached: string[] = [];
    return {
      dispose(): void {
        clearInterval(interval);
      },
      invalidate(): void {},
      render(width: number): string[] {
        const state: FooterState = {
          ...getState(),
          gitBranch: getGitBranch(),
        };
        const tier = getTier(width);
        const segs = buildSegments(state, theme, tier);
        let line = assembleLine(segs, theme.fg("muted", IC.sep), width);
        if (visibleWidth(line) > width) {
          line = truncateToWidth(line, width, "");
        }
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
/**
 * 空 footer 工厂 —— 隐藏 pi 内置 footer（仍在 ui 树最底，但视觉上不可见）。
 * 闭包内捕获 footerData 引用供 status bar widget 读 git branch。
 */
export function createEmptyFooter(
  onCreated?: (footerData: ReadonlyFooterDataProvider) => void,
): (
  tui: unknown,
  theme: Theme,
  footerData: ReadonlyFooterDataProvider,
) => Component {
  return (_tui, _theme, footerData) => {
    onCreated?.(footerData);
    return {
      dispose(): void {},
      invalidate(): void {},
      render(): string[] {
        return [];
      },
    };
  };
}
