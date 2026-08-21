// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Subagent 启动器 — 通过多路复用器（tmux/herdr）创建子 pane 运行 subagent
 *
 * 布局策略：
 *   single:  在当前 pane 上方/下方创建一个子 pane（占 40%）
 *   parallel: 先创建顶部/底部行，再水平分割为 N 个等宽子 pane
 *   chain:    复用 single，每步在前一步的 pane 位置继续分割
 *
 * 多路复用器抽象：具体 tmux/herdr 操作由 MultiplexerBackend 实现，
 * detectBackend() 按 HERDR_ENV/$TMUX 环境变量自动选择。launcher 只调接口。
 */

import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type {
  AgentConfig,
  AgentModelConfig,
  LaunchResult,
  StatusFile,
  SubagentConfig,
} from "../core/types.ts";
import {
  getPluginRoot,
  removeSubagentOnlyMarkers,
  resolveAgentFile,
} from "../core/context.ts";
import { registerRun } from "../registry/registry.ts";
import { formatReturnHeaderInstruction } from "../registry/return-header.ts";
import { isSystemAgent } from "../core/system-agents.ts";
import { detectBackend } from "./multiplexer/detect.ts";
import type { MultiplexerBackend } from "./multiplexer/types.ts";

// ─── XDG 路径 ────────────────────────────────────────────────────────────────

function resolveXdgCache(): string {
  return process.env.XDG_CACHE_HOME ?? path.join(os.homedir(), ".cache");
}

/** 所有运行数据的根目录 */
export function getSubagentsDir(): string {
  return path.join(resolveXdgCache(), "pi", "subagents");
}

/** 单次运行的目录 */
export function getRunDir(runId: string): string {
  return path.join(getSubagentsDir(), runId);
}

/**
 * wrapper 脚本所在目录（插件内置 scripts/）。
 *
 * 脚本内化后跟随插件位置：getPluginRoot()/scripts/。不再依赖外部
 * XDG_DATA_HOME 部署（旧路径已失效）。匹配 context/agents/ 的自包含模式。
 */
function getScriptsDir(): string {
  return path.join(getPluginRoot(), "scripts");
}

// ─── 多路复用器封装 ──────────────────────────────────────────────────────────
//
// launcher 内部用 detectBackend() 获取当前后端实例（tmux/herdr），调接口
// 完成 pane 控制。paneIsAlive/killPane 作为公共导出保留——monitor.ts 和
// runner.ts 基于 status.json 文件轮询（multiplexer 无关），它们通过这两个
// 薄包装间接调后端，无需感知具体实现。

/** Shell 单引号转义（buildWrapperCmd 用） */
function shellQuote(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`;
}

// ─── Run 目录管理 ────────────────────────────────────────────────────────────

/** 生成唯一 run ID */
export function generateRunId(): string {
  return `sa-${Date.now().toString(36)}-${crypto.randomBytes(3).toString("hex")}`;
}

/** 确保 wrapper 脚本可执行 */
function ensureWrapperExecutable(): string {
  const wrapper = path.join(getScriptsDir(), "subagent-wrapper.sh");
  try {
    fs.accessSync(wrapper, fs.constants.X_OK);
  } catch {
    throw new Error(`subagent wrapper is not executable: ${wrapper}`);
  }
  return wrapper;
}

/** 清理过期的运行记录 */
export function cleanupOldRuns(config: SubagentConfig): void {
  if (config.keepResults <= 0) return;

  const subagentsDir = getSubagentsDir();
  if (!fs.existsSync(subagentsDir)) return;

  const runs = fs
    .readdirSync(subagentsDir)
    .map((name) => {
      const runDir = path.join(subagentsDir, name);
      const status = readStatus(runDir);
      let mtimeMs = 0;
      try {
        mtimeMs = fs.statSync(runDir).mtimeMs;
      } catch {
        /* ignore */
      }
      return { name, runDir, status, mtimeMs };
    })
    .filter((run) => run.status?.status !== "running")
    .sort((a, b) => b.mtimeMs - a.mtimeMs);

  for (const run of runs.slice(config.keepResults)) {
    try {
      fs.rmSync(run.runDir, { recursive: true, force: true });
    } catch {
      /* ignore */
    }
  }
}

/** 向 run 目录写入失败状态 */
export function writeFailedStatus(
  runDir: string,
  exitCode: number,
  error: string,
  startedAt?: number,
): void {
  const now = Date.now();
  fs.writeFileSync(
    path.join(runDir, "status.json"),
    JSON.stringify({
      status: "failed",
      exitCode,
      error,
      startedAt: startedAt ?? now,
      finishedAt: now,
    }),
    "utf-8",
  );
}

/**
 * 检查 pane 是否仍存活（multiplexer 无关）。
 *
 * 公共导出：monitor.ts（pane 死亡检测）和 runner.ts（parallel batch 续接
 * 前检查 pane 存活）调用。内部委托 detectBackend()。
 */
export function paneIsAlive(paneId: string): boolean {
  return detectBackend().isAlive(paneId);
}

/**
 * 终止 pane（multiplexer 无关）。
 *
 * 公共导出：monitor.ts（abort/timeout 清理）调用。内部委托 detectBackend()。
 */
export function killPane(paneId: string): void {
  detectBackend().kill(paneId);
}

/** 创建 run 目录并写入初始状态 */
function prepareRunDir(runDir: string, task: string): void {
  fs.mkdirSync(runDir, { recursive: true });
  fs.writeFileSync(path.join(runDir, "task.md"), task, "utf-8");
  fs.writeFileSync(
    path.join(runDir, "status.json"),
    JSON.stringify({ status: "running", startedAt: Date.now() }),
    "utf-8",
  );
}

/**
 * 为 subagent 准备 prompt 文件（到 runDir/subagent-prompt.md）。
 *
 * 处理逻辑：
 *  1. 读 agent .md 全文
 *  2. 剥除 frontmatter（首个 --- 到第二个 --- 之间的内容）
 *  3. 去除 subagent-only HTML 注释标记（保留标记之间的内容）
 *  4. 写入 $runDir/subagent-prompt.md
 *
 * 如果 agent .md 不存在或读取失败，函数静默失败（返回 null）——调用方
 * 继续使用原 wrapper 逻辑（从 agent .md 直接读 prompt）。
 *
 * @returns 写入的文件路径，失败返回 null
 */
export function prepareAgentPrompt(
  agentName: string,
  runDir: string,
): string | null {
  // 走共享路径解析（插件内置 context/agents 优先，~/.config/pi/agents 兼容）
  const agentPath = resolveAgentFile(agentName);
  if (!agentPath) return null;

  let content: string;
  try {
    content = fs.readFileSync(agentPath, "utf-8");
  } catch {
    return null;
  }

  // 提取 body：跳到第二个 --- 之后的全部内容
  const lines = content.split("\n");
  let inFrontmatter = false;
  let frontmatterEnded = false;
  const bodyLines: string[] = [];
  for (const line of lines) {
    if (!frontmatterEnded && line === "---") {
      if (!inFrontmatter) {
        inFrontmatter = true;
        continue;
      } else {
        inFrontmatter = false;
        frontmatterEnded = true;
        continue;
      }
    }
    if (frontmatterEnded) {
      bodyLines.push(line);
    }
  }

  const rawBody = removeSubagentOnlyMarkers(bodyLines.join("\n")).trim();
  if (!rawBody) return null;

  // 一次性追加：能力自检段 + Return Header 指令 + agent 自有 body。
  // Return Header 指令（PR-7）让子 agent 在 final message 顶部写出结构化字段。
  const body = `${CAPABILITY_SELF_CHECK}\n\n${RETURN_FORMAT_INSTRUCTION}\n\n${rawBody}`;

  const promptPath = path.join(runDir, "subagent-prompt.md");
  try {
    fs.writeFileSync(promptPath, body, "utf-8");
    return promptPath;
  } catch {
    return null;
  }
}

/**
 * 能力自检段——统一注入到所有 subagent 的 prompt 头部。
 *
 * 动机：很多模型原生支持多模态（minimax-cn/MiniMax-M3、xiaomi/mimo-v2.5），
 * 但部分模型（zai/GLM-5.1、deepseek-v4-flash、deepseek-v4-pro 等）没有视觉能力。
 * 不在 atelier 维护 modelCapabilities 表，而是让模型自检：发现自己无视觉时
 * 显式调用 visual subagent 处理图片。
 */
const CAPABILITY_SELF_CHECK = `## 能力自检（重要）

如果你发现自己**没有视觉能力**（无法直接理解图片附件）但收到了图片附件，**不要**试图猜测图片内容。请调用 visual subagent 处理图片：

\`\`\`
subagent({ agent: "visual", task: "分析以下图片：[描述图片情境]", images: [...] })
\`\`\`

支持视觉的模型：minimax-cn/MiniMax-M3、xiaomi/mimo-v2.5。`;

// PR-7：Return Header 指令——统一注入到所有 subagent 的 prompt 头部。
// 让子 agent 在 final message 顶部写出 "Status:"/Summary 等结构化字段，
// 方便父会话结构化解析而非靠 regex 猜。
//
// 由 prepareAgentPrompt() 在 CAPABILITY_SELF_CHECK 之后追加。
const RETURN_FORMAT_INSTRUCTION = formatReturnHeaderInstruction();

/** 读取 run 目录下的 status.json */
export function readStatus(runDir: string): StatusFile | null {
  const statusPath = path.join(runDir, "status.json");
  try {
    return JSON.parse(fs.readFileSync(statusPath, "utf-8"));
  } catch {
    return null;
  }
}

/** 读取 run 目录下的 result.md */
export function readResult(runDir: string): string {
  const resultPath = path.join(runDir, "result.md");
  try {
    return fs.readFileSync(resultPath, "utf-8");
  } catch {
    return "(no output)";
  }
}

// ─── Wrapper 命令构造 ────────────────────────────────────────────────────────

/** 构造 wrapper 脚本的完整命令行 */
function buildWrapperCmd(
  runId: string,
  agent: AgentConfig,
  runDir: string,
  cwd?: string,
  model?: string,
  images?: string[],
  promptFile?: string,
): string {
  const wrapper = ensureWrapperExecutable();
  const args: string[] = [runId, agent.name, path.join(runDir, "task.md")];
  if (model) args.push("--model", model);
  if (cwd) args.push("--cwd", cwd);
  if (agent.tools && agent.tools.length > 0)
    args.push("--tools", agent.tools.join(","));
  if (images && images.length > 0) args.push("--image", images.join(","));
  if (promptFile) args.push("--prompt-file", promptFile);
  return [wrapper, ...args].map(shellQuote).join(" ");
}

// ─── 启动函数 ─────────────────────────────────────────────────────────────────

/**
 * 启动单个 subagent。
 *
 * 布局：
 *   - 无 topRowTargetPaneId → 在当前 pane 上方/下方垂直分割（后端决定方向）
 *   - 有 topRowTargetPaneId → 在指定 pane 右侧水平分割（chain 模式复用）
 *
 * splitPercent 是 tmux 时代的 API（0-100），内部转 ratio（0-1）给后端。
 */
export function launchSingle(
  agent: AgentConfig,
  task: string,
  config: SubagentConfig,
  cwd?: string,
  model?: string,
  topRowTargetPaneId?: string,
  splitPercent = 50,
  images?: string[],
  // PR-9: 系统子 agent 标记。默认由 isSystemAgent(agent.name) 推断；外部传 false 可强制覆盖
  isSystemSpawned?: boolean,
  // PR-10: chain / parallel batch 的 parent run id,关联到 atelier_runs.parent_run_id
  parentRunId?: string,
): LaunchResult {
  // detectBackend 抛错覆盖了原 process.env.TMUX 检查（tmux/herdr 都不在才抛）
  const backend: MultiplexerBackend = detectBackend();

  cleanupOldRuns(config);
  const myPaneId = backend.currentPaneId();
  const runId = generateRunId();
  const runDir = getRunDir(runId);
  prepareRunDir(runDir, task);
  // 同步注册到全局 registry（SQLite）；失败仅 console.warn，不阻塞 subagent
  registerRun({
    runId,
    agent: agent.name,
    mode: "single",
    runDir,
    taskExcerpt: task.slice(0, 200),
    isSystemSpawned: isSystemSpawned ?? isSystemAgent(agent.name),
    parentRunId,
  });

  // 准备 subagent prompt 文件（包含 subagent-only 段，但不含 HTML 注释标记）
  const promptFile = prepareAgentPrompt(agent.name, runDir);

  const paneTitle = `${config.panePrefix}${agent.name}`;
  const cmd = buildWrapperCmd(
    runId,
    agent,
    runDir,
    cwd,
    model,
    images,
    promptFile ?? undefined,
  );

  // splitPercent (0-100) → ratio (0-1)
  const ratio = splitPercent / 100;
  const paneId = topRowTargetPaneId
    ? backend.splitRight(topRowTargetPaneId, cmd, ratio)
    : backend.splitAbove(cmd, ratio);

  // 设置 pane 标题并切回主 pane
  backend.setTitle(paneId, paneTitle);
  backend.refocus(myPaneId);

  return { runId, runDir, paneId, paneTitle, agent };
}

/**
 * 并行启动多个 subagent。
 *
 * 布局（修正后）：
 *   1. 第一个 task → 在当前 pane 上方/下方垂直分割，创建顶部/底部行
 *   2. 后续 task → 在前一个 pane 右侧水平分割，填满该行
 *
 * 效果（tmux 上方布局示意；herdr 新 pane 在下方，纯界面差异）：
 *   ┌──────────┬──────────┐
 *   │  sa1     │  sa2     │   ← 上方 40% 行，水平等分
 *   ├──────────┴──────────┤
 *   │  主 agent            │   ← 当前 pane
 *   └─────────────────────┘
 */
export function launchParallel(
  tasks: Array<{ agent: AgentConfig; task: string; cwd?: string }>,
  config: SubagentConfig,
  model?: string,
  existingTopRowPaneId?: string,
  // PR-9: 整个 batch 共享的 isSystemSpawned（默认由 isSystemAgent 推断）
  isSystemSpawned?: boolean,
  // PR-10: parallel batch 的 parent run id,关联到 atelier_runs.parent_run_id
  parentRunId?: string,
): LaunchResult[] {
  // detectBackend 抛错覆盖了原 process.env.TMUX 检查
  const backend: MultiplexerBackend = detectBackend();

  cleanupOldRuns(config);
  const myPaneId = backend.currentPaneId();
  const results: LaunchResult[] = [];
  const count = tasks.length;

  for (let i = 0; i < count; i++) {
    const { agent, task, cwd } = tasks[i];
    const runId = generateRunId();
    const runDir = getRunDir(runId);
    prepareRunDir(runDir, task);
    // PR-9: 同步注册到全局 registry；isSystemSpawned 推断
    registerRun({
      runId,
      agent: agent.name,
      mode: "parallel",
      runDir,
      isSystemSpawned: isSystemSpawned ?? isSystemAgent(agent.name),
      parentRunId,
    });

    // 准备 subagent prompt 文件
    const promptFile = prepareAgentPrompt(agent.name, runDir);

    // 处理同名 agent 的 pane 标题编号
    const agentCountForName = tasks.filter(
      (t, j) => j <= i && t.agent.name === agent.name,
    ).length;
    const paneTitle =
      tasks.filter((t) => t.agent.name === agent.name).length > 1
        ? `${config.panePrefix}${agent.name}:${agentCountForName}`
        : `${config.panePrefix}${agent.name}`;

    const cmd = buildWrapperCmd(
      runId,
      agent,
      runDir,
      cwd,
      model,
      undefined,
      promptFile ?? undefined,
    );

    let paneId: string;
    if (i === 0 && !existingTopRowPaneId) {
      // 第一个且无已有顶部行：在当前 pane 上方/下方垂直分割，创建行
      // splitAbove 的 ratio 由后端决定具体占比（tmux/herdr 都用 0.4）
      paneId = backend.splitAbove(cmd, 0.4);
    } else if (i === 0 && existingTopRowPaneId) {
      // 跨 batch 续接：在已有行最右 pane 右侧水平分割
      const ratio = count / (count + 1);
      paneId = backend.splitRight(existingTopRowPaneId, cmd, ratio);
    } else {
      // 后续：在前一个 pane 右侧水平分割，自动计算等分比例
      const ratio = (count - i) / (count - i + 1);
      paneId = backend.splitRight(results[i - 1].paneId, cmd, ratio);
    }

    backend.setTitle(paneId, paneTitle);
    results.push({ runId, runDir, paneId, paneTitle, agent });
  }

  // 切回主 pane
  backend.refocus(myPaneId);
  return results;
}
