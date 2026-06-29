// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Checkpoint 系统 (PR-10)
 *
 * 参考 MiMoCode `session/checkpoint.ts`(1500+ 行,简化取核心)+ `checkpoint-templates.ts`。
 *
 * 目标: 长程任务(5+ 步 chain、复杂并行)跨崩溃可恢复。
 *
 * 简化决策:
 *   - 用 YAML-like 文本文件(只保留 4 节:Active intent / Steps / Intermediate results / Inherited context snapshot)
 *   - 写入 `.agents/workflows/{runId}.yaml`(注: 暂用 JSON 序列化以便 Node 原生处理,
 *     真正的 YAML 写出留给后续 PR 升级)
 *   - 每完成一步写一次(轻量级持久化)
 *   - API: `writeCheckpoint()`, `readCheckpoint()`, `validateCheckpoint()`
 *
 * 校验:
 *   - checkpoint 必须存在
 *   - totalSteps 匹配当前 chain 定义(若不匹配→ error)
 *   - currentStep 只能向前(API 拒绝后退)
 *
 * 不在范围内:
 *   - 真正的 YAML 解析器
 *   - inherited context 的语义压缩(compaction 留给后续)
 *   - checkpoint 与 status.json 双写一致性保证(本阶段只信任 checkpoint 自身)
 */

import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";

/** step 单条记录: 当前执行状态 + 输出引用 */
export interface CheckpointStep {
  /** step 在 chain/parallel 中的索引(0-based) */
  index: number;
  /** step 名(id from workflow, 或 chain[N].agent) */
  id: string;
  /** 启动的 agent */
  agent: string;
  /** step 执行的 task 描述 */
  task: string;
  /** 状态 */
  status: "pending" | "running" | "completed" | "failed";
  /** 完成的 ISO 时间戳 */
  completedAt?: string;
  /** 该 step runId(workspace/{runId}/ 子目录名) */
  runId?: string;
  /** 该 step 输出 preview(前 200 字) */
  outputPreview?: string;
}

/** 完整 checkpoint 数据结构 */
export interface CheckpointData {
  /** 对应 parent run id(sa-xxx) */
  runId: string;
  /** 模式: chain | parallel */
  mode: "chain" | "parallel";
  /** 总步数 */
  totalSteps: number;
  /** 当前步骤(0-based);-1 表示还没开始 */
  currentStep: number;
  /** ISO 时间戳 */
  createdAt: string;
  updatedAt: string;
  /** Active intent(§1): 一句描述本 checkpoint 的目标 */
  activeIntent: string;
  /** Step 列表 */
  steps: CheckpointStep[];
  /** §3: intermediate results —— 每个 step 关联的 workfile / result 文件路径 */
  intermediateResults: Array<{
    stepIndex: number;
    workfilePath?: string;
    runId?: string;
  }>;
  /** §4: inherited context snapshot —— 上一步的 finalText 前 2000 字(冻结不可变) */
  inheritedContextSnapshot: string;
}

const CHECKPOINT_FORMAT_VERSION = 1;
const INHERITED_CONTEXT_MAX = 2000; // §4 截断长度(避免文件爆炸)

/** 校验失败的错误 */
export class CheckpointError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CheckpointError";
  }
}

/**
 * 计算 checkpoint 写入路径。
 *   存储于 `.agents/workflows/{runId}.yaml` (本阶段先用 .json 后缀因 Node 原生)
 */
export function resolveCheckpointPath(cwd: string, runId: string): string {
  const dir = path.join(cwd, ".agents", "workflows");
  return path.join(dir, `${runId}.json`);
}

/**
 * 写入 checkpoint(原子: 先写 tmp 文件再 rename)。
 *
 * @returns 写入的文件路径
 */
export function writeCheckpoint(
  checkpoint: CheckpointData,
  cwd: string,
): string {
  const filePath = resolveCheckpointPath(cwd, checkpoint.runId);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });

  // 新增字段: format version + updatedAt 刷新
  const data: CheckpointData & { __format__: number } = {
    ...checkpoint,
    updatedAt: new Date().toISOString(),
    __format__: CHECKPOINT_FORMAT_VERSION,
  };

  const tmpPath = `${filePath}.tmp-${crypto.randomBytes(2).toString("hex")}`;
  fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2), "utf-8");
  fs.renameSync(tmpPath, filePath);
  return filePath;
}

/**
 * 读取 checkpoint。失败 → 返回 null。
 */
export function readCheckpoint(
  cwd: string,
  runId: string,
): CheckpointData | null {
  const filePath = resolveCheckpointPath(cwd, runId);
  if (!fs.existsSync(filePath)) return null;
  try {
    const raw = JSON.parse(fs.readFileSync(filePath, "utf-8")) as
      | CheckpointData
      | (CheckpointData & { __format__: number });
    // 校验关键字段
    if (
      typeof raw.runId !== "string" ||
      typeof raw.totalSteps !== "number" ||
      typeof raw.currentStep !== "number" ||
      !Array.isArray(raw.steps)
    ) {
      console.warn(
        `[atelier:checkpoint] ${runId} 数据结构异常，runId=${raw.runId}`,
      );
      return null;
    }
    return raw as CheckpointData;
  } catch (err) {
    console.warn(`[atelier:checkpoint] failed to parse ${filePath}:`, err);
    return null;
  }
}

/**
 * 校验 checkpoint 的合法性(供 resume / 诊断用)。
 *
 * 规则:
 *   - 必须存在 (readCheckpoint 返回非 null)
 *   - currentStep ∈ [-1, totalSteps - 1] 范围内
 *   - steps.length === totalSteps
 *   - 不能 resume 到比当前 currentStep 早的步骤
 *
 * @throws CheckpointError 校验失败
 */
export function validateCheckpoint(
  checkpoint: CheckpointData,
  opts: { resumeFrom?: number } = {},
): void {
  if (checkpoint.currentStep < -1) {
    throw new CheckpointError(
      `currentStep ${checkpoint.currentStep} < -1, 数据损坏`,
    );
  }
  if (checkpoint.currentStep >= checkpoint.totalSteps) {
    throw new CheckpointError(
      `currentStep ${checkpoint.currentStep} >= totalSteps ${checkpoint.totalSteps}, 数据损坏`,
    );
  }
  if (checkpoint.steps.length !== checkpoint.totalSteps) {
    throw new CheckpointError(
      `steps.length(${checkpoint.steps.length}) !== totalSteps(${checkpoint.totalSteps})`,
    );
  }
  if (
    opts.resumeFrom !== undefined &&
    opts.resumeFrom < checkpoint.currentStep
  ) {
    throw new CheckpointError(
      `resumeFrom ${opts.resumeFrom} < 当前 currentStep ${checkpoint.currentStep},API 拒绝后退`,
    );
  }
}

/**
 * 创建空的 checkpoint 骨架(初次建立时调用)。
 *
 * @param runId     parent run id
 * @param mode      chain | parallel
 * @param steps     step 描述列表(只取 agent / task / id,不取 outputs)
 * @param intent    Active intent 文本
 */
export function createCheckpoint(
  runId: string,
  mode: "chain" | "parallel",
  steps: Array<{ id: string; agent: string; task: string }>,
  intent: string,
): CheckpointData {
  const now = new Date().toISOString();
  return {
    runId,
    mode,
    totalSteps: steps.length,
    currentStep: -1,
    createdAt: now,
    updatedAt: now,
    activeIntent: intent,
    steps: steps.map((s, i) => ({
      index: i,
      id: s.id,
      agent: s.agent,
      task: s.task,
      status: "pending",
    })),
    intermediateResults: [],
    inheritedContextSnapshot: "",
  };
}

/**
 * 标记 step 完成,并推进 currentStep。
 *
 * @returns 更新后的 CheckpointData(未落盘,调用方需 writeCheckpoint)
 */
export function markStepCompleted(
  checkpoint: CheckpointData,
  stepIndex: number,
  opts: {
    runId?: string;
    workfilePath?: string;
    outputPreview?: string;
    inheritedContextForNext?: string;
  } = {},
): CheckpointData {
  if (stepIndex < 0 || stepIndex >= checkpoint.totalSteps) {
    throw new CheckpointError(`stepIndex ${stepIndex} 越界`);
  }
  const step = checkpoint.steps[stepIndex];
  step.status = "completed";
  step.completedAt = new Date().toISOString();
  if (opts.runId) step.runId = opts.runId;
  if (opts.outputPreview) step.outputPreview = opts.outputPreview;

  if (opts.workfilePath || opts.runId) {
    checkpoint.intermediateResults.push({
      stepIndex,
      workfilePath: opts.workfilePath,
      runId: opts.runId,
    });
  }

  // 推进 currentStep
  checkpoint.currentStep = Math.max(checkpoint.currentStep, stepIndex);

  // 写入 inherited snapshot 给下一步
  if (opts.inheritedContextForNext) {
    checkpoint.inheritedContextSnapshot = opts.inheritedContextForNext.slice(
      0,
      INHERITED_CONTEXT_MAX,
    );
  }
  checkpoint.updatedAt = new Date().toISOString();
  return checkpoint;
}

/**
 * 把 checkpoint 标记为失败。
 */
export function markCheckpointFailed(
  checkpoint: CheckpointData,
  stepIndex: number,
  error: string,
): CheckpointData {
  if (stepIndex >= 0 && stepIndex < checkpoint.totalSteps) {
    checkpoint.steps[stepIndex].status = "failed";
    checkpoint.steps[stepIndex].outputPreview =
      `failed: ${error.slice(0, 200)}`;
  }
  checkpoint.updatedAt = new Date().toISOString();
  return checkpoint;
}
