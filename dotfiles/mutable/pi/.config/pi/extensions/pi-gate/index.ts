// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * pi-gate — Pi Authority Boundary Extension
 *
 * 将 Crush bash-gate.sh / edit-gate.sh 的硬拦截逻辑移植到 Pi 的 tool_call hook。
 * 设计原则：
 *   - 硬拦截（block: true）用于 frozen commands / protected paths / 敏感信息
 *   - 上下文提醒（notify）用于"改了需要 blue home"等非致命场景
 *   - 命令改写（mutate event.input）用于 npm→pnpm 等环境适配
 *
 * 参考：
 *   - dotfiles/immutable/agents/.config/crush/hooks/bash-gate.sh
 *   - dotfiles/immutable/agents/.config/crush/hooks/edit-gate.sh
 *   - Pi docs: extensions.md §Tool Events (tool_call)
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve, relative } from "node:path";

// ─── Anchors 配置（Phase 4 统一声明，此处内联默认值）─────────────────────────

interface AnchorsConfig {
  frozen_paths: string[];
  frozen_commands: string[];
  redirect_conventions: Record<string, string>;
  human_only_actions: string[];
  anchor_measurements: string[];
}

/** 默认值与 dotfiles/immutable/agents/.config/agents/anchors.json 保持一致（部署前的兜底）。
 *  冻结判定基于子串匹配："blue rebuild" 天然放行 "blue --dry-run rebuild"（中间隔着 --dry-run，不构成子串）。
 *  冻结的是「需要 sudo 提权」的命令；非 sudo 的 blue/guix 命令（blue home/stow/check 等）放行。 */
const DEFAULT_ANCHORS: AnchorsConfig = {
  frozen_paths: ["tmp/", "channel.lock", "~/.config/", "~/.local/"],
  frozen_commands: [
    "blue rebuild",
    "blue init",
    "blue clean",
    "guix system reconfigure",
    "guix system init",
    "sudo",
  ],
  redirect_conventions: {
    "guix home reconfigure":
      "建议改用 blue home（锁定频道版本 + 括号检查，保证可复现）",
  },
  human_only_actions: [
    "blue rebuild（Guix System reconfigure，需 sudo）",
    "blue init（装机到 /mnt，需 sudo）",
    "channel.lock 更新（blue update）",
    "distill → skills/（agenote 蒸馏产物须人工 review）",
  ],
  anchor_measurements: [
    "blue check 退出码 = 0（括号平衡 + tangle 通过）",
    "git diff 非空（有实际变更，非空报告）",
    "测试套件实际执行（不是被跳过或标准被降低）",
  ],
};

/**
 * 尝试从 anchors.json 加载配置；找不到则用默认值。
 * 查找路径：~/.config/agents/anchors.json
 */
function loadAnchors(): AnchorsConfig {
  const candidates = [
    join(homedir(), ".config", "agents", "anchors.json"),
    // 未来可扩展：项目级 .agents/anchors.json
  ];
  for (const p of candidates) {
    if (existsSync(p)) {
      try {
        const raw = JSON.parse(readFileSync(p, "utf-8"));
        return { ...DEFAULT_ANCHORS, ...raw };
      } catch {
        // JSON 解析失败，用默认值
      }
    }
  }
  return DEFAULT_ANCHORS;
}

// ─── Bash 命令拦截规则 ──────────────────────────────────────────────────────

/** 命令起始位置前缀：行首 或 ; | && || ( $( 之后的可选空白。
 *  仅在命令起始位置匹配交互式命令名；避免 more/less/man/ed 等常见英文词出现在注释、字符串、参数中被误拦。 */
const PREFIX = /(?:^|[;&|\n(]|&&|\|\||\$\()\s*/;
const cp = (r: RegExp) => new RegExp(PREFIX.source + r.source);

/** 交互式命令（无 TTY 会挂起）——仅在命令起始位置匹配 */
const INTERACTIVE_PATTERNS: Array<{ re: RegExp; msg: string }> = [
  {
    re: cp(/(vi|vim|nvim|nano|pico|ed|emacs)\b/),
    msg: "禁止交互式编辑器，请使用 edit/write 工具",
  },
  {
    re: cp(/(less|more|most|pg)\b/),
    msg: "禁止交互式 pager，请使用 read/grep 工具",
  },
  { re: cp(/man(?:\s|$)/), msg: "禁止 man，请使用 --help 或在线文档" },
  {
    re: cp(/(python|python3)\s*$/),
    msg: "禁止裸 REPL，请使用 python -c '...' 或 python script.py",
  },
  {
    re: cp(/node\s*$/),
    msg: "禁止裸 REPL，请使用 node -e '...' 或 node script.js",
  },
  { re: cp(/ipython\b/), msg: "禁止 ipython，请使用 python -c '...'" },
];

/** Git 写操作限制——同样仅命令起始位置 */
const RE_GIT_COMMIT = cp(/git\s+commit\b/);
const GIT_PATTERNS: Array<{ re: RegExp; msg: string }> = [
  { re: RE_GIT_COMMIT, msg: "" }, // 特殊处理：需要 -m
  { re: cp(/git\s+add\s.*-p\b/), msg: "禁止 git add -p（交互式）" },
  { re: cp(/git\s+rebase\s.*-i\b/), msg: "禁止 git rebase -i（交互式）" },
];

/**
 * 检查 bash 命令是否应被硬拦截。
 * 返回拦截原因，或 null 表示放行。
 */
function checkBashCommand(cmd: string, anchors: AnchorsConfig): string | null {
  // Phase 1a: 冻结命令（子串匹配，来自 anchors.json）。
  //   - "blue rebuild" 命中真实 rebuild，但天然不命中 "blue --dry-run rebuild"（中间隔着 --dry-run）。
  //   - "sudo" 命中任何提权尝试（agent 永不需要 sudo）。
  //   - 额外 --dry-run 兜底：命令显式带 --dry-run 时不冻结（纯验证，不写系统）。
  if (!cmd.includes("--dry-run")) {
    for (const frozen of anchors.frozen_commands) {
      if (cmd.includes(frozen)) {
        return `🚫 冻结命令「${frozen}」需 sudo 提权或为系统级操作，禁止 agent 执行。验证请用 \`blue --dry-run rebuild\`；固化请提醒用户手动运行。`;
      }
    }
  }
  // Phase 1a-2: guix system reconfigure/init 的宽匹配（含 `guix time-machine ... -- system reconfigure`
  //   包装形式，本仓库实际构建管线即用此形）。子串匹配会漏掉被参数隔开的包装形式，故用正则补捕。
  //   仅针对 system（需 sudo）；guix home reconfigure 不需 sudo，走 redirect_conventions 软提示。
  if (
    !cmd.includes("--dry-run") &&
    /\bguix\b/.test(cmd) &&
    /\bsystem\s+(reconfigure|init)\b/.test(cmd)
  ) {
    return "🚫 禁止 guix system reconfigure/init（含 time-machine 包装，需 sudo）。验证请用 `blue --dry-run rebuild`；固化请提醒用户手动运行。";
  }

  // Phase 1b: 交互式命令（无 TTY 会挂起）
  for (const { re, msg } of INTERACTIVE_PATTERNS) {
    if (re.test(cmd)) return `🚫 ${msg}`;
  }

  // Phase 1c: Git 限制
  for (const { re, msg } of GIT_PATTERNS) {
    if (re.test(cmd)) {
      if (msg) return `🚫 ${msg}`;
      if (RE_GIT_COMMIT.test(cmd) && !/(\s-m\s|\s--message\s)/.test(cmd)) {
        return "🚫 git commit 必须使用 -m 指定提交信息";
      }
    }
  }

  return null; // 放行
}

/**
 * 非阻塞重定向建议：命令命中 redirect_conventions 时返回提示文本（不拦截）。
 * 例如裸 `guix home reconfigure`（不需 sudo，放行）→ 建议改用 blue home。
 */
function checkRedirect(cmd: string, anchors: AnchorsConfig): string | null {
  for (const [pattern, suggestion] of Object.entries(
    anchors.redirect_conventions,
  )) {
    if (cmd.includes(pattern)) return `💡 ${suggestion}`;
  }
  return null;
}

// ─── 文件写入拦截规则 ──────────────────────────────────────────────────────

/**
 * 检查文件路径是否受保护。
 * @param filePath 绝对路径
 * @param projectDir 当前项目目录（用于判断相对路径）
 * @param anchors anchors 配置
 * @returns 拦截原因，或 null 表示放行
 */
function checkProtectedPath(
  filePath: string,
  projectDir: string,
  anchors: AnchorsConfig,
): string | null {
  const resolved = resolve(filePath);
  const rel = projectDir ? relative(projectDir, resolved) : resolved;

  // Meta-frozen: anchors.json 是冻结规则的单一权威源，agent 禁止修改（无论源还是部署位置），
  // 防止优化器削弱约束自己的规则（frozen rules must stay frozen under pressure）。修改须人工。
  if (
    /(^|\/)anchors\.json$/.test(resolved) ||
    /(^|\/)anchors\.json$/.test(filePath)
  ) {
    return "🚫 anchors.json 是冻结规则源（meta-frozen），禁止 agent 修改。如需调整冻结规则请人工编辑。";
  }

  // Frozen paths（从 anchors 加载）
  for (const frozen of anchors.frozen_paths) {
    if (frozen.startsWith("~/")) {
      // 家目录相对路径
      const expanded = join(homedir(), frozen.slice(2));
      if (resolved.startsWith(expanded)) {
        return `🚫 冻结路径「${frozen}」禁止写入。请修改源文件后通过 blue home 生效。`;
      }
    } else if (rel.startsWith(frozen) || resolved.endsWith(frozen)) {
      return `🚫 冻结路径「${frozen}」禁止写入。请修改源文件后通过 blue home 生效。`;
    }
  }

  // 部署位置保护：~/.config/ 和 ~/.local/（但排除项目内的路径）
  const home = homedir();
  if (
    (resolved.startsWith(join(home, ".config") + "/") ||
      resolved.startsWith(join(home, ".local") + "/")) &&
    !resolved.startsWith(projectDir)
  ) {
    return "🚫 禁止直接修改已部署位置（~/.config/ 或 ~/.local/）。请修改 dotfiles/ 源文件后运行 blue home。";
  }

  return null; // 放行
}

// ─── 敏感信息检测 ──────────────────────────────────────────────────────────

const SENSITIVE_PATTERNS: Array<{ re: RegExp; label: string }> = [
  { re: /sk-[a-zA-Z0-9]{20,}/i, label: "疑似 API key（sk-...）" },
  {
    re: /(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*["'][^"'\s]{8,}["']/i,
    label: "明文密码/secret/token",
  },
  {
    re: /-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----/,
    label: "SSH 私钥",
  },
  { re: /AKIA[0-9A-Z]{16}/, label: "疑似 AWS access key" },
  { re: /ghp_[a-zA-Z0-9]{36}/, label: "疑似 GitHub token" },
];

function detectSensitiveInfo(content: string): string[] {
  const found: string[] = [];
  for (const { re, label } of SENSITIVE_PATTERNS) {
    if (re.test(content)) found.push(label);
  }
  return found;
}

// ─── 命令改写（环境适配）────────────────────────────────────────────────────

function rewriteCommand(
  cmd: string,
): { rewritten: string; note: string } | null {
  let result = cmd;
  const notes: string[] = [];

  // npm → pnpm
  if (/(^|[|&;]\s*)npm\b/.test(result)) {
    result = result.replace(/(^|[|&;]\s*)npm\b/g, "$1pnpm");
    notes.push("npm→pnpm");
  }
  // pip → uv pip
  if (/(^|[|&;]\s*)pip3?\b/.test(result)) {
    result = result.replace(/(^|[|&;]\s*)pip3?\b/g, "$1uv pip");
    notes.push("pip→uv pip");
  }

  if (notes.length > 0) {
    return {
      rewritten: result,
      note: `已替换命令 (${notes.join(", ")})，注意参数差异`,
    };
  }
  return null;
}

// ─── Extension Entry ────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  const anchors = loadAnchors();

  // ── Bash 命令拦截 ────────────────────────────────────────────────────────
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return undefined;

    const cmd = (event.input as { command?: string }).command ?? "";
    if (!cmd) return undefined;

    // 硬拦截检查
    const blockReason = checkBashCommand(cmd, anchors);
    if (blockReason) {
      if (ctx.hasUI) {
        ctx.ui.notify(blockReason, "error");
      }
      return { block: true, reason: blockReason };
    }

    // 非阻塞重定向建议（如裸 guix home reconfigure → 建议 blue home）
    const redirect = checkRedirect(cmd, anchors);
    if (redirect && ctx.hasUI) {
      ctx.ui.notify(redirect, "info");
    }

    // 命令改写（非阻塞）
    const rewrite = rewriteCommand(cmd);
    if (rewrite) {
      (event.input as { command: string }).command = rewrite.rewritten;
      if (ctx.hasUI) {
        ctx.ui.notify(rewrite.note, "info");
      }
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

    // 路径保护检查
    const pathBlock = checkProtectedPath(filePath, ctx.cwd, anchors);
    if (pathBlock) {
      if (ctx.hasUI) {
        ctx.ui.notify(pathBlock, "error");
      }
      return { block: true, reason: pathBlock };
    }

    // 敏感信息检测
    let content = "";
    if (event.toolName === "write") {
      content = input.content ?? "";
    } else if (event.toolName === "edit" && input.edits) {
      content = input.edits
        .flatMap((e) => [...(e.lines ?? []), e.newText ?? ""])
        .join("\n");
    }

    if (content) {
      const sensitive = detectSensitiveInfo(content);
      if (sensitive.length > 0) {
        const reason = `🚫 检测到敏感信息: ${sensitive.join("; ")}。如确认无风险请手动操作。`;
        if (ctx.hasUI) {
          ctx.ui.notify(reason, "error");
        }
        return { block: true, reason };
      }
    }

    // 上下文提醒（非阻塞）
    const rel = ctx.cwd ? relative(ctx.cwd, resolve(filePath)) : filePath;
    if (rel.startsWith("dotfiles/")) {
      if (ctx.hasUI) {
        ctx.ui.notify("此文件修改后需要运行 blue home 才能生效", "info");
      }
    }
    if (filePath.endsWith(".org") && rel.startsWith("source/")) {
      if (ctx.hasUI) {
        ctx.ui.notify(
          "修改 org 配置后，务必先用 blue --dry-run rebuild 验证",
          "info",
        );
      }
    }

    return undefined;
  });
}
