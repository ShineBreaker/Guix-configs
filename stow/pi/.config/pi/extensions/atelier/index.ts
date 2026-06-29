// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * atelier 扩展入口
 *
 * 通过 tmux 分屏可视化执行 subagent 任务。
 *
 * 模式：
 *   - single: { agent: "name", task: "..." }
 *   - parallel: { tasks: [{ agent: "name", task: "..." }, ...] }
 *   - chain: { chain: [{ agent: "name", task: "..." }, ...] }
 *   - list: { action: "list" }
 *   - status: { action: "status" [, id: "run-id"] }
 *
 * 快捷命令：
 *   - /agentname <task>     — 启动单个 agent
 *   - /<prompt-name> <param> — 按 prompt 模板启动链路
 *
 * 文件拆分：
 *   types.ts       — 接口和常量
 *   config.ts      — 配置加载
 *   discovery.ts   — Agent 和 Prompt 发现
 *   workfile.ts    — Workfile 持久化
 *   launcher.ts    — Tmux 分屏启动
 *   monitor.ts     — 运行监控
 *   runner.ts      — 执行编排
 *   formatting.ts  — 结果格式化
 *   schemas.ts     — 参数 Schema
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { execFileSync } from "node:child_process";
import { getAgentDir } from "@earendil-works/pi-coding-agent";
import type {
  AgentToolResult,
  ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import type { AgentConfig, RunResult, SubagentDetails } from "./types.ts";
import { loadConfig } from "./config.ts";
import { discoverAgents, discoverPrompts } from "./discovery.ts";
import { ensureWorkfile } from "./workfile.ts";
import { getRunDir, launchSingle } from "./launcher.ts";
import { waitForCompletion, listRunning } from "./monitor.ts";
import {
  executeWithFallback,
  runParallelBatches,
  runChain,
  resolveModelChain,
  readDefaultModelFromSettings,
} from "./runner.ts";
import { formatResults } from "./formatting.ts";
import { SubagentParams } from "./schemas.ts";
import { appendSessionLog, finalizeSessionLog } from "./session-log.ts";
import { stripSubagentOnlySection } from "./context.ts";
import { rebuildFromStatusFiles, closeRegistry } from "./registry.ts";
import { orphanRecovery } from "./orphan-recovery.ts";
import { startStuckDetector } from "./stuck-detector.ts";

// ─── Plan Review Gate 提示词 ─────────────────────────────────────────────────
//
// 职责：拦截 plannotator_submit_plan，强制先让 oracle 审查计划。
// 审查框架由 oracle 自带（假设检验、范围风险、架构一致性、替代方案），
// 此处只需路由到 oracle，不重复定义审查维度。

const PLAN_REVIEW_GATE_PROMPT = [
  "任务提交前需要先让 oracle 审查计划。",
  "请调用 subagent 工具：",
  'subagent(agent: "oracle", task: "审查以下实施计划的架构合理性和风险，提出建议。计划文件：<planFilePath>")',
  "",
  "审查完成后，如果计划需要修改请修改后再提交。",
  "如果计划已通过审查，直接再次调用 plannotator_submit_plan 即可（不会再次被阻止）。",
].join("\n");

// ─── Worker single 模式硬警告 ────────────────────────────────────────────────
//
// 设计：worker 是为并发执行设计的 subagent。LLM 在 single 模式调用 worker 时
// （即 `subagent({ agent: "worker", task: "..." })`）会触发硬警告（isError）。
// 30 秒内 LLM 重试相同的调用视为紧急 override（例如上下文窗口即将满），
// 放行执行。
//
// 为什么用进程级时间戳而不是 set 记忆：每次 tool call 之后 LLM 会读取错误信息
// 重新决策，30s 窗口足够覆盖"LLM 看到错误 → 修改策略 → 再调用一次"的往返。

/** worker single 模式 override 的 grace window（毫秒） */
const WORKER_OVERRIDE_GRACE_MS = 30_000;

/** 进程级：worker single 最近一次警告时间戳 */
let lastWorkerSingleWarnAt = 0;

/**
 * 判断当前 single+worker 调用应警告还是放行。
 *
 * @returns "warn" 触发硬警告；"allow" 视为 override 放行
 */
function checkWorkerSingleOverride(): "warn" | "allow" {
  if (Date.now() - lastWorkerSingleWarnAt > WORKER_OVERRIDE_GRACE_MS) {
    lastWorkerSingleWarnAt = Date.now();
    return "warn";
  }
  return "allow";
}

/** 构造 worker single 硬警告的错误响应 */
function workerSingleWarnResponse(): AgentToolResult<SubagentDetails> {
  return {
    content: [
      {
        type: "text",
        text: [
          "❌ worker 是为并发执行设计的 subagent，不允许 single 模式调用。",
          "",
          "请改用 `tasks` 数组（即使只放 1 个任务也合法）：",
          '  subagent({ tasks: [{ agent: "worker", task: "..." }] })',
          "",
          "或者把工作拆成 N 个独立子任务，让 N 个 worker 并行：",
          "  subagent({ tasks: [",
          '    { agent: "worker", task: "子任务 A" },',
          '    { agent: "worker", task: "子任务 B" },',
          "  ] })",
          "",
          `紧急 override：若确实需要 single worker（例如剩余的上下文窗口不够使用）`,
          `${WORKER_OVERRIDE_GRACE_MS / 1000}s 内再调用一次相同的请求将放行执行。`,
        ].join("\n"),
      },
    ],
    details: makeDetails("single")([]),
    isError: true,
  };
}

// ─── 辅助函数 ────────────────────────────────────────────────────────────────

/** 创建 makeDetails 工厂 */
const makeDetails =
  (mode: "single" | "parallel" | "chain" | "list" | "status") =>
  (results: RunResult[]): SubagentDetails => ({
    mode,
    results,
  });

// ─── Extension Entry ─────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  const config = loadConfig();

  // ── Atelier Registry：启动 rebuild + orphan recovery + stuck detector ─────
  //
  // 三步全部 best-effort，任何一步失败不阻塞 atelier 扩展加载。
  // status.json 仍是 single source of truth；registry 仅是查询视图。
  // 设计细节见 registry.ts / orphan-recovery.ts / stuck-detector.ts。
  const registryInit = (() => {
    try {
      const rebuildReport = rebuildFromStatusFiles();
      const recoveryReport = orphanRecovery();
      return { ok: true as const, rebuildReport, recoveryReport };
    } catch (err) {
      console.warn(
        "[atelier:registry] init failed, continuing without index:",
        err,
      );
      return { ok: false as const, error: err };
    }
  })();

  if (registryInit.ok && registryInit.rebuildReport.indexed > 0) {
    console.log(
      `[atelier:registry] indexed ${registryInit.rebuildReport.indexed} runs from status.json`,
    );
  }

  // 后台 stuck detector fiber（unref，不阻塞进程退出）
  const stuckDetector = registryInit.ok ? startStuckDetector() : null;

  // ── 注册 subagent 工具 ──────────────────────────────────────────────────

  pi.registerTool({
    name: "subagent",
    label: "Subagent",
    description: [
      "通过 tmux 分屏可视化执行 subagent 任务。",
      "模式：single (agent + task)、parallel (tasks 数组)、chain (chain 数组)。",
      "管理：action: list 列出可用 agent 和 prompt 模板，action: status 查看运行状态。",
    ].join(" "),
    parameters: SubagentParams,

    async execute(
      _toolCallId,
      params,
      signal,
      _onUpdate,
      _ctx,
    ): Promise<AgentToolResult<SubagentDetails>> {
      const agents = discoverAgents();
      const prompts = discoverPrompts();
      const effectiveCwd = params.cwd ?? process.cwd();

      // ── action: list ─────────────────────────────────────────────────

      if (params.action === "list") {
        const agentLines = agents
          .map((a) => {
            const tools = a.tools ? a.tools.join(", ") : "all";
            const tier = a.tier ?? config.defaultTier;
            const tierCfg = config.tiers[tier];
            const model =
              tier === "inherit"
                ? (readDefaultModelFromSettings()[0] ?? "(inherit)")
                : tierCfg
                  ? tierCfg.model
                  : "(unknown tier)";
            return `| ${a.name} | ${tier} | ${model} | ${a.description.slice(0, 40)}… | ${tools} |`;
          })
          .join("\n");
        const promptLines = prompts
          .map(
            (p) =>
              `| ${p.name} | ${p.mode} | ${p.description.slice(0, 40)}… | /${p.name} <${p.param}> |`,
          )
          .join("\n");
        const list = [
          "## Agents",
          "| Name | Tier | Model | Description | Tools |",
          "|------|------|-------|-------------|-------|",
          agentLines || "| (none) | | | | |",
          "",
          "## Prompt Templates",
          "| Name | Mode | Description | Usage |",
          "|------|------|-------------|-------|",
          promptLines || "| (none) | | | |",
        ].join("\n");
        return {
          content: [
            {
              type: "text",
              text: list,
            },
          ],
          details: makeDetails("list")([]),
        };
      }

      // ── action: status ───────────────────────────────────────────────

      if (params.action === "status") {
        if (params.id) {
          const runDir = getRunDir(params.id);
          let statusJson: Record<string, unknown>;
          try {
            statusJson = JSON.parse(
              fs.readFileSync(path.join(runDir, "status.json"), "utf-8"),
            );
          } catch {
            return {
              content: [
                {
                  type: "text",
                  text: `未找到 run: ${params.id}`,
                },
              ],
              details: makeDetails("status")([]),
            };
          }
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify(statusJson, null, 2),
              },
            ],
            details: makeDetails("status")([]),
          };
        }

        const running = listRunning();
        if (running.length === 0) {
          return {
            content: [
              {
                type: "text",
                text: "无运行中的 subagent",
              },
            ],
            details: makeDetails("status")([]),
          };
        }
        const lines = running.map(
          (r) => `- **${r.runId}**: ${r.output.slice(0, 80)}...`,
        );
        return {
          content: [
            {
              type: "text",
              text: lines.join("\n"),
            },
          ],
          details: makeDetails("status")(running),
        };
      }

      // ── chain 模式 ──────────────────────────────────────────────────

      if (params.chain && params.chain.length > 0) {
        if (params.chain.length > config.maxTasks) {
          return {
            content: [
              {
                type: "text",
                text: `chain 任务数 ${params.chain.length} 超过上限 ${config.maxTasks}`,
              },
            ],
            details: makeDetails("chain")([]),
            isError: true,
          };
        }

        const chainEntries: Array<{
          agent: AgentConfig;
          task: string;
          cwd?: string;
        }> = [];
        for (const t of params.chain) {
          const agent = agents.find((a) => a.name === t.agent);
          if (!agent) {
            const available = agents.map((a) => a.name).join(", ") || "none";
            return {
              content: [
                {
                  type: "text",
                  text: `未知 agent: "${t.agent}"。可用: ${available}`,
                },
              ],
              details: makeDetails("chain")([]),
            };
          }
          chainEntries.push({
            agent,
            task: t.task,
            cwd: params.cwd,
          });
        }

        try {
          const results = await runChain(
            chainEntries,
            config,
            effectiveCwd,
            params.task,
            params.model,
            signal,
          );
          appendSessionLog("chain", results);
          return {
            content: [
              {
                type: "text",
                text: formatResults(results),
              },
            ],
            details: makeDetails("chain")(results),
            isError: results.some((r) => r.status === "failed") || undefined,
          };
        } catch (err) {
          return {
            content: [
              {
                type: "text",
                text: `启动失败: ${(err as Error).message}`,
              },
            ],
            details: makeDetails("chain")([]),
            isError: true,
          };
        }
      }

      // ── parallel 模式 ───────────────────────────────────────────────

      if (params.tasks && params.tasks.length > 0) {
        if (params.tasks.length > config.maxTasks) {
          return {
            content: [
              {
                type: "text",
                text: `parallel 任务数 ${params.tasks.length} 超过上限 ${config.maxTasks}`,
              },
            ],
            details: makeDetails("parallel")([]),
            isError: true,
          };
        }

        const taskEntries: Array<{
          agent: AgentConfig;
          task: string;
          cwd?: string;
        }> = [];
        for (const t of params.tasks) {
          const agent = agents.find((a) => a.name === t.agent);
          if (!agent) {
            const available = agents.map((a) => a.name).join(", ") || "none";
            return {
              content: [
                {
                  type: "text",
                  text: `未知 agent: "${t.agent}"。可用: ${available}`,
                },
              ],
              details: makeDetails("parallel")([]),
            };
          }
          taskEntries.push({
            agent,
            task: t.task,
            cwd: params.cwd,
          });
        }

        try {
          const results = await runParallelBatches(
            taskEntries,
            config,
            effectiveCwd,
            params.model,
            signal,
          );
          appendSessionLog("parallel", results);
          return {
            content: [
              {
                type: "text",
                text: formatResults(results),
              },
            ],
            details: makeDetails("parallel")(results),
            isError: results.some((r) => r.status === "failed") || undefined,
          };
        } catch (err) {
          return {
            content: [
              {
                type: "text",
                text: `启动失败: ${(err as Error).message}`,
              },
            ],
            details: makeDetails("parallel")([]),
            isError: true,
          };
        }
      }

      // ── single 模式 ─────────────────────────────────────────────────

      if (params.agent && params.task) {
        // worker single 模式硬警告 + 30s override grace
        if (params.agent === "worker") {
          const verdict = checkWorkerSingleOverride();
          if (verdict === "warn") {
            return workerSingleWarnResponse();
          }
        }

        const agent = agents.find((a) => a.name === params.agent);
        if (!agent) {
          const available = agents.map((a) => a.name).join(", ") || "none";
          return {
            content: [
              {
                type: "text",
                text: `未知 agent: "${params.agent}"。可用: ${available}`,
              },
            ],
            details: makeDetails("single")([]),
          };
        }

        try {
          const startedAt = Date.now();
          const result = await executeWithFallback(
            agent,
            params.task,
            config,
            params.cwd ?? process.cwd(),
            params.model,
            signal,
            undefined,
            50,
            params.images,
          );

          if (result.status === "completed") {
            ensureWorkfile(result, effectiveCwd, startedAt);
          }
          appendSessionLog("single", [result]);
          return {
            content: [
              {
                type: "text",
                text: result.output,
              },
            ],
            details: makeDetails("single")([result]),
            isError: result.status === "failed" || undefined,
          };
        } catch (err) {
          return {
            content: [
              {
                type: "text",
                text: `启动失败: ${(err as Error).message}`,
              },
            ],
            details: makeDetails("single")([]),
            isError: true,
          };
        }
      }

      const available = agents.map((a) => a.name).join(", ") || "none";
      return {
        content: [
          {
            type: "text",
            text: `参数无效。可用 agent: ${available}`,
          },
        ],
        details: makeDetails("single")([]),
      };
    },
  });

  // ── 为每个 agent 注册 /agentname 快捷命令 ──────────────────────────────

  const agents = discoverAgents();
  for (const agent of agents) {
    pi.registerCommand(agent.name, {
      description: `${agent.description}（/${agent.name} <任务描述>）`,
      handler: async (args, ctx) => {
        const task = args.trim();
        if (!task) {
          ctx.ui.notify(
            `用法: /${agent.name} <任务描述>\n例: /${agent.name} 审查当前修改的代码`,
            "warn",
          );
          return;
        }

        try {
          const startedAt = Date.now();
          // 解析 model 链：显式覆盖 > tier > defaultTier > inherit
          const modelChain = resolveModelChain(agent, config);
          const initialModel = modelChain[0];
          const modelLabel = initialModel
            ? `(model: ${initialModel})`
            : `(model: inherit)`;
          // 先用首选模型启动，通知用户
          const launch = launchSingle(
            agent,
            task,
            config,
            ctx.cwd,
            initialModel,
          );
          ctx.ui.notify(
            `⏳ ${agent.name} 已启动 (run: ${launch.runId})... ${modelLabel}`,
            "info",
          );
          let result = await waitForCompletion(launch, config);

          // Fallback：如果失败且 tier 配置了 fallback，自动重试
          if (
            result.status === "failed" &&
            modelChain.length > 1 &&
            result.error !== "Aborted" &&
            result.error !== "timeout"
          ) {
            for (const fallbackModel of modelChain.slice(1, 3)) {
              ctx.ui.notify(
                `🔄 ${agent.name} 首选模型失败，尝试 fallback: ${fallbackModel}`,
                "warn",
              );
              const fallbackLaunch = launchSingle(
                agent,
                task,
                config,
                ctx.cwd,
                fallbackModel,
              );
              result = await waitForCompletion(fallbackLaunch, config);
              if (result.status === "completed") break;
              if (result.error === "Aborted" || result.error === "timeout")
                break;
            }
          }

          if (result.status === "completed") {
            ensureWorkfile(result, ctx.cwd, startedAt);
            const workfileNote = result.workfilePath
              ? `\n📄 ${result.workfilePath}`
              : "";
            ctx.ui.notify(
              `✅ ${agent.name} 完成 (${(result.durationMs / 1000).toFixed(1)}s)${workfileNote}\n\n${result.output.slice(0, 4000)}${result.output.length > 4000 ? "\n...（截断）" : ""}`,
              "info",
            );
          } else {
            ctx.ui.notify(
              `❌ ${agent.name} 失败 (run: ${launch.runId}): ${result.error ?? "未知错误"}`,
              "error",
            );
          }
        } catch (err) {
          ctx.ui.notify(
            `启动 ${agent.name} 失败: ${(err as Error).message}`,
            "error",
          );
        }
      },
    });
  }

  // ── 为每个 prompt 模板注册快捷命令 ─────────────────────────────────────

  const prompts = discoverPrompts();
  const agentNames = new Set(agents.map((a) => a.name));
  for (const prompt of prompts) {
    if (agentNames.has(prompt.name)) continue; // 与 agent 命令冲突，跳过
    pi.registerCommand(prompt.name, {
      description: `${prompt.description}（/${prompt.name} <${prompt.param}>）`,
      handler: async (args, ctx) => {
        const paramValue = args.trim();
        if (!paramValue) {
          ctx.ui.notify(
            `用法: /${prompt.name} <${prompt.param}>\n例: /${prompt.name} 重构认证模块`,
            "warn",
          );
          return;
        }

        // 替换模板中的占位符
        const resolvedEntries = prompt.entries.map((e) => ({
          agent: e.agent,
          task: e.task.replaceAll(`{${prompt.param}}`, paramValue),
        }));

        try {
          let results: RunResult[];

          if (prompt.mode === "chain") {
            const chainEntries = resolvedEntries.map((e) => {
              const agent = agents.find((a) => a.name === e.agent);
              if (!agent) throw new Error(`未知 agent: ${e.agent}`);
              return {
                agent,
                task: e.task,
              };
            });
            results = await runChain(chainEntries, config, ctx.cwd, paramValue);
          } else if (prompt.mode === "parallel") {
            const taskEntries = resolvedEntries.map((e) => {
              const agent = agents.find((a) => a.name === e.agent);
              if (!agent) throw new Error(`未知 agent: ${e.agent}`);
              return {
                agent,
                task: e.task,
              };
            });
            results = await runParallelBatches(taskEntries, config, ctx.cwd);
          } else {
            const e = resolvedEntries[0];
            const agentCfg = agents.find((a) => a.name === e.agent);
            if (!agentCfg) throw new Error(`未知 agent: ${e.agent}`);
            // 单一 prompt 模式也使用 fallback
            const singleResult = await executeWithFallback(
              agentCfg,
              e.task,
              config,
              ctx.cwd,
              undefined,
              undefined,
            );
            results = [singleResult];
          }

          const success = results.filter(
            (r) => r.status === "completed",
          ).length;
          ctx.ui.notify(
            `${prompt.name}: ${success}/${results.length} 成功\n\n${formatResults(results).slice(0, 4000)}`,
            success === results.length ? "info" : "warn",
          );
        } catch (err) {
          ctx.ui.notify(
            `启动 ${prompt.name} 失败: ${(err as Error).message}`,
            "error",
          );
        }
      },
    });
  }

  // ── /run-plan 命令：loop 框架薄包装 ────────────────────────────────
  // 读 .agents/current-plan.md → 归档 → loopctl start → step

  pi.registerCommand("run-plan", {
    description: "清空当前上下文，在新会话中执行已通过审查的计划",
    handler: async (_args, ctx) => {
      const planPath = path.join(ctx.cwd, ".agents", "current-plan.md");
      const loopctlBin = "loopctl";

      if (!fs.existsSync(planPath)) {
        ctx.ui.notify(
          "❌ 未找到已审查的计划。\n" +
            "请先用 plannotator 生成计划并让 oracle 审查通过。",
          "error",
        );
        return;
      }

      try {
        execFileSync("which", [loopctlBin], {
          encoding: "utf-8",
        });
      } catch {
        ctx.ui.notify(
          "❌ loopctl 未找到。请确认 ~/.local/bin/loopctl 存在且在 PATH 中。",
          "error",
        );
        return;
      }

      // 读取 + 归档
      let planContent: string;
      try {
        planContent = fs.readFileSync(planPath, "utf-8");
      } catch (err) {
        ctx.ui.notify(`❌ 读取计划失败: ${(err as Error).message}`, "error");
        return;
      }

      const archiveDir = path.join(ctx.cwd, ".agents", "archive");
      fs.mkdirSync(archiveDir, {
        recursive: true,
      });
      const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
      const archivePath = path.join(archiveDir, `plan-${timestamp}.md`);
      try {
        fs.renameSync(planPath, archivePath);
      } catch (err) {
        ctx.ui.notify(`❌ 归档计划失败: ${(err as Error).message}`, "error");
        return;
      }

      // loopctl 启动 + 第一轮
      const loopName = `plan-${timestamp}`;
      try {
        execFileSync(
          loopctlBin,
          [loopName, "start", "--task-file", archivePath, "--adapter", "pi"],
          {
            cwd: ctx.cwd,
            encoding: "utf-8",
          },
        );
        ctx.ui.notify(
          `📋 计划已作为 loop "${loopName}" 启动，正在执行第一轮...`,
          "info",
        );
        execFileSync(loopctlBin, [loopName, "step"], {
          cwd: ctx.cwd,
          encoding: "utf-8",
          timeout: 600_000,
          maxBuffer: 10 * 1024 * 1024,
        });
        ctx.ui.notify(`✅ Loop "${loopName}" 第一轮完成`, "info");
      } catch (err: any) {
        const output = (err.stdout || err.stderr || err.message) as string;
        ctx.ui.notify(`❌ loopctl 错误: ${output.slice(0, 500)}`, "error");
      }
    },
  });

  // ── /loop 命令：loopctl 前端薄包装 ──────────────────────────────────

  pi.registerCommand("loop", {
    description: "loopctl 前端：管理跨 agent 长期迭代循环",
    handler: async (args, ctx) => {
      const loopctlBin = "loopctl";

      try {
        execFileSync("which", [loopctlBin], {
          encoding: "utf-8",
        });
      } catch {
        ctx.ui.notify(
          "❌ loopctl 未找到。请确认 ~/.local/bin/loopctl 存在且在 PATH 中。",
          "error",
        );
        return;
      }

      const trimmed = args.trim();
      const cmdArgs: string[] = trimmed
        ? trimmed.split(/\s+/)
        : ["list", "--all"];

      try {
        const result = execFileSync(loopctlBin, cmdArgs, {
          cwd: ctx.cwd,
          encoding: "utf-8",
          timeout: 600_000,
          maxBuffer: 10 * 1024 * 1024,
        });
        ctx.ui.notify(result.trim() || "(无输出)", "info");
      } catch (err: any) {
        const output = (err.stdout || err.stderr || err.message) as string;
        ctx.ui.notify(`❌ loopctl 错误: ${output.slice(0, 500)}`, "error");
      }
    },
  });

  // ── Visual agent 自动移交 ────────────────────────────────────────────
  // 当用户输入包含图片但当前模型不支持视觉时，保存图片到临时文件
  // 并注入系统提示指示 LLM 调用 visual subagent
  {
    pi.on("before_agent_start", (event, ctx) => {
      const images = event.images;
      if (!images || images.length === 0) return;

      // 防止 subagent 递归：wrapper 会导出 PI_SUBAGENT=1
      if (process.env.PI_SUBAGENT) return;

      // 检查当前模型是否支持视觉（通过 Model.input 字段）
      const currentModel = ctx.model;
      if (currentModel?.input?.includes("image")) return; // 当前模型支持视觉，无需移交

      // 保存图片到临时文件
      const tmpDir = path.join(os.tmpdir(), "pi-visual");
      fs.mkdirSync(tmpDir, {
        recursive: true,
      });
      const savedPaths: string[] = [];

      for (let i = 0; i < images.length; i++) {
        const img = images[i];
        // ImageContent: { type: "image", data: string (base64), mimeType: string }
        if (!img.data) continue;

        const ext = (() => {
          const mime = img.mimeType?.toLowerCase() ?? "image/png";
          if (mime.includes("jpeg") || mime.includes("jpg")) return ".jpg";
          if (mime.includes("gif")) return ".gif";
          if (mime.includes("webp")) return ".webp";
          if (mime.includes("bmp")) return ".bmp";
          if (mime.includes("svg")) return ".svg";
          return ".png";
        })();

        const tmpFile = path.join(tmpDir, `img-${Date.now()}-${i}${ext}`);
        fs.writeFileSync(tmpFile, Buffer.from(img.data, "base64"));
        savedPaths.push(tmpFile);
      }

      if (savedPaths.length === 0) return;

      // 注入系统提示，指示 LLM 调用 visual subagent
      const imageList = savedPaths.map((p) => `  - ${p}`).join("\n");
      const visionHint = [
        "",
        "🖼️ **检测到图片输入，但当前模型不支持视觉。**",
        "请使用 visual subagent 分析以下图片：",
        "",
        `subagent(agent: "visual", task: "分析以下图片", images: [${savedPaths.map((p) => `"${p}"`).join(", ")}])`,
        "",
        `图片文件：\n${imageList}`,
        "",
      ].join("\n");

      // 追加到系统提示
      return {
        systemPrompt: event.systemPrompt + "\n" + visionHint,
      };
    });
  }

  // ── Worker / Planner 上下文注入 ─────────────────────────────────────────
  //
  // 流程：
  //   1. 检测 plan mode 是否激活（双保险：session entries + systemPrompt 标记）
  //   2. 按模式读取 agents/{worker,planner}.md 的 body
  //   3. 剥离 subagent-only 段（主会话不需要看 workfile 路径、详细输出模板等）
  //   4. 追加到 systemPrompt
  //   5. plan mode 下额外追加优先级提示（plannotator 的 [PLANNOTATOR - PLANNING PHASE] 优先级最高）
  //
  // 检测失败（plannotator 未安装）→ 默认走 worker 上下文，不报错。

  {
    const PLANNOTATOR_MARKER = "[PLANNOTATOR - PLANNING PHASE]";

    /**
     * 检测 plan mode 是否激活。
     * 主路径：读 session entries 找 plannotator 写的 custom 条目
     * 兜底：扫描 systemPrompt 是否含 plannotator 标记
     */
    function isPlanModeActive(
      ctx: {
        sessionManager: {
          getEntries(): ReadonlyArray<{
            type: string;
            customType?: string;
            data?: {
              phase?: string;
            };
          }>;
        };
      },
      systemPrompt: string,
    ): boolean {
      // 主路径：session entries（取最近的 plannotator 条目）
      try {
        const entries = ctx.sessionManager.getEntries();
        for (let i = entries.length - 1; i >= 0; i--) {
          const e = entries[i];
          if (e.type === "custom" && e.customType === "plannotator") {
            return e.data?.phase === "planning";
          }
        }
      } catch {
        // 静默走兜底
      }
      // 兜底：systemPrompt 标记
      return systemPrompt.includes(PLANNOTATOR_MARKER);
    }

    /**
     * 读取 agent .md 的 body，剥离 subagent-only 段。
     * 文件不存在或读取失败返回 null。
     */
    function loadMainSessionAgentContext(agentName: string): string | null {
      const agentPath = path.join(getAgentDir(), "agents", `${agentName}.md`);
      try {
        const content = fs.readFileSync(agentPath, "utf-8");
        return stripSubagentOnlySection(content);
      } catch {
        return null;
      }
    }

    pi.on("before_agent_start", (event, ctx) => {
      // 防止 subagent 递归
      if (process.env.PI_SUBAGENT) return;

      const planMode = isPlanModeActive(ctx, event.systemPrompt);
      const agentName = planMode ? "planner" : "worker";
      const contextContent = loadMainSessionAgentContext(agentName);
      if (!contextContent) return; // 静默失败（agent .md 缺失），不加注入

      // plan mode 下追加优先级提示：plannotator 的 plan 约束优先于本上下文
      const priorityHint = planMode
        ? "\n\n# 优先级提示：plan mode 下，plannotator 注入的 [PLANNOTATOR - PLANNING PHASE] 段中的所有约束优先级最高，与本文冲突时遵循 plannotator。\n"
        : "";

      return {
        systemPrompt:
          event.systemPrompt + priorityHint + "\n\n" + contextContent,
      };
    });
  }

  // ── Plan review gate ──────────────────────────────────────────────────
  //
  // 流程：
  //   1. 首次 plannotator_submit_plan → block，提示调 oracle 审查
  //   2. oracle 审完后 LLM 再次调 plannotator_submit_plan → 放行
  //   3. 放行时自动保存计划到 .agents/current-plan.md
  //   4. 提示 LLM 通知用户执行 /run-plan（清空上下文，在新会话中执行计划）

  {
    const reviewedPlans = new Set<string>();
    const approvedPlanPath = path.join(
      process.cwd(),
      ".agents",
      "current-plan.md",
    );

    pi.on("tool_call", async (event, _ctx) => {
      if (event.toolName !== "plannotator_submit_plan") return;
      const planFilePath = event.input?.filePath as string | undefined;
      if (!planFilePath) return;

      // 第二次调用（oracle 已审查）→ 放行并保存计划
      if (reviewedPlans.has(planFilePath)) {
        reviewedPlans.delete(planFilePath);

        // 读取计划文件内容并保存到约定路径
        try {
          const planContent = fs.readFileSync(planFilePath, "utf-8");
          const planDir = path.dirname(approvedPlanPath);
          fs.mkdirSync(planDir, {
            recursive: true,
          });
          fs.writeFileSync(approvedPlanPath, planContent, "utf-8");
        } catch {
          // 保存失败不阻塞，/run-plan 会报错提示
        }

        return {
          systemPrompt:
            "✅ 计划已通过 oracle 审查并保存。" +
            "请通知用户：执行 `/run-plan` 开始实施（将清空当前上下文，在新会话中执行计划）。" +
            "如果用户不想清空上下文，也可以直接按计划执行。",
        };
      }

      // 首次调用 → block，提示调 oracle 审查
      reviewedPlans.add(planFilePath);
      return {
        block: true,
        reason: PLAN_REVIEW_GATE_PROMPT + planFilePath,
      };
    });
    pi.on("session_shutdown", () => {
      reviewedPlans.clear();
      finalizeSessionLog(process.cwd());
      // 停止 stuck detector，清除 interval handler
      stuckDetector?.stop();
      // flush WAL，关闭 SQLite 连接
      closeRegistry();
    });
  }
}
