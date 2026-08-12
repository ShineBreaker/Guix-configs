// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * pi-gate — Pi Authority Boundary Extension
 *
 * 将 Crush bash-gate.sh / edit-gate.sh 的硬拦截逻辑移植到 Pi 的 tool_call hook。
 * 设计原则：
 *   - 硬拦截（block: true）用于 frozen commands / protected paths / 敏感信息
 *   - 上下文提醒（notify）用于"改了需要 blue home"等非致命场景（path_hints）
 *   - 命令改写（mutate event.input）用于 npm→pnpm 等环境适配
 *
 * 配置分层（ratchet 模型，越下层越严格，只能加码不能削弱）：
 *   1. 内置 DEFAULT_ANCHORS（兜底）
 *   2. 全局 ~/.config/agents/anchors.json（meta-frozen，人工维护，承载 sudo 等不可削弱项）
 *   3. 项目级 <root>/.agents/anchors.json —— 从 ctx.cwd 向上遍历到 git 根（含），
 *      收集每一层，按「根→近」合并。每层的相对 frozen_paths/frozen_globs/path_hints
 *      都相对【该层根目录】（包含其 anchors.json 的目录的父目录）解析，祖先 gate 才不会错位。
 *   数组取并集（项目层无法移除全局项）；映射浅合并、近层覆盖远层。
 *
 * 参考：
 *   - dotfiles/immutable/agents/.config/crush/hooks/bash-gate.sh
 *   - dotfiles/immutable/agents/.config/crush/hooks/edit-gate.sh
 *   - Pi docs: extensions.md §Tool Events (tool_call)
 */

import { appendFileSync, existsSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve, relative } from "node:path";

// ─── 加载错误日志（omp 默认静默吞掉扩展错误，这里显式留痕）────────────────────
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

// ─── Anchors 配置（分层声明，此处内联默认值）──────────────────────────────────

export interface AnchorsConfig {
  /** 冻结路径：~/ 开头按家目录展开；相对路径按【所在层根目录】解析；也按 basename 后缀匹配（如 channel.lock）。 */
  frozen_paths: string[];
  /** 冻结命令：子串匹配（如 "blue rebuild"）。 */
  frozen_commands: string[];
  /** 冻结 glob：相对【所在层根目录】匹配写入路径（如 "infra/**"、"*.lock"）。 */
  frozen_globs: string[];
  /** 软提示（非阻塞）：命令子串 → 建议文本。 */
  redirect_conventions: Record<string, string>;
  /** 命令 token 改写（非阻塞）：from → to（如 npm → bun）。 */
  rewrite: Record<string, string>;
  /** 路径提示（非阻塞 notify）：相对【所在层根目录】的前缀 → 提示文本。 */
  path_hints: Record<string, string>;
  /** 是否启用内置改写（npm→pnpm / pip→uv pip）。项目层可置 false 关闭。 */
  builtin_rewrite: boolean;
  /** 文档性：仅人工可执行的动作（供 completion reviewer / skill 参考）。 */
  human_only_actions: string[];
  /** 文档性：完成度度量锚点。 */
  anchor_measurements: string[];
  /** 交互式命令（无 TTY 会挂起）：出现即禁，命令起始位置 + 词边界匹配。名单来自全局 anchors.json。 */
  interactive_commands: string[];
  /** 裸 REPL 命令：仅无参数时禁（命令起始位置 + 行尾）。名单来自全局 anchors.json。 */
  bare_repl_commands: string[];
  /** 敏感信息检测：正则 + 标签 + 可选 flags（如 "i"）。名单来自全局 anchors.json。 */
  sensitive_patterns: Array<{ pattern: string; label: string; flags?: string }>;
}

/** anchors.json 原始内容（所有字段可选，含元字段）。 */
export type RawAnchors = Partial<AnchorsConfig> & {
  _comment?: string;
  _meta_frozen?: boolean;
};

/** 默认值：不可削弱的代码底层（in-code floor），与机器/仓库无关。
 *  sudo 恒被冻结（agent 任何场景都不需要提权）；交互式命令/Git 限制亦在代码中硬编。
 *  机器级（~/.config 部署保护）与仓库级（blue/guix system/tmp/channel.lock）规则
 *  分别放进全局 ~/.config/agents/anchors.json 与项目 <root>/.agents/anchors.json。 */
export const DEFAULT_ANCHORS: AnchorsConfig = {
  frozen_paths: [],
  frozen_commands: ["sudo"],
  frozen_globs: [],
  redirect_conventions: {},
  rewrite: {},
  path_hints: {},
  builtin_rewrite: true,
  human_only_actions: [],
  anchor_measurements: [],
  interactive_commands: [],
  bare_repl_commands: [],
  sensitive_patterns: [],
};

const arr = (v: unknown): string[] =>
  Array.isArray(v) ? v.filter((x) => typeof x === "string") : [];
const map = (v: unknown): Record<string, string> => {
  if (!v || typeof v !== "object" || Array.isArray(v)) return {};
  const out: Record<string, string> = {};
  for (const [k, val] of Object.entries(v as Record<string, unknown>)) {
    if (typeof val === "string") out[k] = val;
  }
  return out;
};
const uniq = (a: string[]): string[] => [...new Set(a)];

/** 从 unknown 提取 sensitive_patterns（校验 pattern 为 string；label 缺失补空串）。 */
const patternArr = (
  v: unknown,
): Array<{ pattern: string; label: string; flags?: string }> => {
  if (!Array.isArray(v)) return [];
  return v
    .filter(
      (x): x is Record<string, unknown> =>
        x != null &&
        typeof x === "object" &&
        typeof (x as Record<string, unknown>).pattern === "string",
    )
    .map((x) => ({
      pattern: x.pattern as string,
      label: typeof x.label === "string" ? x.label : "",
      flags: typeof x.flags === "string" ? x.flags : undefined,
    }));
};
/** 按 pattern 去重（保留首次出现，ratchet：全局层胜出）。 */
const dedupPatterns = (
  a: Array<{ pattern: string; label: string; flags?: string }>,
): Array<{ pattern: string; label: string; flags?: string }> => {
  const seen = new Set<string>();
  const out: Array<{ pattern: string; label: string; flags?: string }> = [];
  for (const p of a) {
    if (!seen.has(p.pattern)) {
      seen.add(p.pattern);
      out.push(p);
    }
  }
  return out;
};

/** 将 extra 合并到 base 之上（ratchet）：数组并集、映射浅合并（extra 覆盖）、builtin_rewrite 由 extra 决定（若给出）。 */
export function mergeAnchors(
  base: AnchorsConfig,
  extra: RawAnchors,
): AnchorsConfig {
  return {
    frozen_paths: uniq([...base.frozen_paths, ...arr(extra.frozen_paths)]),
    frozen_commands: uniq([
      ...base.frozen_commands,
      ...arr(extra.frozen_commands),
    ]),
    frozen_globs: uniq([...base.frozen_globs, ...arr(extra.frozen_globs)]),
    redirect_conventions: {
      ...base.redirect_conventions,
      ...map(extra.redirect_conventions),
    },
    rewrite: { ...base.rewrite, ...map(extra.rewrite) },
    path_hints: { ...base.path_hints, ...map(extra.path_hints) },
    builtin_rewrite:
      typeof extra.builtin_rewrite === "boolean"
        ? extra.builtin_rewrite
        : base.builtin_rewrite,
    human_only_actions: uniq([
      ...base.human_only_actions,
      ...arr(extra.human_only_actions),
    ]),
    anchor_measurements: uniq([
      ...base.anchor_measurements,
      ...arr(extra.anchor_measurements),
    ]),
    interactive_commands: uniq([
      ...base.interactive_commands,
      ...arr(extra.interactive_commands),
    ]),
    bare_repl_commands: uniq([
      ...base.bare_repl_commands,
      ...arr(extra.bare_repl_commands),
    ]),
    sensitive_patterns: dedupPatterns([
      ...base.sensitive_patterns,
      ...patternArr(extra.sensitive_patterns),
    ]),
  };
}

// ─── 分层加载 ─────────────────────────────────────────────────────────────────

export interface GateLayer {
  /** 该层根目录：全局层为家目录；项目层为包含 .agents/anchors.json 的目录。 */
  root: string;
  /** 该层 anchors.json 来源路径（全局层即全局路径）。 */
  file: string;
  cfg: AnchorsConfig;
}

export interface LoadedGates {
  globalPath: string;
  /** 全局层 + 各项目层（根→近顺序）。路径类检查逐层用各自 root 解析。 */
  layers: GateLayer[];
  /** 折叠后的单一配置：命令/改写/提示类（与根目录无关）用它。 */
  merged: AnchorsConfig;
}

function readJsonSafe(p: string): RawAnchors | null {
  try {
    if (!existsSync(p)) return null;
    const raw = JSON.parse(readFileSync(p, "utf-8"));
    return raw && typeof raw === "object" && !Array.isArray(raw)
      ? (raw as RawAnchors)
      : null;
  } catch {
    return null;
  }
}

function mtimeMs(p: string): number {
  try {
    return statSync(p).mtimeMs;
  } catch {
    return -1;
  }
}

/**
 * 从 startDir 向上遍历到 git 根（含）或文件系统根，收集每一层的 .agents/anchors.json。
 * 返回【近→根】顺序（cwd 最近者在前）。
 */
export function findAnchorsFiles(startDir: string): string[] {
  const found: string[] = [];
  let dir = resolve(startDir);
  // 防御性上限，避免异常挂载下无限上溯
  for (let i = 0; i < 64; i++) {
    const candidate = join(dir, ".agents", "anchors.json");
    if (existsSync(candidate)) found.push(candidate);
    if (existsSync(join(dir, ".git"))) break; // 含 git 根后停止
    const parent = dirname(dir);
    if (parent === dir) break; // 到达文件系统根
    dir = parent;
  }
  return found;
}

const gateCache = new Map<string, { sig: string; gates: LoadedGates }>();

/**
 * 加载并合并所有层配置（带 mtime 缓存）。
 * @param cwd 当前工作目录（项目层遍历起点）
 */
export function loadGates(cwd: string): LoadedGates {
  const home = homedir();
  const globalPath = join(home, ".config", "agents", "anchors.json");
  const projectFiles = findAnchorsFiles(cwd || home); // 近→根

  const sigParts = [`${globalPath}:${mtimeMs(globalPath)}`];
  for (const f of projectFiles) sigParts.push(`${f}:${mtimeMs(f)}`);
  const sig = sigParts.join("|");

  const key = cwd || "";
  const hit = gateCache.get(key);
  if (hit && hit.sig === sig) return hit.gates;

  const layers: GateLayer[] = [];
  // 全局层（root = 家目录）
  const globalRaw = readJsonSafe(globalPath);
  const globalCfg = globalRaw
    ? mergeAnchors(DEFAULT_ANCHORS, globalRaw)
    : DEFAULT_ANCHORS;
  layers.push({ root: home, file: globalPath, cfg: globalCfg });
  let merged = globalCfg;

  // 项目层：根→近（reverse 后），近层覆盖远层的映射、数组并集
  const rootFirst = [...projectFiles].reverse();
  for (const file of rootFirst) {
    const raw = readJsonSafe(file);
    if (!raw) continue;
    const root = dirname(dirname(file)); // <root>/.agents/anchors.json → <root>
    layers.push({ root, file, cfg: mergeAnchors(DEFAULT_ANCHORS, raw) });
    merged = mergeAnchors(merged, raw); // ratchet：全局项恒在，近层映射胜出
  }

  const gates: LoadedGates = { globalPath, layers, merged };
  gateCache.set(key, { sig, gates });
  return gates;
}

// ─── Bash 命令拦截规则 ──────────────────────────────────────────────────────

/** 命令起始位置前缀：行首 或 ; | && || ( $( 之后的可选空白。
 *  仅在命令起始位置匹配交互式命令名；避免 more/less/man/ed 等常见英文词出现在注释、字符串、参数中被误拦。 */
const PREFIX = /(?:^|[;&|\n(]|&&|\|\||\$\()\s*/;
const cp = (r: RegExp) => new RegExp(PREFIX.source + r.source);

// 交互式命令名单（出现即禁 / 仅裸调用禁）数据驱动，来自 anchors.json 的
// interactive_commands 与 bare_repl_commands；匹配机制（PREFIX + \b / $）在 checkBashCommand 内构造。

/** Git 写操作限制——同样仅命令起始位置 */
const RE_GIT_COMMIT = cp(/git\s+commit\b/);
const GIT_PATTERNS: Array<{ re: RegExp; msg: string }> = [
  { re: RE_GIT_COMMIT, msg: "" }, // 特殊处理：需要 -m
  { re: cp(/git\s+add\s.*-p\b/), msg: "禁止 git add -p（交互式）" },
  { re: cp(/git\s+rebase\s.*-i\b/), msg: "禁止 git rebase -i（交互式）" },
];

/**
 * 检查 bash 命令是否应被硬拦截。
 * @param cmd 命令字符串
 * @param merged 折叠后的配置（含全局 + 所有项目层的 frozen_commands 并集）
 * @returns 拦截原因，或 null 表示放行
 */
export function checkBashCommand(
  cmd: string,
  merged: AnchorsConfig,
): string | null {
  // Phase 1a: 冻结命令（子串匹配，来自各层 anchors.json 的并集）。
  //   - "blue rebuild" 命中真实 rebuild，但天然不命中 "blue --dry-run rebuild"（中间隔着 --dry-run）。
  //   - "sudo" 命中任何提权尝试（agent 永不需要 sudo）——恒在全局层，不可被项目层削弱。
  //   - 额外 --dry-run 兜底：命令显式带 --dry-run 时不冻结（纯验证，不写系统）。
  if (!cmd.includes("--dry-run")) {
    for (const frozen of merged.frozen_commands) {
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

  // Phase 1b: 交互式命令（无 TTY 会挂起）——名单来自 anchors.json，匹配在此构造
  for (const name of merged.interactive_commands) {
    if (cp(new RegExp(`${escapeRe(name)}\\b`)).test(cmd)) {
      return `🚫 禁止交互式命令 ${name}（无 TTY 会挂起），请使用对应工具`;
    }
  }
  for (const name of merged.bare_repl_commands) {
    if (cp(new RegExp(`${escapeRe(name)}\\s*$`)).test(cmd)) {
      return `🚫 禁止裸 REPL ${name}，请使用 ${name} -c '...' 或脚本`;
    }
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

// ─── rm 破坏性删除防护（通用，代码底层）──────────────────────────────────────
// 需要词边界精度（配置层子串匹配会误伤 confirm/form 等），故与 sudo/交互式/git 同族硬编，
// 对所有项目恒定生效。重定向目标：trash-put/gio trash 或 mv（保留可恢复副本）。
//   - 硬拦截：rm -rf（递归+强制）或 rm 针对根/家/$HOME/通配/./.. —— 不可逆且波及面大。
//   - 软提示：其余 rm —— 建议改用 trash/mv，避免误删重要文件。
const RE_RM = cp(/rm\b/);
const RE_RM_RECURSIVE = /(^|[\s])-[a-zA-Z]*[rR]|--recursive/;
const RE_RM_FORCE = /(^|[\s])-[a-zA-Z]*f|--force/;
/** 危险目标 token：/ ~ $HOME . .. /* ~/* （独立成词）。 */
const RE_RM_DANGEROUS_TARGET =
  /(^|[\s'"=])(\/|~|\$HOME|\.\.?|\/\*|~\/\*)(?=[\s'"]|$)/;

export function checkRmCommand(
  cmd: string,
): { block?: string; hint?: string } | null {
  const m = cmd.match(RE_RM);
  if (!m) return null;
  // 从 rm 起始位置往后取参数段（含后续链式命令，保守判定）
  const args = cmd.slice(m.index ?? 0);
  const recursive = RE_RM_RECURSIVE.test(args);
  const force = RE_RM_FORCE.test(args);
  const dangerousTarget = RE_RM_DANGEROUS_TARGET.test(args);
  if ((recursive && force) || dangerousTarget) {
    return {
      block:
        "🚫 禁止破坏性 rm（rm -rf，或针对根/家/$HOME/通配符的删除，不可逆）。请改用 `trash-put <path>` / `gio trash <path>`，或先 `mv <path> /tmp/` 保留可恢复副本。",
    };
  }
  return {
    hint: "💡 检测到 rm：建议改用 `trash-put`/`gio trash` 或 `mv` 到临时目录，避免误删重要文件后无法恢复。",
  };
}

/**
 * 非阻塞重定向建议：命令命中 redirect_conventions 时返回提示文本（不拦截）。
 * 例如裸 `guix home reconfigure`（不需 sudo，放行）→ 建议改用 blue home。
 */
export function checkRedirect(
  cmd: string,
  merged: AnchorsConfig,
): string | null {
  for (const [pattern, suggestion] of Object.entries(
    merged.redirect_conventions,
  )) {
    if (cmd.includes(pattern)) return `💡 ${suggestion}`;
  }
  return null;
}

// ─── 文件写入拦截规则 ──────────────────────────────────────────────────────

const GLOBAL_ANCHORS_PATH = join(
  homedir(),
  ".config",
  "agents",
  "anchors.json",
);

/**
 * 检查文件路径是否受保护（硬拦截）。
 * @param filePath 目标路径（绝对或相对）
 * @param gates 分层配置
 * @param projectDir 当前工作目录（用于豁免部署位置保护：项目内文件不拦）
 * @returns 拦截原因，或 null 表示放行
 */
export function checkProtectedPath(
  filePath: string,
  gates: LoadedGates,
  projectDir: string,
): string | null {
  const resolved = resolve(filePath);
  const home = homedir();
  const basename = resolved.split("/").pop() ?? resolved;

  // Meta-frozen：仅【全局】anchors.json 与显式声明 _meta_frozen 的 anchors.json 禁改。
  //   普通项目级 anchors.json 是 agent 可写的（由 writing-gates skill 引导维护），
  //   全局层承载 sudo 等不可削弱项，必须人工编辑。
  if (basename === "anchors.json") {
    if (resolved === GLOBAL_ANCHORS_PATH || resolved === gates.globalPath) {
      return "🚫 全局 anchors.json 是冻结规则源（meta-frozen），禁止 agent 修改。如需调整全局冻结规则请人工编辑。";
    }
    const raw = readJsonSafe(resolved);
    if (raw && raw._meta_frozen === true) {
      return "🚫 该 anchors.json 声明了 _meta_frozen，禁止 agent 修改（人工锁定的项目 gate）。如需调整请人工编辑。";
    }
    // 其余 anchors.json：agent 可写的项目 gate，放行（仍受下方 frozen_paths/globs 约束）
  }

  // 逐层 frozen_paths + frozen_globs（相对各层 root 解析）
  for (const layer of gates.layers) {
    const rel = relative(layer.root, resolved);
    const inside = !rel.startsWith(".."); // 路径在该层根目录之内时 rel 才有意义

    for (const frozen of layer.cfg.frozen_paths) {
      if (frozen.startsWith("~/")) {
        const expanded = join(home, frozen.slice(2));
        if (
          resolved === expanded ||
          resolved.startsWith(expanded + "/") ||
          resolved.startsWith(expanded)
        ) {
          return `🚫 冻结路径「${frozen}」禁止写入。请修改源文件后通过 blue home 生效。`;
        }
      } else if (
        (inside && rel.startsWith(frozen)) ||
        resolved.endsWith(frozen)
      ) {
        return `🚫 冻结路径「${frozen}」禁止写入。请修改源文件后通过 blue home 生效。`;
      }
    }

    if (inside) {
      for (const glob of layer.cfg.frozen_globs) {
        if (matchGlob(rel, basename, glob)) {
          return `🚫 冻结 glob「${glob}」禁止写入（项目级 gate）。`;
        }
      }
    }
  }

  // 部署位置保护（机器级硬底）：~/.config/ 和 ~/.local/，但排除项目内路径
  if (
    (resolved.startsWith(join(home, ".config") + "/") ||
      resolved.startsWith(join(home, ".local") + "/")) &&
    !resolved.startsWith(projectDir)
  ) {
    return "🚫 禁止直接修改已部署位置（~/.config/ 或 ~/.local/）。请修改 dotfiles/ 源文件后运行 blue home。";
  }

  return null; // 放行
}

/**
 * 收集非阻塞路径提示（path_hints，逐层相对 root 解析）。
 * @returns 去重后的提示文本数组
 */
export function collectPathHints(
  filePath: string,
  gates: LoadedGates,
): string[] {
  const resolved = resolve(filePath);
  const hints: string[] = [];
  for (const layer of gates.layers) {
    const rel = relative(layer.root, resolved);
    if (rel.startsWith("..")) continue;
    for (const [prefix, msg] of Object.entries(layer.cfg.path_hints)) {
      const p = prefix.endsWith("/") ? prefix : prefix + "/";
      if (rel === prefix || rel.startsWith(p) || rel.startsWith(prefix)) {
        hints.push(msg);
      }
    }
  }
  return [...new Set(hints)];
}

// ─── glob 匹配 ────────────────────────────────────────────────────────────────

function escapeRe(s: string): string {
  return s.replace(/[\\^$.|+()[\]{}]/g, "\\$&");
}

/** 将 glob 转为 anchored 正则：`**` → 任意（含 /），`*` → [^/]*，`?` → [^/]。 */
function globToRegex(glob: string): RegExp {
  let re = "";
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === "*") {
      if (glob[i + 1] === "*") {
        re += ".*";
        i++;
        if (glob[i + 1] === "/") i++; // 吞掉 **/ 的斜杠
      } else {
        re += "[^/]*";
      }
    } else if (c === "?") {
      re += "[^/]";
    } else {
      re += escapeRe(c);
    }
  }
  return new RegExp("^" + re + "$");
}

/**
 * glob 匹配：含 `/` 的 glob 对【相对路径】匹配；不含 `/` 的对【basename】匹配。
 */
export function matchGlob(
  rel: string,
  basename: string,
  glob: string,
): boolean {
  const re = globToRegex(glob);
  if (glob.includes("/")) {
    return re.test(rel) || re.test("./" + rel);
  }
  return re.test(basename);
}

// ─── 敏感信息检测 ──────────────────────────────────────────────────────────

// 敏感信息检测模式数据驱动，来自 anchors.json 的 sensitive_patterns（正则 + 标签 + 可选 flags）。

export function detectSensitiveInfo(
  content: string,
  merged: AnchorsConfig,
): string[] {
  const found: string[] = [];
  for (const { pattern, label, flags } of merged.sensitive_patterns) {
    try {
      if (new RegExp(pattern, flags ?? "").test(content)) found.push(label);
    } catch {
      // 无效正则跳过（配置损坏不应让 hook 崩溃）
    }
  }
  return found;
}

// ─── 命令改写（环境适配）────────────────────────────────────────────────────

export function rewriteCommand(
  cmd: string,
  merged: AnchorsConfig,
): { rewritten: string; note: string } | null {
  let result = cmd;
  const notes: string[] = [];

  if (merged.builtin_rewrite) {
    // npm → pnpm（若项目层显式 rewrite 了 npm，则以项目为准，跳过内置）
    if (!("npm" in merged.rewrite) && /(^|[|&;]\s*)npm\b/.test(result)) {
      result = result.replace(/(^|[|&;]\s*)npm\b/g, "$1pnpm");
      notes.push("npm→pnpm");
    }
    // pip → uv pip（同理，项目层 rewrite pip/pip3 时跳过内置）
    if (
      !("pip" in merged.rewrite) &&
      !("pip3" in merged.rewrite) &&
      /(^|[|&;]\s*)pip3?\b/.test(result)
    ) {
      result = result.replace(/(^|[|&;]\s*)pip3?\b/g, "$1uv pip");
      notes.push("pip→uv pip");
    }
  }

  // 项目层 token 改写（数据驱动，如 npm → bun）
  for (const [from, to] of Object.entries(merged.rewrite)) {
    const re = new RegExp("(^|[|&;]\\s*)" + escapeRe(from) + "\\b", "g");
    const out = result.replace(re, "$1" + to);
    if (out !== result) {
      result = out;
      notes.push(`${from}→${to}`);
    }
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

    const gates = loadGates(ctx.cwd);

    // 硬拦截检查
    const blockReason = checkBashCommand(cmd, gates.merged);
    if (blockReason) {
      if (ctx.hasUI) {
        ctx.ui.notify(blockReason, "error");
      }
      return { block: true, reason: blockReason };
    }

    // rm 破坏性删除防护（通用代码底层：rm -rf / 根·家·通配 硬拦；其余 rm 软提示改 trash/mv）
    const rm = checkRmCommand(cmd);
    if (rm?.block) {
      if (ctx.hasUI) {
        ctx.ui.notify(rm.block, "error");
      }
      return { block: true, reason: rm.block };
    }
    if (rm?.hint && ctx.hasUI) {
      ctx.ui.notify(rm.hint, "info");
    }

    // 非阻塞重定向建议（如裸 guix home reconfigure → 建议 blue home）
    const redirect = checkRedirect(cmd, gates.merged);
    if (redirect && ctx.hasUI) {
      ctx.ui.notify(redirect, "info");
    }

    // 命令改写（非阻塞）
    const rewrite = rewriteCommand(cmd, gates.merged);
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

    const gates = loadGates(ctx.cwd);

    // 路径保护检查
    const pathBlock = checkProtectedPath(filePath, gates, ctx.cwd);
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
      const sensitive = detectSensitiveInfo(content, gates.merged);
      if (sensitive.length > 0) {
        const reason = `🚫 检测到敏感信息: ${sensitive.join("; ")}。如确认无风险请手动操作。`;
        if (ctx.hasUI) {
          ctx.ui.notify(reason, "error");
        }
        return { block: true, reason };
      }
    }

    // 路径提示（非阻塞，来自各层 path_hints）
    if (ctx.hasUI) {
      for (const hint of collectPathHints(filePath, gates)) {
        ctx.ui.notify(hint, "info");
      }
    }

    return undefined;
  });
}
