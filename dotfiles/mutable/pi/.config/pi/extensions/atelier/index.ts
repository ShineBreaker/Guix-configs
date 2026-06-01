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
import { runParallelBatches, runChain } from "./runner.ts";
import { formatResults } from "./formatting.ts";
import { SubagentParams } from "./schemas.ts";
import { appendSessionLog, finalizeSessionLog } from "./session-log.ts";

// ─── Plan Review Gate 提示词 ─────────────────────────────────────────────────
//
// 职责：拦截 plannotator_submit_plan，强制先让 oracle 审查计划。
// 审查框架由 oracle 自带（假设检验、范围风险、架构一致性、替代方案），
// 此处只需路由到 oracle，不重复定义审查维度。

const PLAN_REVIEW_GATE_PROMPT = [
  "📋 提交前需要先让 oracle 审查计划。",
  "请调用 subagent 工具：",
  '  subagent(agent: "oracle", task: "审查以下实施计划的架构合理性和风险，提出建议。计划文件：<planFilePath>")',
  "",
  "审查完成后，如果计划需要修改请修改后再提交。",
  "如果计划已通过审查，直接再次调用 plannotator_submit_plan 即可（不会再次被阻止）。",
].join("\n");

// ─── 辅助函数 ────────────────────────────────────────────────────────────────

/** 创建 makeDetails 工厂 */
const makeDetails =
  (mode: "single" | "parallel" | "chain" | "list" | "status") =>
  (results: RunResult[]): SubagentDetails => ({ mode, results });

// ─── Extension Entry ─────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  const config = loadConfig();

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
            const model = a.model ?? "default";
            return `| ${a.name} | ${a.description.slice(0, 40)}… | ${tools} | ${model} |`;
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
          "| Name | Description | Tools | Model |",
          "|------|-------------|-------|-------|",
          agentLines || "| (none) | | | |",
          "",
          "## Prompt Templates",
          "| Name | Mode | Description | Usage |",
          "|------|------|-------------|-------|",
          promptLines || "| (none) | | | |",
        ].join("\n");
        return {
          content: [{ type: "text", text: list }],
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
              content: [{ type: "text", text: `未找到 run: ${params.id}` }],
              details: makeDetails("status")([]),
            };
          }
          return {
            content: [
              { type: "text", text: JSON.stringify(statusJson, null, 2) },
            ],
            details: makeDetails("status")([]),
          };
        }

        const running = listRunning();
        if (running.length === 0) {
          return {
            content: [{ type: "text", text: "无运行中的 subagent" }],
            details: makeDetails("status")([]),
          };
        }
        const lines = running.map(
          (r) => `- **${r.runId}**: ${r.output.slice(0, 80)}...`,
        );
        return {
          content: [{ type: "text", text: lines.join("\n") }],
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
          chainEntries.push({ agent, task: t.task, cwd: params.cwd });
        }

        try {
          const results = await runChain(
            chainEntries,
            config,
            effectiveCwd,
            params.task,
            params.model,
            params.thinking,
            signal,
          );
          appendSessionLog("chain", results);
          return {
            content: [{ type: "text", text: formatResults(results) }],
            details: makeDetails("chain")(results),
            isError: results.some((r) => r.status === "failed") || undefined,
          };
        } catch (err) {
          return {
            content: [
              { type: "text", text: `启动失败: ${(err as Error).message}` },
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
          taskEntries.push({ agent, task: t.task, cwd: params.cwd });
        }

        try {
          const results = await runParallelBatches(
            taskEntries,
            config,
            effectiveCwd,
            params.model,
            params.thinking,
            signal,
          );
          appendSessionLog("parallel", results);
          return {
            content: [{ type: "text", text: formatResults(results) }],
            details: makeDetails("parallel")(results),
            isError: results.some((r) => r.status === "failed") || undefined,
          };
        } catch (err) {
          return {
            content: [
              { type: "text", text: `启动失败: ${(err as Error).message}` },
            ],
            details: makeDetails("parallel")([]),
            isError: true,
          };
        }
      }

      // ── single 模式 ─────────────────────────────────────────────────

      if (params.agent && params.task) {
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
          const launch = launchSingle(
            agent,
            params.task,
            config,
            params.cwd,
            params.model,
            params.thinking,
            undefined,
            50,
            params.images,
          );
          const result = await waitForCompletion(launch, config, signal);
          if (result.status === "completed") {
            ensureWorkfile(result, effectiveCwd, startedAt);
          }
          appendSessionLog("single", [result]);
          return {
            content: [{ type: "text", text: result.output }],
            details: makeDetails("single")([result]),
            isError: result.status === "failed" || undefined,
          };
        } catch (err) {
          return {
            content: [
              { type: "text", text: `启动失败: ${(err as Error).message}` },
            ],
            details: makeDetails("single")([]),
            isError: true,
          };
        }
      }

      const available = agents.map((a) => a.name).join(", ") || "none";
      return {
        content: [{ type: "text", text: `参数无效。可用 agent: ${available}` }],
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
          const launch = launchSingle(
            agent,
            task,
            config,
            ctx.cwd,
            agent.model,
            agent.thinking,
          );
          ctx.ui.notify(
            `⏳ ${agent.name} 已启动 (run: ${launch.runId})...`,
            "info",
          );
          const result = await waitForCompletion(launch, config);
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
              return { agent, task: e.task };
            });
            results = await runChain(chainEntries, config, ctx.cwd, paramValue);
          } else if (prompt.mode === "parallel") {
            const taskEntries = resolvedEntries.map((e) => {
              const agent = agents.find((a) => a.name === e.agent);
              if (!agent) throw new Error(`未知 agent: ${e.agent}`);
              return { agent, task: e.task };
            });
            results = await runParallelBatches(taskEntries, config, ctx.cwd);
          } else {
            const e = resolvedEntries[0];
            const agent = agents.find((a) => a.name === e.agent);
            if (!agent) throw new Error(`未知 agent: ${e.agent}`);
            const launch = launchSingle(agent, e.task, config, ctx.cwd);
            const result = await waitForCompletion(launch, config);
            results = [result];
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

  // ── /run-plan 命令：清空上下文，在新会话中执行已审查的计划 ─────────
  //
  // 流程：
  //   1. 读取 .agents/current-plan.md
  //   2. 立即归档到 .agents/archive/plan-<timestamp>.md（防反复触发）
  //   3. newSession() 创建清空上下文的新会话
  //   4. 将计划内容作为用户消息注入新会话

  pi.registerCommand("run-plan", {
    description: "清空当前上下文，在新会话中执行已通过审查的计划",
    handler: async (_args, ctx) => {
      const planPath = path.join(ctx.cwd, ".agents", "current-plan.md");

      // 检查计划文件是否存在
      if (!fs.existsSync(planPath)) {
        ctx.ui.notify(
          "❌ 未找到已审查的计划。\n" +
            "请先用 plannotator 生成计划并让 oracle 审查通过。",
          "error",
        );
        return;
      }

      // 读取计划内容
      let planContent: string;
      try {
        planContent = fs.readFileSync(planPath, "utf-8");
      } catch (err) {
        ctx.ui.notify(`❌ 读取计划失败: ${(err as Error).message}`, "error");
        return;
      }

      // 立即归档（防反复触发）
      const archiveDir = path.join(ctx.cwd, ".agents", "archive");
      fs.mkdirSync(archiveDir, { recursive: true });
      const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
      const archivePath = path.join(archiveDir, `plan-${timestamp}.md`);
      try {
        fs.renameSync(planPath, archivePath);
      } catch (err) {
        ctx.ui.notify(`❌ 归档计划失败: ${(err as Error).message}`, "error");
        return;
      }

      ctx.ui.notify(
        `📋 计划已归档到 ${archivePath}\n🔄 正在创建新会话...`,
        "info",
      );

      // 构建注入新会话的指令
      const executionPrompt = [
        "请按照以下已审查的实施计划开始执行。",
        "",
        "执行要求：",
        "1. 严格按计划步骤执行，不要跳过或重新评估已完成审查的决策",
        "2. 每完成一个步骤，简要标注进度",
        "3. 遇到阻塞（无法绕过的错误）立即上报，不要自行扩大范围",
        "4. 完成后调用 reviewer 审查实施结果",
        "",
        "---",
        "# 实施计划",
        "",
        planContent,
      ].join("\n");

      // 创建新会话并注入计划
      try {
        const result = await ctx.newSession({
          parentSession: ctx.sessionManager?.currentPath,
          setup: async (sessionManager) => {
            // 新会话创建后的设置回调
          },
          withSession: async (newCtx) => {
            // 向新会话注入计划作为初始用户消息
            newCtx.sendUserMessage(executionPrompt);
          },
        });

        if (result.cancelled) {
          ctx.ui.notify("⚠️ 用户取消了新会话创建", "warn");
        }
      } catch (err) {
        ctx.ui.notify(`❌ 创建新会话失败: ${(err as Error).message}`, "error");
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
      fs.mkdirSync(tmpDir, { recursive: true });
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
          fs.mkdirSync(planDir, { recursive: true });
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
    });
  }
}
