// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { getAgentDir, parseFrontmatter } from "@earendil-works/pi-coding-agent";
import type {
  AgentToolResult,
  ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

// ─── types ────────────────────────────────────────────────────────────────────

interface AgentConfig {
  name: string;
  description: string;
  tools?: string[];
  tier?: string;
  systemPrompt: string;
  filePath: string;
}

interface AgentModelConfig {
  model: string;
  fallback: string[];
}

interface PromptConfig {
  name: string;
  mode: "single" | "parallel" | "chain";
  param: string;
  description: string;
  entries: Array<{ agent: string; task: string }>;
}

interface SubagentConfig {
  pollIntervalMs: number;
  panePrefix: string;
  keepResults: number;
  timeoutMs: number;
  maxTasks: number;
  maxConcurrency: number;
  defaultTier: string;
  tiers: Record<string, AgentModelConfig>;
}

interface LaunchResult {
  runId: string;
  runDir: string;
  paneId: string;
  paneTitle: string;
  agent: AgentConfig;
}

interface RunResult {
  runId: string;
  agent: string;
  status: "completed" | "failed" | "running";
  exitCode: number;
  output: string;
  durationMs: number;
  tmuxPane: string;
  error?: string;
  workfilePath?: string;
}

interface SubagentDetails {
  mode: "single" | "parallel" | "chain" | "list" | "status";
  results: RunResult[];
}

interface StatusFile {
  status: "running" | "completed" | "failed";
  exitCode?: number;
  finishedAt?: number;
  startedAt?: number;
  error?: string;
}

const DEFAULT_CONFIG: SubagentConfig = {
  pollIntervalMs: 2000,
  panePrefix: "sub:",
  keepResults: 24,
  timeoutMs: 30 * 60 * 1000,
  maxTasks: 8,
  maxConcurrency: 4,
  defaultTier: "pro",
  tiers: {},
};

const TOP_ROW_PERCENT = "40";

// ─── context ──────────────────────────────────────────────────────────────────

const SUBAGENT_START = /<!--\s*@atelier:subagent\s*-->/;
const SUBAGENT_END = /<!--\s*\/@atelier:subagent\s*-->/;

function hasSubagentOnlySection(content: string): boolean {
  return SUBAGENT_START.test(content) && SUBAGENT_END.test(content);
}

function extractSubagentOnlySection(content: string): string {
  const parts: string[] = [];
  const lines = content.split("\n");
  let i = 0;
  let inSubagent = false;
  let buffer: string[] = [];

  while (i < lines.length) {
    const line = lines[i];

    if (!inSubagent && SUBAGENT_START.test(line)) {
      inSubagent = true;
      buffer = [];
      i++;
      continue;
    }

    if (inSubagent && SUBAGENT_END.test(line)) {
      inSubagent = false;
      parts.push(buffer.join("\n").trim());
      buffer = [];
      i++;
      continue;
    }

    if (inSubagent) {
      buffer.push(line);
    }
    i++;
  }

  if (inSubagent && buffer.length > 0) {
    parts.push(buffer.join("\n").trim());
  }

  return parts.filter((p) => p.length > 0).join("\n\n");
}

function stripSubagentOnlySection(content: string): string {
  const lines = content.split("\n");
  const result: string[] = [];
  let inSubagent = false;

  for (const line of lines) {
    if (!inSubagent && SUBAGENT_START.test(line)) {
      inSubagent = true;
      continue;
    }
    if (inSubagent && SUBAGENT_END.test(line)) {
      inSubagent = false;
      continue;
    }
    if (!inSubagent) {
      result.push(line);
    }
  }

  return collapseBlankLines(result.join("\n"));
}

function removeSubagentOnlyMarkers(content: string): string {
  return content
    .split("\n")
    .filter((line) => !SUBAGENT_START.test(line) && !SUBAGENT_END.test(line))
    .join("\n");
}

function collapseBlankLines(text: string): string {
  const lines = text.split("\n");
  const result: string[] = [];
  for (const line of lines) {
    const last = result[result.length - 1];
    if (line.trim() === "" && last !== undefined && last.trim() === "") {
      continue;
    }
    result.push(line);
  }
  return result.join("\n").trim();
}

// ─── config ───────────────────────────────────────────────────────────────────

import { existsSync, readFileSync } from "node:fs";

function loadConfig(): SubagentConfig {
  const candidates = [
    path.join(getAgentDir(), "settings.json"),
    path.join(os.homedir(), ".config", "pi", "settings.json"),
  ];

  let raw: Record<string, unknown> | undefined;
  for (const settingsPath of candidates) {
    if (!existsSync(settingsPath)) continue;
    try {
      raw = JSON.parse(readFileSync(settingsPath, "utf8"))?.atelier as
        | Record<string, unknown>
        | undefined;
      if (raw) break;
    } catch {
      continue;
    }
  }

  if (!raw) return DEFAULT_CONFIG;
  return {
    pollIntervalMs:
      typeof raw.pollIntervalMs === "number"
        ? raw.pollIntervalMs
        : DEFAULT_CONFIG.pollIntervalMs,
    panePrefix:
      typeof raw.panePrefix === "string"
        ? raw.panePrefix
        : DEFAULT_CONFIG.panePrefix,
    keepResults:
      typeof raw.keepResults === "number"
        ? raw.keepResults
        : DEFAULT_CONFIG.keepResults,
    timeoutMs:
      typeof raw.timeoutMs === "number"
        ? raw.timeoutMs
        : DEFAULT_CONFIG.timeoutMs,
    maxTasks:
      typeof raw.maxTasks === "number" ? raw.maxTasks : DEFAULT_CONFIG.maxTasks,
    maxConcurrency:
      typeof raw.maxConcurrency === "number"
        ? raw.maxConcurrency
        : DEFAULT_CONFIG.maxConcurrency,
    defaultTier:
      typeof raw.defaultTier === "string"
        ? raw.defaultTier
        : DEFAULT_CONFIG.defaultTier,
    tiers: parseTiers(raw.tiers),
  };
}

function parseTiers(raw: unknown): Record<string, AgentModelConfig> {
  if (!raw || typeof raw !== "object") return DEFAULT_CONFIG.tiers;
  const result: Record<string, AgentModelConfig> = {};
  for (const [name, value] of Object.entries(raw)) {
    if (!value || typeof value !== "object") continue;
    const v = value as Record<string, unknown>;
    if (typeof v.model !== "string") continue;
    const fallback = Array.isArray(v.fallback)
      ? v.fallback.filter((f): f is string => typeof f === "string")
      : [];
    result[name] = { model: v.model, fallback };
  }
  return result;
}

// ─── discovery ────────────────────────────────────────────────────────────────

function discoverAgents(): AgentConfig[] {
  const agentsDir = path.join(getAgentDir(), "agents");
  const agents: AgentConfig[] = [];

  if (!fs.existsSync(agentsDir)) return agents;

  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(agentsDir, { withFileTypes: true });
  } catch {
    return agents;
  }

  for (const entry of entries) {
    if (!entry.name.endsWith(".md")) continue;
    if (!entry.isFile() && !entry.isSymbolicLink()) continue;

    const filePath = path.join(agentsDir, entry.name);
    let content: string;
    try {
      content = fs.readFileSync(filePath, "utf-8");
    } catch {
      continue;
    }

    const { frontmatter, body } =
      parseFrontmatter<Record<string, string>>(content);
    if (!frontmatter.name || !frontmatter.description) continue;

    const tools = frontmatter.tools
      ?.split(",")
      .map((t: string) => t.trim())
      .filter(Boolean);

    const tier = frontmatter.tier?.trim() || undefined;

    agents.push({
      name: frontmatter.name,
      description: frontmatter.description,
      tools: tools && tools.length > 0 ? tools : undefined,
      tier,
      systemPrompt: body,
      filePath,
    });
  }

  return agents;
}

function parsePromptFrontmatter(
  content: string,
): { frontmatter: Record<string, string>; body: string } | null {
  let offset = 0;
  if (content.startsWith("<!--")) {
    const closeIdx = content.indexOf("-->");
    if (closeIdx >= 0) offset = closeIdx + 3;
  }
  while (offset < content.length && /\s/.test(content[offset])) offset++;

  if (!content.startsWith("---", offset)) return null;
  const fmStart = offset + 3;
  const fmEnd = content.indexOf("\n---", fmStart);
  if (fmEnd < 0) return null;

  const fmText = content.slice(fmStart, fmEnd);
  const frontmatter: Record<string, string> = {};
  for (const line of fmText.split("\n")) {
    const m = line.match(/^(\w+):\s*(.*)/);
    if (m) frontmatter[m[1]] = m[2].trim();
  }

  const body = content.slice(fmEnd + 4);
  return { frontmatter, body };
}

function discoverPrompts(): PromptConfig[] {
  const promptsDir = path.join(getAgentDir(), "prompts");
  const prompts: PromptConfig[] = [];

  if (!fs.existsSync(promptsDir)) return prompts;

  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(promptsDir, { withFileTypes: true });
  } catch {
    return prompts;
  }

  for (const entry of entries) {
    if (!entry.name.endsWith(".md")) continue;
    if (!entry.isFile() && !entry.isSymbolicLink()) continue;

    const filePath = path.join(promptsDir, entry.name);
    let content: string;
    try {
      content = fs.readFileSync(filePath, "utf-8");
    } catch {
      continue;
    }

    const parsed = parsePromptFrontmatter(content);
    if (!parsed || !parsed.frontmatter.name || !parsed.frontmatter.mode)
      continue;

    const mode = parsed.frontmatter.mode as "single" | "parallel" | "chain";
    if (!["single", "parallel", "chain"].includes(mode)) continue;

    const jsonMatch = parsed.body.match(/```json\s*\n([\s\S]*?)\n```/);
    if (!jsonMatch) continue;

    let template: Record<string, unknown>;
    try {
      template = JSON.parse(jsonMatch[1]);
    } catch {
      continue;
    }

    const promptEntries: Array<{ agent: string; task: string }> = [];
    const items = (template.chain ?? template.tasks ?? [template]) as Array<
      Record<string, string>
    >;
    for (const item of items) {
      if (item.agent && item.task) {
        promptEntries.push({ agent: item.agent, task: item.task });
      }
    }

    if (promptEntries.length === 0) continue;

    prompts.push({
      name: parsed.frontmatter.name,
      mode,
      param: parsed.frontmatter.param ?? "task",
      description: parsed.frontmatter.description ?? "",
      entries: promptEntries,
    });
  }

  return prompts;
}

// ─── workfile ─────────────────────────────────────────────────────────────────

function getWorkfileDir(cwd: string, agentName: string): string {
  return path.join(cwd, ".agents", "workfile", agentName);
}

function generateWorkfileName(): string {
  const date = new Date().toISOString().slice(0, 10);
  const hash = crypto.randomBytes(2).toString("hex");
  return `${date}-${hash}.md`;
}

function persistToWorkfile(
  cwd: string,
  agentName: string,
  content: string,
): string | undefined {
  try {
    const dir = getWorkfileDir(cwd, agentName);
    fs.mkdirSync(dir, { recursive: true });
    const fileName = generateWorkfileName();
    const filePath = path.join(dir, fileName);
    fs.writeFileSync(filePath, content, "utf-8");
    return path.relative(cwd, filePath);
  } catch {
    return undefined;
  }
}

function checkWorkfileExists(
  cwd: string,
  agentName: string,
  startedAt: number,
): boolean {
  try {
    const dir = getWorkfileDir(cwd, agentName);
    if (!fs.existsSync(dir)) return false;
    const files = fs.readdirSync(dir).filter((f) => f.endsWith(".md"));
    return files.some((f) => {
      const stat = fs.statSync(path.join(dir, f));
      return stat.mtimeMs >= startedAt - 5000;
    });
  } catch {
    return false;
  }
}

function ensureWorkfile(
  result: {
    agent: string;
    output: string;
    workfilePath?: string;
    status: string;
  },
  cwd: string,
  startedAt: number,
): void {
  if (checkWorkfileExists(cwd, result.agent, startedAt)) return;
  const workfilePath = persistToWorkfile(cwd, result.agent, result.output);
  if (workfilePath) {
    result.workfilePath = workfilePath;
  }
}

// ─── launcher ─────────────────────────────────────────────────────────────────

function resolveXdgCache(): string {
  return process.env.XDG_CACHE_HOME ?? path.join(os.homedir(), ".cache");
}

function resolveXdgData(): string {
  return (
    process.env.XDG_DATA_HOME ?? path.join(os.homedir(), ".local", "share")
  );
}

function getSubagentsDir(): string {
  return path.join(resolveXdgCache(), "pi", "subagents");
}

function getRunDir(runId: string): string {
  return path.join(getSubagentsDir(), runId);
}

function getScriptsDir(): string {
  return path.join(resolveXdgData(), "pi", "scripts");
}

function tmuxExec(args: string[]): string {
  return execFileSync("tmux", args, {
    encoding: "utf-8",
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();
}

function tmuxExecMaybe(args: string[]): string | null {
  try {
    return tmuxExec(args);
  } catch {
    return null;
  }
}

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`;
}

function generateRunId(): string {
  return `sa-${Date.now().toString(36)}-${crypto.randomBytes(3).toString("hex")}`;
}

function ensureWrapperExecutable(): string {
  const wrapper = path.join(getScriptsDir(), "subagent-wrapper.sh");
  try {
    fs.accessSync(wrapper, fs.constants.X_OK);
  } catch {
    throw new Error(`subagent wrapper is not executable: ${wrapper}`);
  }
  return wrapper;
}

function cleanupOldRuns(config: SubagentConfig): void {
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

function writeFailedStatus(
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

function paneIsAlive(paneId: string): boolean {
  return (
    tmuxExecMaybe(["display-message", "-p", "-t", paneId, "#{pane_id}"]) ===
    paneId
  );
}

function killPane(paneId: string): void {
  tmuxExecMaybe(["kill-pane", "-t", paneId]);
}

function prepareRunDir(runDir: string, task: string): void {
  fs.mkdirSync(runDir, { recursive: true });
  fs.writeFileSync(path.join(runDir, "task.md"), task, "utf-8");
  fs.writeFileSync(
    path.join(runDir, "status.json"),
    JSON.stringify({ status: "running", startedAt: Date.now() }),
    "utf-8",
  );
}

const CAPABILITY_SELF_CHECK = `## 能力自检（重要）

如果你发现自己**没有视觉能力**（无法直接理解图片附件）但收到了图片附件，**不要**试图猜测图片内容。请调用 visual subagent 处理图片：

\`\`\`
subagent({ agent: "visual", task: "分析以下图片：[描述图片情境]", images: [...] })
\`\`\`

支持视觉的模型：minimax-cn/MiniMax-M3、xiaomi/mimo-v2.5。`;

function prepareAgentPrompt(agentName: string, runDir: string): string | null {
  const agentPath = path.join(
    process.env.XDG_CONFIG_HOME ?? path.join(os.homedir(), ".config"),
    "pi",
    "agents",
    `${agentName}.md`,
  );
  let content: string;
  try {
    content = fs.readFileSync(agentPath, "utf-8");
  } catch {
    return null;
  }

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

  const body = `${CAPABILITY_SELF_CHECK}\n\n${rawBody}`;

  const promptPath = path.join(runDir, "subagent-prompt.md");
  try {
    fs.writeFileSync(promptPath, body, "utf-8");
    return promptPath;
  } catch {
    return null;
  }
}

function readStatus(runDir: string): StatusFile | null {
  const statusPath = path.join(runDir, "status.json");
  try {
    return JSON.parse(fs.readFileSync(statusPath, "utf-8"));
  } catch {
    return null;
  }
}

function readResult(runDir: string): string {
  const resultPath = path.join(runDir, "result.md");
  try {
    return fs.readFileSync(resultPath, "utf-8");
  } catch {
    return "(no output)";
  }
}

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

function splitAboveCurrentPane(cmd: string): string {
  return tmuxExec([
    "split-window",
    "-v",
    "-b",
    "-p",
    TOP_ROW_PERCENT,
    "-P",
    "-F",
    "#{pane_id}",
    cmd,
  ]);
}

function splitRightOfPane(
  targetPaneId: string,
  cmd: string,
  percent: number,
): string {
  return tmuxExec([
    "split-window",
    "-t",
    targetPaneId,
    "-h",
    "-p",
    String(Math.max(10, Math.min(90, percent))),
    "-P",
    "-F",
    "#{pane_id}",
    cmd,
  ]);
}

function launchSingle(
  agent: AgentConfig,
  task: string,
  config: SubagentConfig,
  cwd?: string,
  model?: string,
  topRowTargetPaneId?: string,
  splitPercent = 50,
  images?: string[],
): LaunchResult {
  if (!process.env.TMUX) {
    throw new Error("atelier requires Pi to run inside a tmux session");
  }

  cleanupOldRuns(config);
  const myPaneId = tmuxExec(["display-message", "-p", "#{pane_id}"]);
  const runId = generateRunId();
  const runDir = getRunDir(runId);
  prepareRunDir(runDir, task);

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

  const paneId = topRowTargetPaneId
    ? splitRightOfPane(topRowTargetPaneId, cmd, splitPercent)
    : splitAboveCurrentPane(cmd);

  tmuxExec(["select-pane", "-t", paneId, "-T", paneTitle]);
  tmuxExec(["select-pane", "-t", myPaneId]);

  return { runId, runDir, paneId, paneTitle, agent };
}

function launchParallel(
  tasks: Array<{ agent: AgentConfig; task: string; cwd?: string }>,
  config: SubagentConfig,
  model?: string,
  existingTopRowPaneId?: string,
): LaunchResult[] {
  if (!process.env.TMUX) {
    throw new Error("atelier requires Pi to run inside a tmux session");
  }

  cleanupOldRuns(config);
  const myPaneId = tmuxExec(["display-message", "-p", "#{pane_id}"]);
  const results: LaunchResult[] = [];
  const count = tasks.length;

  for (let i = 0; i < count; i++) {
    const { agent, task, cwd } = tasks[i];
    const runId = generateRunId();
    const runDir = getRunDir(runId);
    prepareRunDir(runDir, task);

    const promptFile = prepareAgentPrompt(agent.name, runDir);

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
      paneId = splitAboveCurrentPane(cmd);
    } else if (i === 0 && existingTopRowPaneId) {
      paneId = splitRightOfPane(
        existingTopRowPaneId,
        cmd,
        Math.round((count / (count + 1)) * 100),
      );
    } else {
      const pct = Math.round(((count - i) / (count - i + 1)) * 100);
      paneId = splitRightOfPane(results[i - 1].paneId, cmd, pct);
    }

    tmuxExec(["select-pane", "-t", paneId, "-T", paneTitle]);
    results.push({ runId, runDir, paneId, paneTitle, agent });
  }

  tmuxExec(["select-pane", "-t", myPaneId]);
  return results;
}

// ─── monitor ──────────────────────────────────────────────────────────────────

async function waitForCompletion(
  launch: LaunchResult,
  config: SubagentConfig,
  signal?: AbortSignal,
): Promise<RunResult> {
  const startedAt = Date.now();

  return new Promise<RunResult>((resolve) => {
    const interval = setInterval(() => {
      const agent = launch.paneTitle.replace(config.panePrefix, "");

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

      if (signal?.aborted) {
        killPane(launch.paneId);
        finishFailed(-1, "Aborted", "Aborted");
        return;
      }

      if (Date.now() - startedAt > config.timeoutMs) {
        killPane(launch.paneId);
        finishFailed(124, `Timed out after ${config.timeoutMs}ms`, "timeout");
        return;
      }

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

function waitForAll(
  launches: LaunchResult[],
  config: SubagentConfig,
  signal?: AbortSignal,
): Promise<RunResult[]> {
  return Promise.all(launches.map((l) => waitForCompletion(l, config, signal)));
}

function listRunning(): RunResult[] {
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

// ─── runner ───────────────────────────────────────────────────────────────────

function readDefaultModelFromSettings(): string[] {
  const candidates = [
    path.join(getAgentDir(), "settings.json"),
    path.join(os.homedir(), ".config", "pi", "settings.json"),
  ];
  for (const p of candidates) {
    try {
      const raw = JSON.parse(fs.readFileSync(p, "utf8")) as Record<
        string,
        unknown
      >;
      const provider = raw.defaultProvider;
      const model = raw.defaultModel;
      if (
        typeof provider === "string" &&
        typeof model === "string" &&
        provider &&
        model
      ) {
        return [`${provider}/${model}`];
      }
    } catch {
      continue;
    }
  }
  return [];
}

const MAX_ATTEMPTS = 3;

function resolveModelChain(
  agent: AgentConfig,
  config: SubagentConfig,
  explicitModel?: string,
): string[] {
  if (explicitModel) return [explicitModel];

  const tier = agent.tier ?? config.defaultTier;

  if (tier === "inherit") return readDefaultModelFromSettings();

  const tierCfg: AgentModelConfig | undefined = config.tiers[tier];
  if (!tierCfg) return [];

  return [tierCfg.model, ...tierCfg.fallback].filter(Boolean);
}

async function executeWithFallback(
  agent: AgentConfig,
  task: string,
  config: SubagentConfig,
  cwd: string,
  explicitModel: string | undefined,
  signal: AbortSignal | undefined,
  topRowTargetPaneId?: string,
  splitPercent?: number,
  images?: string[],
): Promise<RunResult> {
  const modelChain = resolveModelChain(agent, config, explicitModel);

  if (modelChain.length === 0) {
    const launch = launchSingle(
      agent,
      task,
      config,
      cwd,
      undefined,
      topRowTargetPaneId,
      splitPercent ?? 50,
      images,
    );
    return waitForCompletion(launch, config, signal);
  }

  let lastResult: RunResult | undefined;
  const maxAttempts = Math.min(MAX_ATTEMPTS, modelChain.length);

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const model = modelChain[attempt];
    const launch = launchSingle(
      agent,
      task,
      config,
      cwd,
      model,
      topRowTargetPaneId,
      splitPercent ?? 50,
      images,
    );
    const result = await waitForCompletion(launch, config, signal);

    if (result.status === "completed") return result;

    lastResult = result;
    if (result.error === "Aborted" || result.error === "timeout") return result;
  }

  return lastResult!;
}

async function runParallelBatches(
  tasks: Array<{ agent: AgentConfig; task: string; cwd?: string }>,
  config: SubagentConfig,
  cwd: string,
  explicitModel?: string,
  signal?: AbortSignal,
): Promise<RunResult[]> {
  const results: RunResult[] = [];
  const concurrency = Math.max(
    1,
    Math.min(config.maxConcurrency, config.maxTasks),
  );
  const startedAt = Date.now();
  let topRowTargetPaneId: string | undefined;

  for (let i = 0; i < tasks.length; i += concurrency) {
    const batch = tasks.slice(i, i + concurrency);
    if (topRowTargetPaneId && !paneIsAlive(topRowTargetPaneId)) {
      topRowTargetPaneId = undefined;
    }
    const launches = launchParallel(
      batch,
      config,
      explicitModel,
      topRowTargetPaneId,
    );
    topRowTargetPaneId = launches[launches.length - 1].paneId;
    const batchResults = await waitForAll(launches, config, signal);
    results.push(...batchResults);
  }

  for (const r of results) {
    if (r.status === "completed") {
      ensureWorkfile(r, cwd, startedAt);
    }
  }

  return results;
}

async function runChain(
  steps: Array<{ agent: AgentConfig; task: string; cwd?: string }>,
  config: SubagentConfig,
  cwd: string,
  rootTask?: string,
  explicitModel?: string,
  signal?: AbortSignal,
): Promise<RunResult[]> {
  const results: RunResult[] = [];
  let previous = rootTask ?? "";
  let topRowTargetPaneId: string | undefined;
  const startedAt = Date.now();

  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    const task = step.task
      .replaceAll("{previous}", previous)
      .replaceAll("{task}", rootTask ?? previous);
    const pct = Math.round(((steps.length - i) / (steps.length - i + 1)) * 100);

    const result = await executeWithFallback(
      step.agent,
      task,
      config,
      step.cwd ?? cwd,
      explicitModel,
      signal,
      topRowTargetPaneId,
      pct,
    );

    if (result.status === "completed") {
      ensureWorkfile(result, cwd, startedAt);
    }

    let outputWithContext = result.output;
    if (result.workfilePath) {
      outputWithContext += `\n\n---\n上一步工作产物已持久化到: ${result.workfilePath}`;
    }

    results.push(result);
    previous = outputWithContext;
    if (result.status === "failed") break;
  }

  return results;
}

// ─── formatting ───────────────────────────────────────────────────────────────

function formatResult(r: RunResult): string {
  const icon = r.status === "completed" ? "✓" : "✗";
  const workfile = r.workfilePath ? `\n📄 工作产物: ${r.workfilePath}` : "";
  return `### [${r.agent}] ${icon} (${r.durationMs}ms)${workfile}\n\n${r.output}`;
}

function formatResults(results: RunResult[]): string {
  const success = results.filter((r) => r.status === "completed").length;
  return `${success}/${results.length} succeeded\n\n${results.map(formatResult).join("\n\n---\n\n")}`;
}

// ─── schemas ──────────────────────────────────────────────────────────────────

const TaskItem = Type.Object({
  agent: Type.String({ description: "Agent 名称" }),
  task: Type.String({ description: "任务描述" }),
  cwd: Type.Optional(Type.String({ description: "工作目录" })),
});

const SubagentParams = Type.Object({
  agent: Type.Optional(
    Type.String({ description: "Agent 名称（single 模式）" }),
  ),
  task: Type.Optional(
    Type.String({
      description: "任务描述（single 模式，或 chain 模式的根任务）",
    }),
  ),
  tasks: Type.Optional(Type.Array(TaskItem, { description: "并行任务数组" })),
  chain: Type.Optional(
    Type.Array(TaskItem, {
      description: "串行任务链；可在 task 中使用 {previous} 和 {task}",
    }),
  ),
  action: Type.Optional(
    Type.Union([Type.Literal("list"), Type.Literal("status")], {
      description: "管理动作",
    }),
  ),
  id: Type.Optional(Type.String({ description: "查看指定 run-id 的状态" })),
  cwd: Type.Optional(Type.String({ description: "工作目录覆盖" })),
  model: Type.Optional(Type.String({ description: "模型覆盖" })),
  images: Type.Optional(
    Type.Array(Type.String(), {
      description: "图片文件路径数组，传递给 visual agent 分析",
    }),
  ),
});

// ─── session-log ──────────────────────────────────────────────────────────────

interface SessionLogEntry {
  timestamp: string;
  mode: "single" | "parallel" | "chain";
  agents: string[];
  tasks: string[];
  statuses: Array<"completed" | "failed" | "running">;
  totalDurationMs: number;
  outputPreview: string;
}

const sessionLog: SessionLogEntry[] = [];
const sessionStartedAt = new Date().toISOString();

function appendSessionLog(
  mode: "single" | "parallel" | "chain",
  results: RunResult[],
): void {
  if (results.length === 0) return;

  const entry: SessionLogEntry = {
    timestamp: new Date().toISOString(),
    mode,
    agents: results.map((r) => r.agent),
    tasks: results.map((r) => r.output.slice(0, 100)),
    statuses: results.map((r) => r.status),
    totalDurationMs: results.reduce((sum, r) => sum + r.durationMs, 0),
    outputPreview:
      results.length === 1
        ? results[0].output.slice(0, 200)
        : `${results.length} agents: ${results.map((r) => `${r.agent}(${r.status})`).join(", ")}`,
  };
  sessionLog.push(entry);
}

function finalizeSessionLog(cwd: string): string | undefined {
  if (sessionLog.length === 0) return undefined;

  const dir = path.join(cwd, ".agents", "workfile", "session-summaries");
  fs.mkdirSync(dir, { recursive: true });

  const date = new Date().toISOString().slice(0, 10);
  const hash = crypto.randomBytes(2).toString("hex");
  const fileName = `${date}-${hash}.md`;

  const totalCalls = sessionLog.length;
  const totalAgents = new Set(sessionLog.flatMap((e) => e.agents)).size;
  const completedCalls = sessionLog.filter((e) =>
    e.statuses.every((s) => s === "completed"),
  ).length;
  const totalDurationMs = sessionLog.reduce(
    (sum, e) => sum + e.totalDurationMs,
    0,
  );

  const lines: string[] = [
    `# 会话摘要`,
    ``,
    `- **会话开始**: ${sessionStartedAt}`,
    `- **会话结束**: ${new Date().toISOString()}`,
    `- **总调用次数**: ${totalCalls}`,
    `- **涉及 agent**: ${totalAgents}`,
    `- **全部成功**: ${completedCalls}/${totalCalls}`,
    `- **总耗时**: ${(totalDurationMs / 1000).toFixed(1)}s`,
    ``,
    `## 调用记录`,
    ``,
  ];

  for (let i = 0; i < sessionLog.length; i++) {
    const entry = sessionLog[i];
    const status = entry.statuses.every((s) => s === "completed") ? "✅" : "❌";
    const duration = (entry.totalDurationMs / 1000).toFixed(1);
    lines.push(
      `### ${i + 1}. [${entry.mode}] ${status} (${duration}s)`,
      ``,
      `- **Agent**: ${entry.agents.join(", ")}`,
      `- **状态**: ${entry.statuses.join(", ")}`,
      `- **输出预览**: ${entry.outputPreview}`,
      ``,
    );
  }

  const filePath = path.join(dir, fileName);
  fs.writeFileSync(filePath, lines.join("\n"), "utf-8");

  sessionLog.length = 0;

  return path.relative(cwd, filePath);
}

// ─── index (entry) ────────────────────────────────────────────────────────────

const PLAN_REVIEW_GATE_PROMPT = [
  "任务提交前需要先让 oracle 审查计划。",
  "请调用 subagent 工具：",
  'subagent(agent: "oracle", task: "审查以下实施计划的架构合理性和风险，提出建议。计划文件：<planFilePath>")',
  "",
  "审查完成后，如果计划需要修改请修改后再提交。",
  "如果计划已通过审查，直接再次调用 plannotator_submit_plan 即可（不会再次被阻止）。",
].join("\n");

const WORKER_OVERRIDE_GRACE_MS = 30_000;
let lastWorkerSingleWarnAt = 0;

function checkWorkerSingleOverride(): "warn" | "allow" {
  if (Date.now() - lastWorkerSingleWarnAt > WORKER_OVERRIDE_GRACE_MS) {
    lastWorkerSingleWarnAt = Date.now();
    return "warn";
  }
  return "allow";
}

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

const makeDetails =
  (mode: "single" | "parallel" | "chain" | "list" | "status") =>
  (results: RunResult[]): SubagentDetails => ({
    mode,
    results,
  });

export default function (pi: ExtensionAPI) {
  const config = loadConfig();

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

      if (params.agent && params.task) {
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
          const modelChain = resolveModelChain(agent, config);
          const initialModel = modelChain[0];
          const modelLabel = initialModel
            ? `(model: ${initialModel})`
            : `(model: inherit)`;
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

  const prompts = discoverPrompts();
  const agentNames = new Set(agents.map((a) => a.name));
  for (const prompt of prompts) {
    if (agentNames.has(prompt.name)) continue;
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

  {
    pi.on("before_agent_start", (event, ctx) => {
      const images = event.images;
      if (!images || images.length === 0) return;

      if (process.env.PI_SUBAGENT) return;

      const currentModel = ctx.model;
      if (currentModel?.input?.includes("image")) return;

      const tmpDir = path.join(os.tmpdir(), "pi-visual");
      fs.mkdirSync(tmpDir, {
        recursive: true,
      });
      const savedPaths: string[] = [];

      for (let i = 0; i < images.length; i++) {
        const img = images[i];
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

      return {
        systemPrompt: event.systemPrompt + "\n" + visionHint,
      };
    });
  }

  {
    const PLANNOTATOR_MARKER = "[PLANNOTATOR - PLANNING PHASE]";

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
      return systemPrompt.includes(PLANNOTATOR_MARKER);
    }

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
      if (process.env.PI_SUBAGENT) return;

      const planMode = isPlanModeActive(ctx, event.systemPrompt);
      const agentName = planMode ? "planner" : "worker";
      const contextContent = loadMainSessionAgentContext(agentName);
      if (!contextContent) return;

      const priorityHint = planMode
        ? "\n\n# 优先级提示：plan mode 下，plannotator 注入的 [PLANNOTATOR - PLANNING PHASE] 段中的所有约束优先级最高，与本文冲突时遵循 plannotator。\n"
        : "";

      return {
        systemPrompt:
          event.systemPrompt + priorityHint + "\n\n" + contextContent,
      };
    });
  }

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

      if (reviewedPlans.has(planFilePath)) {
        reviewedPlans.delete(planFilePath);

        try {
          const planContent = fs.readFileSync(planFilePath, "utf-8");
          const planDir = path.dirname(approvedPlanPath);
          fs.mkdirSync(planDir, {
            recursive: true,
          });
          fs.writeFileSync(approvedPlanPath, planContent, "utf-8");
        } catch {
          // 保存失败不阻塞
        }

        return {
          systemPrompt:
            "✅ 计划已通过 oracle 审查并保存。" +
            "请通知用户：执行 `/run-plan` 开始实施（将清空当前上下文，在新会话中执行计划）。" +
            "如果用户不想清空上下文，也可以直接按计划执行。",
        };
      }

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
