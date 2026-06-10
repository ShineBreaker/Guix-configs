// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 运行监控 — 轮询 run 目录的 status.json，等待 subagent 完成
 *
 * 支持：超时检测、pane 存活检测、abort signal、完成后读取结果
 */

import * as fs from "node:fs";
import * as path from "node:path";
import type { LaunchResult, RunResult, SubagentConfig } from "./types.ts";
import {
  getSubagentsDir,
  killPane,
  paneIsAlive,
  readResult,
  readStatus,
  writeFailedStatus,
} from "./launcher.ts";

/**
 * 轮询等待单个 subagent 完成。
 *
 * 检测机制（按 pollIntervalMs 间隔）：
 * 1. abort signal → 终止 pane，返回失败
 * 2. 超时 → 终止 pane，返回失败
 * 3. status.json 不再是 "running" → 读取 result.md，返回结果
 * 4. pane 不再存活 → 读取 stderr 日志，返回失败
 */
export async function waitForCompletion(
  launch: LaunchResult,
  config: SubagentConfig,
  signal?: AbortSignal,
): Promise<RunResult> {
  const startedAt = Date.now();

  return new Promise<RunResult>((resolve) => {
    const interval = setInterval(() => {
      const agent = launch.paneTitle.replace(config.panePrefix, "");

      // 统一的失败处理：清理 interval、写状态、resolve
      const finishFailed = (
        exitCode: number,
        output: string,
        error?: string,
      ) => {
        clearInterval(interval);
        writeFailedStatus(launch.runDir, exitCode, error ?? output, startedAt);
        resolve({
          runId: launch.runId,
          agent,
          status: "failed",
          exitCode,
          output,
          durationMs: Date.now() - startedAt,
          tmuxPane: launch.paneTitle,
          error,
        });
      };

      // 检查 abort
      if (signal?.aborted) {
        killPane(launch.paneId);
        finishFailed(-1, "Aborted", "Aborted");
        return;
      }

      // 检查超时
      if (Date.now() - startedAt > config.timeoutMs) {
        killPane(launch.paneId);
        finishFailed(124, `Timed out after ${config.timeoutMs}ms`, "timeout");
        return;
      }

      // 检查 status.json
      const status = readStatus(launch.runDir);
      if (status && status.status !== "running") {
        clearInterval(interval);
        const output = readResult(launch.runDir);
        resolve({
          runId: launch.runId,
          agent,
          status: status.status,
          exitCode: status.exitCode ?? 1,
          output,
          durationMs:
            (status.finishedAt ?? Date.now()) - (status.startedAt ?? startedAt),
          tmuxPane: launch.paneTitle,
          error: status.error,
        });
        return;
      }

      // 检查 pane 存活
      if (!paneIsAlive(launch.paneId)) {
        const stderrPath = path.join(launch.runDir, "stderr.log");
        let stderr = "";
        try {
          stderr = fs.readFileSync(stderrPath, "utf-8").trim();
        } catch {
          /* ignore */
        }
        finishFailed(
          127,
          stderr || "tmux pane exited before writing final status",
          stderr || undefined,
        );
      }
    }, config.pollIntervalMs);
  });
}

/** 等待多个 subagent 全部完成 */
export function waitForAll(
  launches: LaunchResult[],
  config: SubagentConfig,
  signal?: AbortSignal,
): Promise<RunResult[]> {
  return Promise.all(launches.map((l) => waitForCompletion(l, config, signal)));
}

/** 列出所有正在运行的 subagent（从 cache 目录扫描 status.json） */
export function listRunning(): RunResult[] {
  const subagentsDir = getSubagentsDir();
  if (!fs.existsSync(subagentsDir)) return [];

  const results: RunResult[] = [];
  for (const entry of fs.readdirSync(subagentsDir)) {
    const runDir = path.join(subagentsDir, entry);
    const status = readStatus(runDir);
    if (!status || status.status !== "running") continue;

    let task = "";
    try {
      task = fs.readFileSync(path.join(runDir, "task.md"), "utf-8");
    } catch {
      /* ignore */
    }

    results.push({
      runId: entry,
      agent: "(unknown)",
      status: "running",
      exitCode: -1,
      output: task.slice(0, 200),
      durationMs: Date.now() - (status.startedAt ?? Date.now()),
      tmuxPane: "",
    });
  }
  return results;
}
