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
import { updateRunStatus } from "./registry.ts";

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
        // 同步终态到全局 registry（SQLite）
        updateRunStatus({
          runId: launch.runId,
          status: "failed",
          exitCode,
          error: error ?? output,
        });
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

      // PR-7: 检查 status.json 终态
      const status = readStatus(launch.runDir);
      if (status && status.status !== "running") {
        clearInterval(interval);
        const output = readResult(launch.runDir);
        // wrapper 写的终态（completed / failed）同步到全局 registry
        updateRunStatus({
          runId: launch.runId,
          status: status.status === "completed" ? "completed" : "failed",
          exitCode: status.exitCode ?? 1,
          error: status.error,
        });
        // PR-7: 解析 result.md 的 Return Header，写入 registry return_status
        try {
          const parsed = parseReturnHeader(output);
          if (parsed) {
            updateRunReturnStatusInRegistry({
              runId: launch.runId,
              returnStatus: parsed.status,
              returnSummary: parsed.summary,
            });
          } else {
            // 缺 header: 标 unknown（不阻塞 subagent，仅警告）
            updateRunReturnStatusInRegistry({
              runId: launch.runId,
              returnStatus: "unknown",
              returnSummary: "(no return header)",
            });
            console.warn(
              `[atelier:monitor] run ${launch.runId} (${agent}) result.md 缺 Return Header，标 return_status=unknown`,
            );
          }
        } catch (headerErr) {
          console.warn(
            `[atelier:monitor] parseReturnHeader failed for ${launch.runId}:`,
            headerErr,
          );
        }

        // PR-8: completion gate（no-op: isTaskToolAvailable=false → 恒 false）
        // 当前阶段 isTaskToolAvailable() 返回 false，gate 不触发 reentry。
        // 架构保留便于未来接入 pi 的 task 工具。
        try {
          const gate = completionGateDecide(launch.runId, agent, 0);
          if (gate.needReentry) {
            incrementReentryCountInRegistry(launch.runId);
            console.warn(
              `[atelier:monitor] completion gate requested reentry for ${launch.runId} — 架构保留中，当前 no-op`,
            );
          }
          if (gate.downgradedTo) {
            console.warn(
              `[atelier:monitor] gate downgraded ${launch.runId} → ${gate.downgradedTo}`,
            );
          }
        } catch (gateErr) {
          console.warn(
            `[atelier:monitor] completionGate failed for ${launch.runId}:`,
            gateErr,
          );
        }

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
/**
 * 列出所有正在运行的 subagent（从 cache 目录扫描 status.json）
 *
 * PR-9: 默认隐藏系统子 agent。传 `{ includeSystem: true }` 可看全部。
 */
export function listRunning(
  opts: { includeSystem?: boolean } = {},
): RunResult[] {
  const includeSystem = opts.includeSystem ?? false;
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

    // PR-9: 默认隐藏系统子 agent（runId 以 sys- 开头）
    if (!includeSystem && entry.startsWith("sys-")) continue;

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
