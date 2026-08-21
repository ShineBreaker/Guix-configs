// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Resume 机制 (PR-10)
 *
 * 目标: chain/parallel 中途崩溃后,从 checkpoint 续跑未完成步骤。
 *
 * 设计 (参考 MiMoCode `session/checkpoint.ts` + `actor/spawn.ts:81-91`):
 *   - `resumeChain(parentRunId, config, cwd)` 是公开 API
 *   - 调用方传 parent runId,我们读 checkpoint(currentStep 已知,跳过已完成的步)
 *   - 校验通过 → 返回 next step 信息供调用方 dispatch
 *   - 校验失败 → throw CheckpointError
 *
 * 注意: 本模块**不真实启动 subagent**(避免 subagent spawn 依赖 tmux 状态)。
 * 调用方拿到 `NextStep` 后调 launcher / runner 真实 dispatch。
 *
 * 三种返回形态:
 *   - 完整成功但还没跨当前进程: 返回 ResumePlan{ steps, currentStep, totalSteps }
 *   - 检查失败: 抛 CheckpointError
 *   - 已 complete: 返回 { finished: true, ... }
 */

import * as path from "node:path";
import {
  type CheckpointData,
  type CheckpointStep,
  CheckpointError,
  readCheckpoint,
  validateCheckpoint,
} from "./checkpoint.ts";

/** resume plan: 描述从哪个 step 开始继续 */
export interface ResumePlan {
  /** parent run id */
  parentRunId: string;
  /** checkpoint mode */
  mode: "chain" | "parallel";
  /** 当前已完成的 step(0-based),即 currentStep */
  currentStep: number;
  /** 总步数 */
  totalSteps: number;
  /** 待续跑的 step 列表(stepIndex currentStep+1 .. totalSteps-1) */
  remainingSteps: CheckpointStep[];
  /** 当前 step 的 inherited context snapshot(给下一步用) */
  inheritedContextSnapshot: string;
  /** checkpoint 文件路径(写后续时定位) */
  checkpointPath: string;
}

/** 已全部完成(无需 resume) */
export interface FinishedResume {
  finished: true;
  parentRunId: string;
  totalSteps: number;
}

/** resume API 的返回类型 */
export type ResumeResult = ResumePlan | FinishedResume;

/**
 * 从 checkpoint 文件读取 + 校验 + 计算剩余步骤。
 *
 * 注意: 这是**纯计算函数**,不真实启动 subagent。
 * 调用方拿到 plan 后,通过 launcher.runChain / runner.runParallelBatches
 * 把 remainingSteps 转成 RunResult。
 *
 * @throws CheckpointError 校验失败(含 API 拒绝后退)
 */
export function resumeChain(
  parentRunId: string,
  config: { allowBackward?: boolean } = {},
  cwd: string = process.cwd(),
): ResumeResult {
  const checkpoint = readCheckpoint(cwd, parentRunId);
  if (!checkpoint) {
    throw new CheckpointError(`未找到 checkpoint: ${parentRunId}(cwd=${cwd})`);
  }
  // 校验 + 不允许后退(默认;allowBackward=true 时跳过此校验)
  validateCheckpoint(
    checkpoint,
    config.allowBackward ? {} : { resumeFrom: checkpoint.currentStep },
  );

  if (checkpoint.currentStep >= checkpoint.totalSteps - 1) {
    // 全部完成
    return {
      finished: true,
      parentRunId,
      totalSteps: checkpoint.totalSteps,
    };
  }

  // 当前步是 currentStep+1(因为 currentStep 指向**已完成**的最大 step)
  const remainingSteps = checkpoint.steps.slice(checkpoint.currentStep + 1);

  return {
    parentRunId,
    mode: checkpoint.mode,
    currentStep: checkpoint.currentStep,
    totalSteps: checkpoint.totalSteps,
    remainingSteps,
    inheritedContextSnapshot: checkpoint.inheritedContextSnapshot,
    checkpointPath: path.join(
      cwd,
      ".agents",
      "workflows",
      `${parentRunId}.json`,
    ),
  };
}
