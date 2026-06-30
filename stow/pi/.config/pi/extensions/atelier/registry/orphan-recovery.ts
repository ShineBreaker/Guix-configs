// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Orphan Recovery — 启动时扫描 unsettled run 并把过期者标为 orphan。
 *
 * 触发场景：pi 进程被 SIGKILL、机器突然断电、wrapper 子进程被 OOM kill。
 * 后果：status.json 卡在 `{status: "running"}` 永不进入终态。
 *
 * 策略：
 *  - 启动后 grace 期（默认 30s）内启动的新 run 不标 —— 给 wrapper 写终态时间
 *  - grace 期外的 unsettled run 一定是孤儿：tmux pane 都已随旧 pi 死掉
 *  - 已标 orphan / stuck 的 run 跳过（幂等 + 让 stuck 状态留住）
 *
 * 设计权衡：不开 grace 更激进，但 wrapper 启动到第一次写终态的窗口期
 * 内（通常 < 5s）会误杀已完成的 run；30s 是保守安全值。
 */

import { listUnsettled, updateRunStatus } from "./registry.ts";

/** 启动 grace 期（ms），期内启动的新 run 不标 orphan */
const STARTUP_GRACE_MS = 30_000;

/** orphan 标记的错误描述（写进 atelier_runs.error 列） */
const ORPHAN_ERROR = "orphaned: process restarted before completion";

export interface OrphanRecoveryReport {
  scanned: number;
  recovered: number;
  skippedByGrace: number;
  skippedByStatus: number;
}

/**
 * 把 unsettled 且超过 grace 期的所有 run 标为 orphan。
 *
 * 应在 `rebuildFromStatusFiles()` 之后调用 —— 让 rebuild 先把 status.json
 * 同步进 SQLite，然后再做正式判定（recover 只看 SQLite 状态）。
 *
 * @returns 报告：scanned 扫描总数，recovered 标 orphan 数量，
 *          skippedByGrace grace 期内跳过数，skippedByStatus 已 stuck/orphan 跳过数。
 */
export function orphanRecovery(now: number = Date.now()): OrphanRecoveryReport {
  const unsettled = listUnsettled();
  const report: OrphanRecoveryReport = {
    scanned: unsettled.length,
    recovered: 0,
    skippedByGrace: 0,
    skippedByStatus: 0,
  };

  for (const run of unsettled) {
    // 跳过已 stuck（stuck-detector 标的，wrapper 终态写入会覆盖）
    // 跳过已 orphan（幂等：重新标 orphan 没意义）
    if (run.status === "stuck" || run.status === "orphan") {
      report.skippedByStatus++;
      continue;
    }

    if (now - run.startedAt < STARTUP_GRACE_MS) {
      report.skippedByGrace++;
      continue;
    }

    updateRunStatus({
      runId: run.runId,
      status: "orphan",
      error: ORPHAN_ERROR,
      finishedAt: now,
    });
    report.recovered++;
  }

  return report;
}
