// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * TmuxBackend — MultiplexerBackend 的 tmux 实现
 *
 * 从 launcher.ts 迁出的 tmux 操作（tmuxExec/splitAbove/splitRight/isAlive/kill），
 * 行为与原实现字节级一致。ratio 参数（float 0-1）在内部转换为 tmux 的
 * percentage（int 0-100）。
 */

import { execFileSync } from "node:child_process";
import type { MultiplexerBackend } from "./types.ts";

/** 同步执行 tmux 命令，返回 stdout（已 trim） */
function tmuxExec(args: string[]): string {
  return execFileSync("tmux", args, {
    encoding: "utf-8",
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();
}

/** 同步执行 tmux 命令，失败返回 null */
function tmuxExecMaybe(args: string[]): string | null {
  try {
    return tmuxExec(args);
  } catch {
    return null;
  }
}

/** float ratio (0-1) → tmux percentage (int 1-100)，夹紧到合法范围 */
function ratioToPercent(ratio: number): string {
  return String(Math.max(1, Math.min(100, Math.round(ratio * 100))));
}

export class TmuxBackend implements MultiplexerBackend {
  readonly name = "tmux" as const;

  currentPaneId(): string {
    return tmuxExec(["display-message", "-p", "#{pane_id}"]);
  }

  splitAbove(cmd: string, ratio: number): string {
    // -v 垂直分割；-b 在当前 pane 之前（上方）；-P -F 打印新 pane id
    return tmuxExec([
      "split-window",
      "-v",
      "-b",
      "-p",
      ratioToPercent(ratio),
      "-P",
      "-F",
      "#{pane_id}",
      cmd,
    ]);
  }

  splitRight(targetPaneId: string, cmd: string, ratio: number): string {
    // -h 水平分割（右侧）；-t 指定基准 pane
    return tmuxExec([
      "split-window",
      "-t",
      targetPaneId,
      "-h",
      "-p",
      ratioToPercent(ratio),
      "-P",
      "-F",
      "#{pane_id}",
      cmd,
    ]);
  }

  setTitle(paneId: string, title: string): void {
    tmuxExecMaybe(["select-pane", "-t", paneId, "-T", title]);
  }

  refocus(paneId: string): void {
    tmuxExecMaybe(["select-pane", "-t", paneId]);
  }

  isAlive(paneId: string): boolean {
    return (
      tmuxExecMaybe(["display-message", "-p", "-t", paneId, "#{pane_id}"]) ===
      paneId
    );
  }

  kill(paneId: string): void {
    tmuxExecMaybe(["kill-pane", "-t", paneId]);
  }
}
