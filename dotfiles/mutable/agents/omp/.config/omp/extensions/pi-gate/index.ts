// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * pi-gate — Pi Authority Boundary Extension（协议适配器）
 *
 * 判定语义全部在 ~/.config/agents/gate-core.sh（决策核，规则源为两级
 * anchors.json 的 ratchet 合并：全局 ~/.config/agents/anchors.json +
 * 项目 <root>/.agents/anchors.json）。本扩展只做 Pi tool_call 协议转换：
 *   - BLOCK / SENSITIVE → { block: true, reason } + notify error
 *   - REWRITTEN         → mutate event.input.command（Pi 支持改写）
 *   - RM_HINT / NOTES / REDIRECT / HINT → notify info（非阻塞）
 *
 * 决策核缺失或执行异常时：sudo 子串保底拦截 + logLoadError 留痕，其余放行
 * （与 zcode / crush 适配器的降级策略一致）。
 *
 * 姊妹适配器：
 *   - dotfiles/mutable/agents/zcode/.zcode/hooks/{bash,edit}-gate.sh
 *   - dotfiles/immutable/agents/.config/crush/hooks/{bash,edit}-gate.sh
 */

import { appendFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const GATE_CORE = join(homedir(), ".config", "agents", "gate-core.sh");
const LOG_FILE = join(
  homedir(),
  ".config",
  "omp",
  "extensions",
  ".load-errors.log",
);

export function logLoadError(ext: string, where: string, err: unknown): void {
  const msg =
    err instanceof Error ? `${err.message}\n${err.stack ?? ""}` : String(err);
  appendFileSync(
    LOG_FILE,
    `[${new Date().toISOString()}] [${ext}] ${where}: ${msg}\n`,
  );
}

interface Verdict {
  /** 硬拦截理由（BLOCK 或 SENSITIVE）。 */
  block: string | null;
  /** 敏感信息命中（SENSITIVE）：与一般 BLOCK 分开仅为语义标记。 */
  sensitive: boolean;
  /** 改写后的命令（REWRITTEN）。 */
  rewritten: string | null;
  /** 非阻塞提示（RM_HINT / NOTES / REDIRECT / HINT）。 */
  hints: string[];
}

/** 调决策核并解析行协议（每行 `TYPE<TAB>payload`）。 */
function runCore(
  args: string[],
  cwd: string,
  input?: string,
): Verdict | null {
  let res;
  try {
    res = spawnSync("bash", [GATE_CORE, ...args], {
      input: input ?? "",
      env: { ...process.env, GATE_CWD: cwd },
      encoding: "utf8",
      timeout: 10_000,
    });
  } catch (err) {
    logLoadError("pi-gate", "runCore", err);
    return null;
  }
  if (res.error || res.status !== 0) {
    logLoadError("pi-gate", "gate-core", res.error ?? `exit ${res.status}`);
    return null;
  }
  const v: Verdict = {
    block: null,
    sensitive: false,
    rewritten: null,
    hints: [],
  };
  for (const line of (res.stdout ?? "").split("\n")) {
    if (!line) continue;
    const tab = line.indexOf("\t");
    const type = tab === -1 ? line : line.slice(0, tab);
    const payload = tab === -1 ? "" : line.slice(tab + 1);
    switch (type) {
      case "BLOCK":
        v.block = payload;
        return v;
      case "SENSITIVE":
        v.block = payload;
        v.sensitive = true;
        return v;
      case "REWRITTEN":
        v.rewritten = payload;
        break;
      case "RM_HINT":
      case "NOTES":
      case "REDIRECT":
      case "HINT":
        if (payload) v.hints.push(payload);
        break;
      // AUTO_ALLOW：Pi 无 auto-approve 概念，走默认流程即可
    }
  }
  return v;
}

export default function (pi: ExtensionAPI) {
  try {
    return factoryBody(pi);
  } catch (err) {
    logLoadError("pi-gate", "factory", err);
    throw err;
  }
}

function factoryBody(pi: ExtensionAPI) {
  // ── Bash 命令拦截 ────────────────────────────────────────────────────────
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return undefined;

    const cmd = (event.input as { command?: string }).command ?? "";
    if (!cmd) return undefined;

    const v = runCore(["bash", cmd], ctx.cwd);
    if (!v) {
      // 决策核异常：sudo 保底（agent 任何场景都不需要提权）
      if (cmd.includes("sudo")) {
        const reason =
          "🚫 冻结命令「sudo」禁止执行（gate-core 异常，保底拦截）。";
        if (ctx.hasUI) ctx.ui.notify(reason, "error");
        return { block: true, reason };
      }
      return undefined;
    }

    if (v.block) {
      if (ctx.hasUI) ctx.ui.notify(v.block, "error");
      return { block: true, reason: v.block };
    }

    if (v.rewritten) {
      (event.input as { command: string }).command = v.rewritten;
      if (ctx.hasUI) {
        ctx.ui.notify("已改写命令以适配本机环境", "info");
      }
    }
    if (ctx.hasUI) {
      for (const hint of v.hints) ctx.ui.notify(hint, "info");
    }
    return undefined;
  });

  // ── 文件写入拦截（write / edit）─────────────────────────────────────────
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "write" && event.toolName !== "edit") {
      return undefined;
    }

    const input = event.input as {
      path?: string;
      content?: string;
      edits?: Array<{ lines?: string[]; newText?: string }>;
    };
    const filePath = input.path ?? "";
    if (!filePath) return undefined;

    let content = "";
    if (event.toolName === "write") {
      content = input.content ?? "";
    } else if (input.edits) {
      content = input.edits
        .flatMap((e) => [...(e.lines ?? []), e.newText ?? ""])
        .join("\n");
    }

    const v = runCore(["edit", filePath], ctx.cwd, content);
    if (!v) return undefined;

    if (v.block) {
      if (ctx.hasUI) ctx.ui.notify(v.block, "error");
      return { block: true, reason: v.block };
    }
    if (ctx.hasUI) {
      for (const hint of v.hints) ctx.ui.notify(hint, "info");
    }
    return undefined;
  });
}
