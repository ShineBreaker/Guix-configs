// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * HerdrBackend — MultiplexerBackend 的 herdr 实现
 *
 * herdr 是终端多路复用器（与 tmux 对等）。CLI 通过 `herdr pane` 子命令
 * 控制 pane：split（创建空 pane）+ run（在其中执行命令）两步，区别于
 * tmux 的 split-window <cmd> 一步到位。
 *
 * 关键差异（接受，不抹平）：
 *   - herdr split 创建的新 pane 在主 pane **下方**（--direction down），
 *     tmux 在上方（-b）。纯界面差异，不影响 monitor 的 status.json 轮询。
 *   - herdr pane ID 是不透明字符串（如 w1:p1），tmux 是 %N。
 *   - herdr 无「焦点切回」概念：split 用 --no-focus，焦点从未离开主 pane，
 *     refocus() 是 no-op。
 *
 * 环境契约：HERDR_ENV=1 时 herdr 向每个 managed pane 注入
 *   HERDR_WORKSPACE_ID / HERDR_TAB_ID / HERDR_PANE_ID。
 */

import { execFileSync } from "node:child_process";
import type { MultiplexerBackend } from "./types.ts";

/** 同步执行 herdr 命令，返回 stdout（已 trim） */
function herdrExec(args: string[]): string {
  return execFileSync("herdr", args, {
    encoding: "utf-8",
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();
}

/** 同步执行 herdr 命令，失败返回 null */
function herdrExecMaybe(args: string[]): string | null {
  try {
    return herdrExec(args);
  } catch {
    return null;
  }
}

/**
 * 从 herdr pane split 的 JSON 响应中提取新 pane ID。
 *
 * herdr split 返回形状（v0.7.5）：`{ result: { pane: { pane_id: "w1:p2", ... } } }`
 * 解析失败抛错——split 必须返回合法 pane id，否则后续 run/setTitle 无法进行。
 */
function parsePaneId(json: string): string {
  const parsed = JSON.parse(json) as {
    result?: { pane?: { pane_id?: string } };
  };
  const paneId = parsed?.result?.pane?.pane_id;
  if (typeof paneId !== "string" || !paneId) {
    throw new Error(`herdr split 未返回 pane_id: ${json.slice(0, 200)}`);
  }
  return paneId;
}

export class HerdrBackend implements MultiplexerBackend {
  readonly name = "herdr" as const;

  /**
   * 当前 pane ID。
   *
   * herdr 向每个 managed pane 注入 HERDR_PANE_ID env，直接读最快。
   * env 缺失（不该发生，HERDR_ENV=1 时必注入）→ 兜底用 CLI 查。
   */
  currentPaneId(): string {
    if (process.env.HERDR_PANE_ID) return process.env.HERDR_PANE_ID;
    // 兜底：CLI 查（--current 指当前调用 pane）
    const out = herdrExec(["pane", "current", "--current"]);
    const parsed = JSON.parse(out) as { pane_id?: string };
    if (!parsed?.pane_id) {
      throw new Error("无法确定当前 herdr pane id");
    }
    return parsed.pane_id;
  }

  /**
   * 在当前 pane 下方垂直分割新 pane（herdr 只有 down，无 up），
   * 在其中运行 cmd，返回新 pane ID。
   *
   * 两步：split（创建空 pane，--no-focus 不抢焦点）+ run（发命令）。
   * ratio 直接传 herdr（float 0-1，与 tmux percentage 不同）。
   */
  splitAbove(cmd: string, ratio: number): string {
    const splitJson = herdrExec([
      "pane",
      "split",
      "--current",
      "--direction",
      "down",
      "--no-focus",
      "--ratio",
      String(ratio),
    ]);
    const paneId = parsePaneId(splitJson);
    herdrExec(["pane", "run", paneId, cmd]);
    return paneId;
  }

  /**
   * 在指定 pane 右侧水平分割新 pane，运行 cmd，返回新 pane ID。
   * 用于 parallel/chain 在顶部行内扩展。同样两步 split + run。
   */
  splitRight(targetPaneId: string, cmd: string, ratio: number): string {
    const splitJson = herdrExec([
      "pane",
      "split",
      targetPaneId,
      "--direction",
      "right",
      "--no-focus",
      "--ratio",
      String(ratio),
    ]);
    const paneId = parsePaneId(splitJson);
    herdrExec(["pane", "run", paneId, cmd]);
    return paneId;
  }

  /** 设置 pane 标签（herdr pane rename）。失败静默。 */
  setTitle(paneId: string, title: string): void {
    herdrExecMaybe(["pane", "rename", paneId, title]);
  }

  /**
   * 焦点切回 — herdr no-op。
   *
   * split 用 --no-focus，焦点从未离开主 pane，无需切回。
   * 保留方法以满足接口契约。
   */
  refocus(_paneId: string): void {
    // intentionally no-op
  }

  /**
   * 检查 pane 是否存活。
   *
   * herdr pane get 对已关闭 pane 返回非零 exit；用 herdrExecMaybe 捕获，
   * 非 null 即存活。注意：herdr pane ID 关闭后不重用，get 失败 = 已死。
   */
  isAlive(paneId: string): boolean {
    return herdrExecMaybe(["pane", "get", paneId]) !== null;
  }

  /** 关闭 pane（herdr 子命令是 close 而非 kill）。失败静默。 */
  kill(paneId: string): void {
    herdrExecMaybe(["pane", "close", paneId]);
  }
}
