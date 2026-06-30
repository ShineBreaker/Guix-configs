// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * Atelier Registry — 全局 runs 索引（SQLite）
 *
 * 设计目标：
 *  - status.json 仍是单写真相源；registry 是查询视图
 *  - 启动时从 `$XDG_CACHE_HOME/pi/subagents/{runId}/status.json` 全量重建
 *  - 运行中由 atelier 端在 launcher/monitor 的关键点增量同步
 *  - 崩溃可丢：删 .db 文件下次启动自动重建
 *
 * 不动 wrapper.sh / extract-pi-result.py —— 它们只写 status.json，
 * 完全不知 SQLite 存在。本模块是 atelier 侧唯一的 SQLite writer。
 *
 * 技术决策：用 Node 22+ 内置 `node:sqlite` 而非 better-sqlite3，
 * 零新依赖；node:sqlite 是实验性 API 但 Schema/CRUD 子集已稳定。
 * 通过 `--no-warnings=ExperimentalWarning` 抑制启动噪音（pi 自身压制）。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { DatabaseSync } from "node:sqlite";
import type { StatusFile } from "../core/types.ts";

// ─── 常量 ────────────────────────────────────────────────────────────────────

/** status.json 中 "running" 状态也映射到 registry 的 running；终态直接对应。 */
const STATUS_MAP: Record<string, RunStatus> = {
  running: "running",
  completed: "completed",
  failed: "failed",
};

/** 任务摘要长度（task.md 前 N 字），避免 registry 体积爆炸 */
const TASK_EXCERPT_MAX = 200;

// ─── 类型 ────────────────────────────────────────────────────────────────────

/**
 * 扩展的 run 状态枚举。
 *
 * 比 `RunResult.status` 多了三个内部状态：
 *  - pending    : 分配了 runId 还没真正启动（未来 use，本阶段未使用）
 *  - orphan     : 进程重启前 wrapper 未写终态，自动标为孤儿
 *  - stuck      : 超阈值无 turn 更新（默认 5 分钟），由 stuck-detector 标
 *
 * wrapper 终态写入（completed/failed）会覆盖 orphan/stuck，无需特殊处理。
 */
export type RunStatus =
  | "pending"
  | "running"
  | "completed"
  | "failed"
  | "orphan"
  | "stuck";

/** `registerRun` 的输入参数。`startedAt`/`lastTurnAt` 不传则用 now。 */
export interface RegisterRunInput {
  runId: string;
  agent: string;
  /** "single" | "parallel" | "chain"，由 launcher 在 register 时传入 */
  mode: "single" | "parallel" | "chain";
  runDir: string;
  /** task.md 的全文或摘要；超长自动截断 */
  taskExcerpt?: string;
  tmuxPane?: string;
  startedAt?: number;
  /** PR-9: 系统子 agent 标记；默认 false。 */
  isSystemSpawned?: boolean;
  /** PR-10: 父 run id（chain/resume 关联查询用）。 */
  parentRunId?: string;
}

/** `updateRunStatus` 的输入参数。终态必须传 status，其余可选。 */
export interface UpdateRunStatusInput {
  runId: string;
  status: RunStatus;
  exitCode?: number;
  error?: string;
  finishedAt?: number;
  workfilePath?: string;
}

/** PR-7: `updateRunReturnStatus` 的输入参数。从 result.md 解析出的 header 字段。 */
export interface UpdateRunReturnStatusInput {
  runId: string;
  returnStatus: "success" | "partial" | "failed" | "blocked" | "unknown";
  returnSummary?: string;
}

/** 一条 run 的全部字段。 */
export interface RegisteredRun {
  runId: string;
  agent: string;
  mode: "single" | "parallel" | "chain";
  status: RunStatus;
  startedAt: number;
  finishedAt: number | null;
  lastTurnAt: number;
  tmuxPane: string | null;
  runDir: string;
  workfilePath: string | null;
  taskExcerpt: string;
  exitCode: number | null;
  error: string | null;
  /** PR-7: result.md header 解析出的 status。 */
  returnStatus: "success" | "partial" | "failed" | "blocked" | "unknown" | null;
  /** PR-7: result.md header 解析出的 summary。 */
  returnSummary: string | null;
  /** PR-7: 最近一次写入 returnStatus 的时间戳。 */
  returnStatusCheckedAt: number | null;
  /** PR-8: completion gate reentry 次数。 */
  reentryCount: number;
  /** PR-9: 系统子 agent 标记（白名单内的 agent 自动 true）。 */
  isSystemSpawned: boolean;
  /** PR-9/PR-10: 父 run id（chain step / resume parent）。 */
  parentRunId: string | null;
  /** PR-10: checkpoint 文件路径（本阶段可选；未来 resume 用）。 */
  checkpointPath: string | null;
}

interface RegisteredRow {
  run_id: string;
  agent: string;
  mode: string;
  status: string;
  started_at: number;
  finished_at: number | null;
  last_turn_at: number;
  tmux_pane: string | null;
  run_dir: string;
  workfile_path: string | null;
  task_excerpt: string;
  exit_code: number | null;
  error: string | null;
  return_status: string | null;
  return_summary: string | null;
  return_status_checked_at: number | null;
  reentry_count: number;
  is_system_spawned: number;
  parent_run_id: string | null;
  checkpoint_path: string | null;
}

/** rebuildFromStatusFiles 的统计报告 */
export interface RebuildReport {
  scanned: number;
  indexed: number;
  missingStatusFile: number;
  invalidStatusFile: number;
}

// ─── 路径解析 ────────────────────────────────────────────────────────────────

/**
 * registry DB 路径：`$XDG_DATA_HOME/pi/atelier-registry.db`。
 * 放在 data 目录而非 cache 目录，因为崩溃重建是有损的（丢失 turn 计数等），
 * 与 cache（每次启动从源头重建）有本质不同。
 */
function resolveRegistryPath(): string {
  const dataHome =
    process.env.XDG_DATA_HOME ?? path.join(os.homedir(), ".local", "share");
  return path.join(dataHome, "pi", "atelier-registry.db");
}

/** atelier run 目录根，参照 launcher.ts getSubagentsDir()。 */
function resolveSubagentsDir(): string {
  const cacheHome =
    process.env.XDG_CACHE_HOME ?? path.join(os.homedir(), ".cache");
  return path.join(cacheHome, "pi", "subagents");
}

// ─── 单例 DB ────────────────────────────────────────────────────────────────

let dbInstance: DatabaseSync | null = null;
let dbInitError: Error | null = null;

/**
 * 获取（懒初始化）registry DB 单例。
 *
 * 懒加载：第一次调用时才打开 .db、跑 CREATE TABLE。这样：
 *  - atelier 扩展加载时不会因 DB 错误就拒绝启动
 *  - 调用方拿到 db 后才能用 prepared statement（同步 API）
 *
 * @throws 第一次 init 失败的错误会被记住并重抛——后续 getRegistry 都失败，
 *         上层应在 init 时 try/catch。
 */
export function getRegistry(): DatabaseSync {
  if (dbInstance) return dbInstance;
  if (dbInitError) throw dbInitError;

  const dbPath = resolveRegistryPath();
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });

  const db = new DatabaseSync(dbPath);
  // WAL 模式：允许 concurrent read + single writer，避免阻塞 pi 主进程
  db.exec("PRAGMA journal_mode = WAL");
  db.exec("PRAGMA synchronous = NORMAL");
  initSchema(db);

  dbInstance = db;
  return db;
}

/**
 * 关闭 registry。session_shutdown 钩子调用。
 * 即使 init 失败也安全——可以是 noop。
 */
export function closeRegistry(): void {
  if (!dbInstance) return;
  try {
    dbInstance.close();
  } catch {
    /* ignore */
  }
  dbInstance = null;
}

// ─── Schema ──────────────────────────────────────────────────────────────────

/**
 * Schema 版本号。每次 ALTER TABLE 加列必须 +1 并在 migrate() 加分支。
 *   v1 = 初始（13 列）
 *   v2 = 新增 7 列（return_status / return_summary / return_status_checked_at /
 *                  reentry_count / is_system_spawned / parent_run_id / checkpoint_path）
 *        + 索引（idx_status / idx_started / idx_agent / idx_is_system / idx_parent）
 */
const SCHEMA_VERSION = 2;

/**
 * 初始化 schema。`IF NOT EXISTS` 保证幂等。
 *
 * 字段解释：
 *  - run_id     : PRIMARY KEY；`sa-{base36ts}-{3bytehex}`（runtime/launcher.ts generateRunId 生成）
 *  - agent      : agent 名（如 worker/scout/oracle），来自 agentConfig.name
 *  - mode       : single/parallel/chain，用于 `atelier list` 分组
 *  - status     : RunStatus 枚举字符串
 *  - run_dir    : $XDG_CACHE_HOME/pi/subagents/{run_id}
 *  - started_at / finished_at / last_turn_at : 时间戳；last_turn_at 本阶段总等于 started_at
 *  - task_excerpt: task.md 前 200 字摘要（避免大文本进 DB）
 *  - tmux_pane / workfile_path / exit_code / error : 运行期元数据
 *  - return_status / return_summary / return_status_checked_at : monitor 终态后从 result.md 解析
 *  - reentry_count : completion gate 自动 reentry 计数
 *  - is_system_spawned : 系统子 agent 标记（atelier-dream / distill / checkpoint-writer）
 *  - parent_run_id : chain step / resume parent 关联
 *  - checkpoint_path : 长程任务 checkpoint 文件路径
 */

function initSchema(db: DatabaseSync): void {
  // 表骨架(v1 兼容)。后续列都通过 migrate() 增量加,不修改这里。
  db.exec(`
    CREATE TABLE IF NOT EXISTS atelier_runs (
      run_id        TEXT PRIMARY KEY,
      agent         TEXT NOT NULL,
      mode          TEXT NOT NULL DEFAULT 'single',
      status        TEXT NOT NULL DEFAULT 'running',
      run_dir       TEXT NOT NULL,
      task_excerpt  TEXT NOT NULL DEFAULT '',
      started_at    INTEGER NOT NULL,
      finished_at   INTEGER,
      last_turn_at  INTEGER NOT NULL,
      tmux_pane     TEXT,
      workfile_path TEXT,
      exit_code     INTEGER,
      error         TEXT
    );
  `);
  migrate(db);
}

/**
 * 升级到当前 SCHEMA_VERSION。每次加列/索引/重命名都加一个 v+1 分支。
 *
 * 设计:
 *   - 用 `PRAGMA user_version` 记录当前版本(SQLite 原生支持)
 *   - 用 `PRAGMA table_info(...)` 检测列存在性(避免重复加列报错)
 *   - ALTER TABLE ADD COLUMN 支持 NOT NULL DEFAULT(必须有 default)
 *   - 加 NOT NULL 但无默认的列需分两步:先 nullable,UPDATE 填值,再改 NOT NULL
 *     (SQLite 12+ 起 ADD COLUMN 支持 NOT NULL DEFAULT,可省略 UPDATE)
 *   - 每次 ALTER 都 try/catch 单列失败不阻塞整体
 */
function migrate(db: DatabaseSync): void {
  const current = (db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version;
  if (current >= SCHEMA_VERSION) return;

  // v1 → v2: PR-7..11 新增列 + 索引
  if (current < 2) {
    const cols = new Set(
      (db.prepare("PRAGMA table_info(atelier_runs)").all() as Array<{ name: string }>).map((c) => c.name),
    );
    const addCol = (name: string, decl: string) => {
      if (cols.has(name)) return;
      try {
        db.exec(`ALTER TABLE atelier_runs ADD COLUMN ${name} ${decl}`);
      } catch (e) {
        console.error(`[atelier:registry] migration v1→v2 ADD COLUMN ${name} 失败:`, e);
      }
    };
    addCol("return_status", "TEXT");
    addCol("return_summary", "TEXT");
    addCol("return_status_checked_at", "INTEGER");
    addCol("reentry_count", "INTEGER NOT NULL DEFAULT 0");
    addCol("is_system_spawned", "INTEGER NOT NULL DEFAULT 0");
    addCol("parent_run_id", "TEXT");
    addCol("checkpoint_path", "TEXT");

    db.exec(`
      CREATE INDEX IF NOT EXISTS idx_status ON atelier_runs(status);
      CREATE INDEX IF NOT EXISTS idx_started ON atelier_runs(started_at);
      CREATE INDEX IF NOT EXISTS idx_agent ON atelier_runs(agent);
      CREATE INDEX IF NOT EXISTS idx_is_system ON atelier_runs(is_system_spawned);
      CREATE INDEX IF NOT EXISTS idx_parent ON atelier_runs(parent_run_id);
    `);
  }

  // 更新 user_version(原子)
  db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
  console.log(`[atelier:registry] schema 已升级 v${current} → v${SCHEMA_VERSION}`);
}

// ─── Rebuild from status.json ────────────────────────────────────────────────

/**
 * 启动时全量重建 registry：从 `$XDG_CACHE_HOME/pi/subagents/{runId}/status.json`
 * 把所有历史 run 同步进 SQLite。
 *
 * 设计：`INSERT OR IGNORE`，不覆盖已有记录。理由：
 *  - 运行中 wrapper 写终态时会调 updateStatus，可能比本次 rebuild 更晚
 *  - 已有 status=completed/failed 的 run 一定有正确终态，无需覆盖
 *  - 已有 status=running 的 run 在 rebuild 时也是 running（wrapper 还没写终态）
 *
 * @returns 重建报告（scanned / indexed / 错误计数）
 */
export function rebuildFromStatusFiles(): RebuildReport {
  const db = getRegistry();

  const subagentsDir = resolveSubagentsDir();
  if (!fs.existsSync(subagentsDir)) {
    return {
      scanned: 0,
      indexed: 0,
      missingStatusFile: 0,
      invalidStatusFile: 0,
    };
  }

  const insertStmt = db.prepare(`
    INSERT OR IGNORE INTO atelier_runs (
      run_id, agent, mode, status, run_dir, task_excerpt,
      started_at, finished_at, last_turn_at, tmux_pane, exit_code, error
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const report: RebuildReport = {
    scanned: 0,
    indexed: 0,
    missingStatusFile: 0,
    invalidStatusFile: 0,
  };

  // 重建用：先扫描所有 runDir，按 mtimeMs 升序处理（先老的），避免冲突
  const entries = fs.readdirSync(subagentsDir).sort();
  for (const entry of entries) {
    report.scanned++;
    const runDir = path.join(subagentsDir, entry);
    const runId = entry;

    const statusPath = path.join(runDir, "status.json");
    if (!fs.existsSync(statusPath)) {
      report.missingStatusFile++;
      continue;
    }

    let status: StatusFile;
    try {
      status = JSON.parse(fs.readFileSync(statusPath, "utf-8"));
    } catch {
      report.invalidStatusFile++;
      continue;
    }

    // task.md 摘要（前 200 字）
    let taskExcerpt = "";
    try {
      const task = fs.readFileSync(path.join(runDir, "task.md"), "utf-8");
      taskExcerpt = task.slice(0, TASK_EXCERPT_MAX);
    } catch {
      /* task.md 缺失可接受，保留空串 */
    }

    // agent 名：launcher 不存在时(若) 写 status.json — 从 runDir 名无法推导，
    // 留空字符串 ""，rebuild 不报错；registerRun 时会覆盖
    insertStmt.run(
      runId,
      "", // agent — 启动后再 registerRun 覆盖
      "single", // mode — 启动后再 registerRun 覆盖
      STATUS_MAP[status.status] ?? "running",
      runDir,
      taskExcerpt,
      status.startedAt ?? Date.now(),
      status.finishedAt ?? null,
      status.startedAt ?? Date.now(), // last_turn_at 本阶段 = started_at
      null, // tmux_pane 启动后再覆盖
      status.exitCode ?? null,
      status.error ?? null,
    );
    report.indexed++;
  }

  return report;
}

// ─── 写入 API ────────────────────────────────────────────────────────────────

/**
 * 注册一条新 run（launcher.ts:367/428 prepareRunDir 后调）。
 *
 * `INSERT OR REPLACE` 而非 `OR IGNORE` —— 同一 runId 在 rebuildFromStatusFiles
 * 已 insert 一行（agent=""），registerRun 二次写入时正确覆盖。
 *
 * 不抛异常：registry 失败不应阻塞 subagent 启动；失败仅 console.warn。
 */
export function registerRun(input: RegisterRunInput): void {
  try {
    const db = getRegistry();
    const now = Date.now();
    const startedAt = input.startedAt ?? now;

    db.prepare(
      `
      INSERT OR REPLACE INTO atelier_runs (
        run_id, agent, mode, status, run_dir, task_excerpt,
        started_at, finished_at, last_turn_at, tmux_pane,
        is_system_spawned, parent_run_id
      ) VALUES (?, ?, ?, 'running', ?, ?, ?, NULL, ?, ?, ?, ?)
      `,
    ).run(
      input.runId,
      input.agent,
      input.mode,
      input.runDir,
      (input.taskExcerpt ?? "").slice(0, TASK_EXCERPT_MAX),
      startedAt, // started_at
      startedAt, // last_turn_at 本阶段 = started_at
      input.tmuxPane ?? null,
      input.isSystemSpawned ? 1 : 0,
      input.parentRunId ?? null,
    );
  } catch (err) {
    console.warn(
      `[atelier:registry] registerRun failed for ${input.runId}:`,
      err,
    );
  }
}

/**
 * 终态更新（monitor.ts:50/92、launcher.ts:131 writeFailedStatus 后调）。
 *
 * 只更新指定字段——其他字段不动。INSERT OR IGNORE 兼容尚未 register 的 run
 * （monitor 终态时 launchSingle 早已 register 过，但 path-safe 写法）。
 */
export function updateRunStatus(input: UpdateRunStatusInput): void {
  try {
    const db = getRegistry();
    const finishedAt = input.finishedAt ?? Date.now();

    db.prepare(
      `
      UPDATE atelier_runs
      SET status = ?,
          finished_at = COALESCE(?, finished_at),
          exit_code  = COALESCE(?, exit_code),
          error      = COALESCE(?, error),
          workfile_path = COALESCE(?, workfile_path)
      WHERE run_id = ?
    `,
    ).run(
      input.status,
      input.status === "running" ||
        input.status === "stuck" ||
        input.status === "orphan"
        ? null
        : finishedAt,
      input.exitCode ?? null,
      input.error ?? null,
      input.workfilePath ?? null,
      input.runId,
    );
  } catch (err) {
    console.warn(
      `[atelier:registry] updateRunStatus failed for ${input.runId}:`,
      err,
    );
  }
}

/**
 * PR-7: 写入 return header 解析结果。
 * 独立接口（独立函数而非塞进 updateRunStatus），因为：
 *   - header 解析语义与 status 写终态是不同步的——status 由 wrapper 写终态，
 *     header 由 monitor 终态后从 result.md 异步解析
 *   - 调用方无需关心 schema 演进
 *
 * 失败仅 console.warn，不阻塞 subagent 调用方。
 */
export function updateRunReturnStatus(input: UpdateRunReturnStatusInput): void {
  try {
    const db = getRegistry();
    const now = Date.now();
    db.prepare(
      `
      UPDATE atelier_runs
      SET return_status = ?,
          return_summary = ?,
          return_status_checked_at = ?
      WHERE run_id = ?
      `,
    ).run(input.returnStatus, input.returnSummary ?? null, now, input.runId);
  } catch (err) {
    console.warn(
      `[atelier:registry] updateRunReturnStatus failed for ${input.runId}:`,
      err,
    );
  }
}

/**
 * PR-8: 递增 reentry_count（completion gate 触发 re-run 时调）。
 * 用 UPDATE ... SET reentry_count = reentry_count + 1，保证并发也原子。
 */
export function incrementReentryCount(runId: string): number {
  try {
    const db = getRegistry();
    db.prepare(
      "UPDATE atelier_runs SET reentry_count = reentry_count + 1 WHERE run_id = ?",
    ).run(runId);
    const row = db
      .prepare("SELECT reentry_count FROM atelier_runs WHERE run_id = ?")
      .get(runId) as { reentry_count: number } | undefined;
    return row?.reentry_count ?? 0;
  } catch (err) {
    console.warn(
      `[atelier:registry] incrementReentryCount failed for ${runId}:`,
      err,
    );
    return 0;
  }
}

/**
 * 触摸 last_turn_at 为 now。本阶段基本不调用（没有 turn 事件），
 * 留给后续 PR 引入 turn 计数时用。
 */
export function touchRun(runId: string): void {
  try {
    const db = getRegistry();
    db.prepare("UPDATE atelier_runs SET last_turn_at = ? WHERE run_id = ?").run(
      Date.now(),
      runId,
    );
  } catch {
    /* ignore — 本阶段 best-effort */
  }
}
// ─── 查询 API ────────────────────────────────────────────────────────────────

/** 把 row 转换为 RegisteredRun（snake_case → camelCase）。 */
function rowToRun(row: RegisteredRow): RegisteredRun {
  return {
    runId: row.run_id,
    agent: row.agent,
    mode: row.mode as RegisteredRun["mode"],
    status: row.status as RunStatus,
    startedAt: row.started_at,
    finishedAt: row.finished_at,
    lastTurnAt: row.last_turn_at,
    tmuxPane: row.tmux_pane,
    runDir: row.run_dir,
    workfilePath: row.workfile_path,
    taskExcerpt: row.task_excerpt,
    exitCode: row.exit_code,
    error: row.error,
    // result.md Return Header 解析结果（monitor 终态后写入）
    returnStatus: row.return_status as RegisteredRun["returnStatus"],
    returnSummary: row.return_summary,
    returnStatusCheckedAt: row.return_status_checked_at,
    // completion gate reentry 计数
    reentryCount: row.reentry_count,
    // 系统子 agent 标记 + chain/resume 父子关联
    isSystemSpawned: row.is_system_spawned === 1,
    parentRunId: row.parent_run_id,
    // 长程任务 checkpoint 文件路径
    checkpointPath: row.checkpoint_path,
  };
}

/** 列出所有"仍在进行"的 run（status IN running/stuck）。 */
export function listActive(): RegisteredRun[] {
  try {
    const db = getRegistry();
    const stmt = db.prepare(`
      SELECT * FROM atelier_runs
      WHERE status IN ('running', 'stuck')
      ORDER BY started_at ASC
    `);
    return (stmt.all() as RegisteredRow[]).map(rowToRun);
  } catch {
    return [];
  }
}

/** 按 status 过滤。 */
export function listByStatus(status: RunStatus): RegisteredRun[] {
  try {
    const db = getRegistry();
    const stmt = db.prepare(
      "SELECT * FROM atelier_runs WHERE status = ? ORDER BY started_at DESC",
    );
    return (stmt.all(status) as RegisteredRow[]).map(rowToRun);
  } catch {
    return [];
  }
}

/**
 * 列出最近 N 条 run（默认 50）。给未来的 `atelier list` UI 用。
 * 注意：本阶段不实现 list 命令（orchestration 留给后续 PR）。
 */
export function listRecent(limit = 50): RegisteredRun[] {
  try {
    const db = getRegistry();
    const stmt = db.prepare(
      "SELECT * FROM atelier_runs ORDER BY started_at DESC LIMIT ?",
    );
    return (stmt.all(limit) as RegisteredRow[]).map(rowToRun);
  } catch {
    return [];
  }
}

/** 按 run_id 查单条。 */
export function getRun(runId: string): RegisteredRun | null {
  try {
    const db = getRegistry();
    const stmt = db.prepare("SELECT * FROM atelier_runs WHERE run_id = ?");
    const row = stmt.get(runId) as RegisteredRow | undefined;
    return row ? rowToRun(row) : null;
  } catch {
    return null;
  }
}

/**
 * 列出所有未达终态的 run（不在 completed/failed 中）。
 * 给 orphan recovery 用。
 */
export function listUnsettled(): RegisteredRun[] {
  try {
    const db = getRegistry();
    const stmt = db.prepare(`
      SELECT * FROM atelier_runs
      WHERE status NOT IN ('completed', 'failed')
      ORDER BY started_at ASC
    `);
    return (stmt.all() as RegisteredRow[]).map(rowToRun);
  } catch {
    return [];
  }
}
