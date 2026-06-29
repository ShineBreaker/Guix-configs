// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Stuck Detector — 周期性扫 registry 中的 active run，发现超阈值无更新的标 stuck。
 *
 * "无更新"语义：当前阶段 lastTurnAt == startedAt（turn 计数留给后续 PR），
 * 所以扫描等价于"started_at 距今 > STUCK_THRESHOLD_MS 且 status 还在 running"。
 *
 * 设计参考 MiMoCode actor/registry.ts:13-14, 358-392 的 scanStuck 实现。
 * 本实现大幅简化：
 *  - 阈值固定 5 分钟（oracle 评估：长程任务确有可能，建议后续可配）
 *  - 扫描间隔 60s（后台 fiber，不阻塞主进程）
 *  - emit 用 callback（本阶段没有 Bus 事件总线，console.warn 是接收器）
 *
 * 进程退出行为：setInterval handle 调 unref()，不阻塞进程退出。
 */

import { listActive, updateRunStatus } from "./registry.ts";

/** 5 分钟无 turn 更新即视为卡住 */
export const STUCK_THRESHOLD_MS = 5 * 60 * 1000;

/** 后台扫描间隔 */
export const SCAN_INTERVAL_MS = 60 * 1000;

/** 扫描发现的 actor stuck 事件（emit 给外部） */
export interface ActorStuckEvent {
  type: "actorStuck";
  runId: string;
  agent: string;
  /** 距离 lastTurnAt 多少 ms（>= STUCK_THRESHOLD_MS） */
  sinceMs: number;
  /** detector 探测时刻（ms epoch） */
  detectedAt: number;
}

/** stuck 标记的错误描述 */
const STUCK_ERROR_PREFIX = "stuck: no turn for";

export interface StuckScanReport {
  scanned: number;
  stuck: number;
  skippedAlreadyStuck: number;
}

/**
 * 同步扫一次 listActive()，找出"开始时间距今 > STUCK_THRESHOLD_MS 且 status=running"
 * 的 run，标为 stuck + 触发 emit。
 *
 * 已 stuck 的 run 不重复处理（只触发一次事件，下次扫描它仍在 listActive 中
 * 但被跳过 —— 这是有意的，避免日志洪水）。
 *
 * @param emit  回调，每个新发现的 stuck actor 触发一次
 * @param now   可注入的"当前时间"用于测试
 */
export function scanStuck(
  emit: (event: ActorStuckEvent) => void,
  now: number = Date.now(),
): StuckScanReport {
  const active = listActive();
  const report: StuckScanReport = {
    scanned: active.length,
    stuck: 0,
    skippedAlreadyStuck: 0,
  };

  for (const run of active) {
    if (run.status === "stuck") {
      report.skippedAlreadyStuck++;
      continue;
    }
    // 仅 status === running 的有可能被标 stuck；orphan 不归本 detector 处理
    if (run.status !== "running") continue;

    const sinceMs = now - run.lastTurnAt;
    if (sinceMs < STUCK_THRESHOLD_MS) continue;

    const seconds = Math.round(sinceMs / 1000);
    updateRunStatus({
      runId: run.runId,
      status: "stuck",
      error: `${STUCK_ERROR_PREFIX} ${seconds}s`,
      finishedAt: null, // 显式 null 防止 COALESCE 写入
    });

    emit({
      type: "actorStuck",
      runId: run.runId,
      agent: run.agent || "(unknown)",
      sinceMs,
      detectedAt: now,
    });
    report.stuck++;
  }

  return report;
}

/** startStuckDetector 返回的对象；调用 stop() 停止扫描。 */
export interface StuckDetectorHandle {
  stop(): void;
  /** 最后一次扫描的 report（每次扫描后更新） */
  readonly lastReport: StuckScanReport | null;
}

/**
 * 启动 stuck detector 后台 fiber（setInterval）。
 *
 * 行为：
 *  - interval handle 调 unref()，不阻塞进程退出
 *  - 第一次扫描在 1s 后（避免与 orphan recovery / rebuild 抢时机）
 *  - emit 默认 console.warn，将来可改为 PI 事件总线
 *
 * @returns handle，调用 stop() 停止（clearInterval + 阻止内存泄漏）
 */
export function startStuckDetector(
  emit: (event: ActorStuckEvent) => void = defaultEmitter,
): StuckDetectorHandle {
  let lastReport: StuckScanReport | null = null;

  const handle = setInterval(() => {
    lastReport = scanStuck(emit, Date.now());
  }, SCAN_INTERVAL_MS);

  // 不阻塞 pi 主进程退出
  if (typeof handle.unref === "function") handle.unref();

  return {
    stop: () => clearInterval(handle),
    get lastReport() {
      return lastReport;
    },
  };
}

/** 默认 emitter：写到 console.warn，便于用户视觉发现。 */
function defaultEmitter(event: ActorStuckEvent): void {
  const seconds = Math.round(event.sinceMs / 1000);
  console.warn(
    `[atelier:stuck] run ${event.runId} (${event.agent}) 无 turn 更新 ${seconds}s`,
  );
}
