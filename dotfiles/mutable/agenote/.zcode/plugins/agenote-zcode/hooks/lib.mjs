// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

// agenote-zcode hooks 共享库 — `agenote context` 注入三件套（设计 C4，追加型）
//
// 职责：指纹缓存（MEMORY.org/memories 的 mtime+size）、状态文件
// （~/.cache/agenote/injectors/zcode-<session_id>.json）、追加型三件套
// （①指纹+query 未变不重注 ②短 prompt/分数下限滤空跳过 ③单会话累计
// 预算触顶停 recall）。与 agenote 仓库 injectors/lib.sh（claude/codex 用）
// 及 hermes 插件同构，改语义需跨文件同步。
//
// 语义开关的真相源在 agenote SCHEMA [injection]（一键全关
// AGENOTE_INJECTION_ENABLED=false）；本库只管预算/门槛/状态目录旋钮。
// 前置：agenote CLI 须含 context 子命令（旧版 CLI 会静默空串 = 不注入）。
//
// 手动冒烟：
//   KB_ROOT=/tmp/kb AGENOTE_INJECTOR_STATE_DIR=/tmp/st node -e \
//     'import("./lib.mjs").then(m => console.log(m.recallTurn("t", process.cwd(), "查询文本足够长"))))'

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";

/** 单次预算（字符）：简报 8000 / recall 4000，设计 C4 每宿主预算表 */
export const BRIEF_BUDGET = Number(process.env.AGENOTE_INJECTION_BRIEF_BUDGET || 8000);
export const RECALL_BUDGET = Number(process.env.AGENOTE_INJECTION_RECALL_BUDGET || 4000);
/** 单会话累计预算（与 SCHEMA 同名 env 同口径；SessionStart/compact 重置） */
export const CUMULATIVE_BUDGET = Number(
  process.env.AGENOTE_INJECTION_SESSION_CUMULATIVE_BUDGET || 24000,
);
/** recall 有效 query 最短字符（镜像 SCHEMA recall_min_query=6） */
export const MIN_QUERY = Number(process.env.AGENOTE_INJECTION_MIN_QUERY || 6);
/** recall query 取 prompt 前 N 字符（设计 C4 规定值） */
export const QUERY_MAX_CHARS = 200;

const CLI_TIMEOUT_MS = 6000; // 单次 CLI 冷启动数百 ms，留足余量仍在 hook 超时内

// ── 状态目录：~/.cache/agenote/injectors/（整目录可清理，无副作用）──────────

export function stateDir() {
  return (
    process.env.AGENOTE_INJECTOR_STATE_DIR ||
    join(process.env.XDG_CACHE_HOME || join(homedir(), ".cache"), "agenote", "injectors")
  );
}

export function statePath(sessionId) {
  const sid = String(sessionId || "").trim().replaceAll("/", "_");
  return join(stateDir(), sid ? `zcode-${sid}.json` : "zcode.json");
}

export function readState(path) {
  try {
    const data = JSON.parse(readFileSync(path, "utf-8"));
    return data && typeof data === "object" ? data : {};
  } catch {
    return {};
  }
}

export function writeState(path, data) {
  try {
    mkdirSync(dirname(path), { recursive: true });
    const tmp = `${path}.tmp`;
    writeFileSync(tmp, JSON.stringify(data), "utf-8");
    renameSync(tmp, path);
  } catch {
    // 状态写失败宁可下轮重复注入，也不阻塞会话
  }
}

// ── KB agent 域根 + 指纹（与 injectors/lib.sh 同口径的镜像实现）──────────────

export function kbDomainRoot() {
  try {
    let kb = "";
    let agenoteDir = "agenote";
    if (process.env.KB_ROOT) {
      kb = process.env.KB_ROOT;
    } else {
      const cfgPath = join(
        process.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
        "agenote",
        "config.toml",
      );
      let section = "";
      for (const line of readFileSync(cfgPath, "utf-8").split("\n")) {
        const sec = line.match(/^\s*\[([^\]]+)\]\s*$/);
        if (sec) {
          section = sec[1];
          continue;
        }
        const kv = line.match(/^\s*([A-Za-z0-9_-]+)\s*=\s*"((?:[^"\\]|\\.)*)"\s*$/);
        if (kv && section === "paths") {
          if (kv[1] === "kb_root") kb = kv[2];
          if (kv[1] === "agenote_dir") agenoteDir = kv[2] || "agenote";
        }
      }
    }
    if (!kb) kb = join(homedir(), "Documents", "Org");
    kb = kb.replace(/^~(?=\/|$)/, homedir());
    return join(kb, agenoteDir);
  } catch {
    return join(homedir(), "Documents", "Org", "agenote");
  }
}

/** MEMORY.org 与 memories/ 的 mtime+size 指纹（设计 D8）；KB 缺失返回空串 */
export function kbFingerprint() {
  try {
    const root = kbDomainRoot();
    const st = statSync(join(root, "MEMORY.org"));
    let fp = `${Math.floor(st.mtimeMs)}:${st.size}`;
    try {
      const dir = statSync(join(root, "memories"));
      fp += `|${Math.floor(dir.mtimeMs)}:${dir.size}`;
    } catch {
      fp += "|-";
    }
    return fp;
  } catch {
    return "";
  }
}

// ── query 构造：prompt 折叠空白取前 200 字符 + cwd basename 伪词 ─────────────
// 门槛按 prompt 部分长度判（伪词不计入）；不过门槛返回 null（静默跳过）。

export function buildQuery(prompt, cwd) {
  const qText = String(prompt || "")
    .split(/\s+/)
    .filter(Boolean)
    .join(" ")
    .slice(0, QUERY_MAX_CHARS);
  if (qText.trim().length < MIN_QUERY) return null;
  const pseudo = basename(String(cwd || "").replace(/[\\/]+$/, ""));
  return pseudo && pseudo !== "." ? `${qText} ${pseudo}` : qText;
}

// ── CLI 调用：唯一允许的 agenote 调用形态；缺失/失败/非 ok 一律空串 ──────────

export function contextContent(host, mode, budget, query = "", cwd = "") {
  const args = [
    "context",
    "--mode",
    mode,
    "--budget",
    String(budget),
    "--host",
    host,
    "--format",
    "json",
  ];
  if (query) args.push("--query", query);
  try {
    const out = spawnSync("agenote", args, {
      encoding: "utf-8",
      timeout: CLI_TIMEOUT_MS,
      cwd: cwd || undefined, // session 模式 P 类项目匹配用 CLI 进程 cwd
      env: { ...process.env, AGENOTE_AGENT: host },
    });
    const data = JSON.parse((out.stdout || "") || "{}");
    return data && data.status === "ok" ? data.content || "" : "";
  } catch {
    return "";
  }
}

// ── 会话通道（SessionStart）：重置三件套状态 + 指纹缓存重放 ─────────────────
// SessionStart/compact 语义 = 重置：累计清零、recall 解禁；brief 缓存按指纹
// 保留（resume/clear/compact 重触发时 KB 未变则零 spawn 重放）。

export function sessionBrief(sessionId, cwd) {
  const fp = kbFingerprint();
  if (!fp) return "";
  const path = statePath(sessionId);
  const state = readState(path);
  delete state.recall_key;
  state.cumulative = 0;
  if (state.brief_key === fp && state.brief_content) {
    writeState(path, state);
    return state.brief_content;
  }
  delete state.brief_key;
  delete state.brief_content;
  writeState(path, state);
  const content = contextContent("zcode", "session", BRIEF_BUDGET, "", cwd);
  if (content) {
    state.brief_key = fp;
    state.brief_content = content;
    writeState(path, state);
  }
  return content;
}

// ── 每轮通道（UserPromptSubmit）：追加型三件套全量 ──────────────────────────

export function recallTurn(sessionId, cwd, prompt) {
  const fp = kbFingerprint();
  if (!fp) return "";
  const q = buildQuery(prompt, cwd);
  if (q === null) return ""; // 三件套②：短 prompt 不值得注入
  const path = statePath(sessionId);
  const state = readState(path);
  const key = `${fp}::${q}`;
  if (state.recall_key === key) return ""; // 三件套①：指纹+query 未变（含滤空）
  const cumulative = Number(state.cumulative || 0);
  if (cumulative >= CUMULATIVE_BUDGET) {
    state.recall_key = key; // 三件套③：触顶停 recall，记 key 防重复 spawn
    writeState(path, state);
    return "";
  }
  const content = contextContent("zcode", "recall", RECALL_BUDGET, q, cwd);
  state.recall_key = key;
  if (content) {
    state.cumulative = cumulative + content.length;
    writeState(path, state);
    return content;
  }
  writeState(path, state); // 滤空也落账：同 query 下轮零 spawn
  return "";
}
