// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Return Header 协议 — 把 subagent 自由文本结果升级为结构化解析
 *
 * 参考 MiMoCode `actor/return-header.ts` + `actor/spawn.ts:35-54`:
 *   子 agent 必须在 final message 顶部写出 `**Status**: success/partial/failed/blocked`,
 *   parent 不再靠 regex 猜,而是结构化解析。
 *
 * 协议格式:
 *
 *     **Status**: success | partial | failed | blocked
 *     **Summary**: <one sentence>
 *
 *     [actual deliverable here]
 *
 *     **Files touched**: <comma-separated paths or "(none)">
 *     **Findings worth promoting**: <bullet list or "(none)">
 *
 * 4 状态机:
 *   - success:  任务完成,所有目标达成
 *   - partial:  部分完成,目标未达或有次要问题
 *   - failed:   未完成,任务失败
 *   - blocked:  任务无法推进,需要外部介入(权限、依赖、决策等)
 *
 * 容错:
 *   - 没 header → parseReturnHeader 返回 null(调用方决定如何处理)
 *   - header 格式乱 → 返回 status="unknown" + 警告标记
 *
 * 不动 wrapper.sh / extract-pi-result.py:本模块是 atelier 侧纯 JS 实现,
 * 解析的是 result.md 全文(pane 子进程写入的最终 assistant 文本)。
 */

/** Return Header 的 4 状态枚举(扩展集合) */
export type ReturnStatus =
  | "success"
  | "partial"
  | "failed"
  | "blocked"
  | "unknown";

/** parseReturnHeader 的返回值 */
export interface ParsedReturnHeader {
  /** 4 状态之一,或 "unknown"(header 存在但格式乱) */
  status: ReturnStatus;
  /** 一句话摘要 */
  summary: string;
  /** 修改的文件,逗号分隔;空串表示 "(none)" 或无 header */
  filesTouched: string;
  /** 值得 promote 到 KB 的发现;空串表示 "(none)" 或无 header */
  findingsWorthPromoting: string;
  /** header 在原文中的位置(0-based 字符 offset);用于诊断 */
  headerEndOffset: number;
}

/** 单行严格匹配:`**Field**: value` 或 `**Field**:(none)` 等 */
const FIELD_RE = /^\*\*([^*]+)\*\*:\s*(.*)$/;

/** 已知字段名白名单(大小写不敏感) */
const KNOWN_STATUS_FIELDS = new Set(["status"]);
const KNOWN_SUMMARY_FIELDS = new Set(["summary"]);
const KNOWN_FILES_FIELDS = new Set(["files touched", "files"]);
const KNOWN_FINDINGS_FIELDS = new Set(["findings worth promoting", "findings"]);

/** 取 status 字段的合法值;其他值归类为 "unknown" */
function normalizeStatus(raw: string): ReturnStatus {
  const lower = raw.trim().toLowerCase();
  if (lower === "success") return "success";
  if (lower === "partial") return "partial";
  if (lower === "failed" || lower === "failure") return "failed";
  if (lower === "blocked") return "blocked";
  return "unknown";
}

/**
 * 把字段名归一化到我们内部使用的 key。
 * 例如 "Files touched" / "files" 都归一为 "filesTouched"。
 * 已知字段返回小写规范名;未知返回 null。
 */
function canonicalFieldName(raw: string): string | null {
  const lower = raw.trim().toLowerCase();
  if (KNOWN_STATUS_FIELDS.has(lower)) return "status";
  if (KNOWN_SUMMARY_FIELDS.has(lower)) return "summary";
  if (KNOWN_FILES_FIELDS.has(lower)) return "filesTouched";
  if (KNOWN_FINDINGS_FIELDS.has(lower)) return "findingsWorthPromoting";
  return null;
}

/**
 * 解析 result.md 中的 Return Header。
 *
 * @param content result.md 全文
 * @returns 解析结果;无 header 返回 null
 */
export function parseReturnHeader(content: string): ParsedReturnHeader | null {
  if (!content || typeof content !== "string") return null;

  // 找到第一个 `**Status**:` 字段;从那里开始采集头部字段
  const lines = content.split(/\r?\n/);
  let headerStartLine = -1;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const m = line.match(FIELD_RE);
    if (m && KNOWN_STATUS_FIELDS.has(m[1].trim().toLowerCase())) {
      headerStartLine = i;
      break;
    }
  }
  if (headerStartLine === -1) return null;

  // 从 headerStartLine 开始扫描,只接受紧邻的顶部字段
  // 遇到首个非已知字段行、或首个非 `**Field**:` 行、或空行 → header 结束
  const out: Partial<Record<string, string>> = {};
  let headerEndLine = headerStartLine;

  for (let i = headerStartLine; i < lines.length; i++) {
    const line = lines[i];
    const m = line.match(FIELD_RE);
    if (!m) {
      // 非字段行:header 结束
      headerEndLine = i;
      break;
    }
    const canonical = canonicalFieldName(m[1]);
    if (!canonical) {
      // 已知头部之外的其他字段行:当作 header 结束
      headerEndLine = i;
      break;
    }
    out[canonical] = m[2].trim();
    headerEndLine = i + 1; // 这一行属于 header
  }

  // 至少要有 status 字段;若 status 缺失,header 不完整
  if (!out.status) return null;

  const status = normalizeStatus(out.status);

  return {
    status,
    summary: out.summary ?? "",
    filesTouched: out.filesTouched ?? "",
    findingsWorthPromoting: out.findingsWorthPromoting ?? "",
    headerEndOffset: lines.slice(0, headerEndLine).join("\n").length,
  };
}

/**
 * 返回要追加到 agent prompt 的 Return Format 指令(由 launcher
 * 在 prepareAgentPrompt 末尾追加,期望子 agent 在 final message
 * 顶部写出该 header)。
 *
 * 指令文风参考 MiMoCode `actor/spawn.ts:35-54`,中文适配本机。
 */
export function formatReturnHeaderInstruction(): string {
  return `## Return Format(强制)

完成任务的最后,你必须以一段 **Return Header** 开始 assistant 的最终文本,格式严格如下:

\`\`\`
**Status**: success | partial | failed | blocked
**Summary**: <一句话描述本次结果>

<你的实际输出(交付物、解释、引用等)>

**Files touched**: <逗号分隔的文件路径,没有则写 (none)>
**Findings worth promoting**: <要点列表(适合升级到 KB 的经验),没有则写 (none)>
\`\`\`

**Status 取值**(必填,选一个):
- \`success\`: 任务完成,所有目标达成
- \`partial\`: 部分完成,目标未达或有次要问题
- \`failed\`: 未完成,任务失败
- \`blocked\`: 任务无法推进,需要外部介入(权限、依赖、决策等)

**注意**:
- Return Header 必须在**最终 assistant 文本的顶部**(前 4 行内),parent agent 才能结构化解析
- \`**Files touched\`\` 是相对路径(相对于 process.cwd()),父会话会写入 registry
- \`**Findings worth promoting\`\` 应是经过验证的事实,不是泛泛想法
- 字段名大小写不重要(Status/status/STATUS 都能解析),但冒号必须是英文半角 \`:\``;
}

/** 工具函数:Status 字符串是否在 4 个合法值之内 */
export function isKnownStatus(
  s: string,
): s is Exclude<ReturnStatus, "unknown"> {
  return (
    s === "success" || s === "partial" || s === "failed" || s === "blocked"
  );
}
