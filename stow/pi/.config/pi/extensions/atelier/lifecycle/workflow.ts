// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Workflow 简化版 (PR-11)
 *
 * 参考 MiMoCode `workflow/persistence.ts` + `workflow/runtime.ts`。
 *
 * 简化决策(用户决策):
 *   - 只支持**线性 chain**(depends_on 形成一条线),不做 topological sort
 *   - 1 文件 = ~250 行: 数据 + serialize/deserialize + persist/load
 *   - 不做 fork/reclaim(复杂 fork 留给 MiMoCode 完整版)
 *   - 不做 mermaid 可视化(oracle 强烈建议砍)
 *   - 不做 workflow-resume.ts / workflow-events.ts(本次只交付核心)
 *
 * 设计要点:
 *   - `WorkflowStep`: 单步定义 + 状态
 *   - `Workflow`: 完整工作流定义
 *   - `nextReadyStep(workflow)`: 返回下一个可执行 step(线性 chain 形态)
 *   - `serialize` / `deserialize`: JSON 双向转换
 *   - `persistWorkflow` / `loadWorkflow`: 落盘到 `.agents/workflows/{id}.json`
 */

import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";

/** 单步状态 */
export type StepStatus = "pending" | "running" | "completed" | "failed";

/** 单步定义 + 运行时状态 */
export interface WorkflowStep {
  /** step id(workflow 内部唯一) */
  id: string;
  /** 启动的 agent 名 */
  agent: string;
  /** step 执行的 task 描述 */
  task: string;
  /** 依赖的 step id 列表;空数组表示可立即开始 */
  dependsOn: string[];
  /** 当前状态 */
  status: StepStatus;
  /** 该 step 对应的 subagent runId(运行时填) */
  runId?: string;
  /** 输出 preview 文本 */
  outputPreview?: string;
}

/** 完整工作流定义 */
export interface Workflow {
  /** workflow id(wf-yyyymmdd-3bytehex) */
  id: string;
  /** 人类可读的名字(如 "implement-and-review") */
  name: string;
  /** 执行模式: linear chain | parallel stages */
  mode: "chain" | "parallel";
  /** steps 列表(顺序可任意,dependsOn 决定调度) */
  steps: WorkflowStep[];
  /** 上下文占位符(给 task 模板的 {var} 替换用) */
  context: Record<string, string>;
  /** parent run id(PR-10 关联) */
  parentRunId?: string;
}

/** Workflow 持久化文件路径 */
export function resolveWorkflowPath(cwd: string, id: string): string {
  return path.join(cwd, ".agents", "workflows", `${id}.json`);
}

/** 生成 workflow id */
export function generateWorkflowId(): string {
  const now = new Date();
  const yyyymmdd =
    now.getFullYear().toString() +
    String(now.getMonth() + 1).padStart(2, "0") +
    String(now.getDate()).padStart(2, "0");
  return `wf-${yyyymmdd}-${crypto.randomBytes(3).toString("hex")}`;
}

/** 把 workflow 序列化为 JSON 字符串 */
export function serialize(workflow: Workflow): string {
  return JSON.stringify(workflow, null, 2);
}

/** 把 JSON 字符串反序列化为 Workflow */
export function deserialize(json: string): Workflow {
  const parsed = JSON.parse(json) as Workflow;
  // 简单校验
  if (typeof parsed.id !== "string" || !Array.isArray(parsed.steps)) {
    throw new Error("invalid workflow JSON: missing id or steps");
  }
  return parsed;
}

/**
 * 找到下一个 ready step。
 *
 * 简化决策: 只支持线性 chain(`mode === "chain"`)且 dependsOn 形成一条线的情况。
 * 返回第一个 status === "pending" 且所有依赖已 completed 的 step;
 * 若没有或全 completed → 返回 null。
 *
 * 不做真正的 topological sort(用户决策,等需要 DAG 时再扩展)。
 */
export function nextReadyStep(workflow: Workflow): WorkflowStep | null {
  // 简化版本只处理线性场景: 返回第一个 pending 且 (dependsOn.length === 0 ||
  // 所有 dependsOn 已 completed)的 step
  for (const step of workflow.steps) {
    if (step.status !== "pending") continue;
    if (step.dependsOn.length === 0) return step;
    // 检查依赖是否全部 completed
    const allCompleted = step.dependsOn.every((depId) => {
      const dep = workflow.steps.find((s) => s.id === depId);
      return dep?.status === "completed";
    });
    if (allCompleted) return step;
  }
  return null;
}

/**
 * 把 Workflow 持久化到 `.agents/workflows/{id}.json`(原子写)。
 *
 * @returns 写入的文件路径
 */
export function persistWorkflow(workflow: Workflow, cwd: string): string {
  const filePath = resolveWorkflowPath(cwd, workflow.id);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });

  const tmpPath = `${filePath}.tmp-${crypto.randomBytes(2).toString("hex")}`;
  fs.writeFileSync(tmpPath, serialize(workflow), "utf-8");
  fs.renameSync(tmpPath, filePath);
  return filePath;
}

/**
 * 从 `.agents/workflows/{id}.json` 加载 Workflow。文件不存在 → 返回 null。
 */
export function loadWorkflow(cwd: string, id: string): Workflow | null {
  const filePath = resolveWorkflowPath(cwd, id);
  if (!fs.existsSync(filePath)) return null;
  try {
    return deserialize(fs.readFileSync(filePath, "utf-8"));
  } catch (err) {
    console.warn(`[atelier:workflow] loadWorkflow failed for ${id}:`, err);
    return null;
  }
}

/**
 * 列出 cwd 下的所有 workflow id。
 *
 * 注意：workflow 与 checkpoint 共用 `.agents/workflows/` 目录——
 * checkpoint 文件名为 `{parentRunId}.json`（`sa-` 前缀），workflow 文件名
 * 为 `wf-yyyymmdd-...json`（见 generateWorkflowId）。只列 `wf-` 前缀文件，
 * 避免把 checkpoint 文件（结构不同，deserialize 会抛错）误列为 "(corrupt)"。
 */
export function listWorkflows(
  cwd: string,
): Array<{ id: string; name: string; mode: string }> {
  const dir = path.dirname(resolveWorkflowPath(cwd, "_"));
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => f.startsWith("wf-") && f.endsWith(".json"))
    .map((f) => {
      const id = f.replace(/\.json$/, "");
      try {
        const wf = loadWorkflow(cwd, id);
        return { id, name: wf?.name ?? "(unknown)", mode: wf?.mode ?? "chain" };
      } catch {
        return { id, name: "(corrupt)", mode: "chain" };
      }
    });
}

/** 把 WorkflowStep 转成 task 描述(task 模板替换 {var}) */
export function resolveStepTask(
  step: WorkflowStep,
  context: Record<string, string>,
): string {
  let task = step.task;
  for (const [key, value] of Object.entries(context)) {
    task = task.split(`{${key}}`).join(value);
  }
  return task;
}
