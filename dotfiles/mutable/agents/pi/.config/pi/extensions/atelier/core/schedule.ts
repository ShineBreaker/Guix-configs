// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 模型使用时间窗口 DSL 解析器
 *
 * 让 tier 配置为每个模型声明可用时段（避免高峰期烧昂贵模型、或限定便宜模型
 * 只在夜间低峰跑）。DSL 紧凑、人类可写：
 *
 *   { "allow": ["Mon-Fri 09:00-18:00"] }     // 仅工作日上班时段可用
 *   { "deny": ["Mon-Fri 14:00-18:00"] }       // 工作日 14-18 禁用（高峰避开）
 *   { "allow": ["22:00-08:00"] }              // 仅夜间（跨午夜自动展开）
 *   { "allow": ["Sat,Sun 00:00-24:00"] }      // 仅周末
 *   {}                                         // 无限制（默认）
 *
 * 语义：
 *   - allow 非空：仅列出的窗口内可用；窗口外一律禁用。
 *   - deny 非空：列出的窗口内禁用；其余时段可用。
 *   - allow/deny 互斥，同时配置时 allow 优先（更严格的语义胜出）。
 *   - 二者皆空 / undefined：无限制（模型恒可用）。
 *
 * 时间范围跨午夜时（start > end，如 22:00-08:00）自动展开为两段：
 *   22:00-08:00 → [22:00-24:00, 00:00-08:00]
 * `24:00` 作为结束边界等价于「次日 00:00」，闭区间右端。
 */

// ─── 星期映射 ───────────────────────────────────────────────────────────────

/** 星期名（小写三字母）→ JS getDay() 序号（0=周日） */
const DAY_NAMES = {
  sun: 0,
  mon: 1,
  tue: 2,
  wed: 3,
  thu: 4,
  fri: 5,
  sat: 6,
};

// ─── 类型 ───────────────────────────────────────────────────────────────────

/** 单个时间窗口（分钟级，[startMin, endMin] 闭区间） */
export interface TimeWindow {
  /** 0=周日 ... 6=周六 */
  day: number;
  /** 起始分钟（含），0-1439 */
  startMin: number;
  /** 结束分钟（含），0-1440（1440 = 24:00 = 次日 00:00） */
  endMin: number;
}

/** 解析后的 schedule（allow/deny 已规范化为窗口列表） */
export interface ParsedSchedule {
  mode: "allow" | "deny" | "unrestricted";
  windows: TimeWindow[];
}

// ─── 解析原语 ───────────────────────────────────────────────────────────────

/**
 * 解析星期段，返回覆盖的星期序号集合。
 *
 * 接受形式：
 *   - 单日："Mon"
 *   - 范围："Mon-Fri"
 *   - 枚举："Sat,Sun"
 *   - 混合："Mon-Wed,Fri,Sat"
 *   - 空 / "*"：全部 0-6
 */
function parseDays(spec: string): number[] {
  const trimmed = spec.trim().toLowerCase();
  if (!trimmed || trimmed === "*") return [0, 1, 2, 3, 4, 5, 6];

  const result = new Set<number>();
  for (const part of trimmed.split(",")) {
    const seg = part.trim();
    if (!seg) continue;
    const range = seg.split("-");
    if (range.length === 1) {
      const d = DAY_NAMES[seg];
      if (d === undefined) throw new Error(`未知星期: "${seg}"`);
      result.add(d);
    } else if (range.length === 2) {
      const lo = DAY_NAMES[range[0].trim()];
      const hi = DAY_NAMES[range[1].trim()];
      if (lo === undefined || hi === undefined)
        throw new Error(`未知星期段: "${seg}"`);
      const [a, b] = lo <= hi ? [lo, hi] : [hi, lo];
      for (let d = a; d <= b; d++) result.add(d);
    } else {
      throw new Error(`星期段格式错误: "${seg}"`);
    }
  }
  if (result.size === 0) throw new Error(`星期段为空: "${spec}"`);
  return [...result].sort((a, b) => a - b);
}

/**
 * 解析 "HH:MM" 为当日分钟数（0-1440）。
 * 24:00 特例化为 1440（作为结束边界合法）。
 */
function parseTime(spec: string): number {
  const m = spec.trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!m) throw new Error(`时间格式错误: "${spec}"（期望 HH:MM）`);
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h === 24 && min === 0) return 1440; // 24:00 = 次日 00:00 边界
  if (h < 0 || h > 23 || min < 0 || min > 59)
    throw new Error(`时间越界: "${spec}"`);
  return h * 60 + min;
}

/** 解析单个条目 "[Days] HH:MM-HH:MM"，跨午夜展开为多窗口 */
function parseEntry(entry: string): TimeWindow[] {
  const text = entry.trim();
  if (!text) throw new Error("空条目");

  // 拆出可选的星期段（空格前缀）和时间段（末尾 HH:MM-HH:MM）
  const timeMatch = text.match(/(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})$/);
  if (!timeMatch) throw new Error(`条目缺少时间范围: "${entry}"`);
  const startMin = parseTime(timeMatch[1]);
  let endMin = parseTime(timeMatch[2]);
  if (endMin === 0) endMin = 1440; // 00:00 作为结束 → 当日 24:00

  const daySpec = text.slice(0, text.indexOf(timeMatch[0])).trim();
  const days = parseDays(daySpec); // 空串 → 全部 0-6

  // 跨午夜展开：startMin >= endMin（且非 24:00 整点边界）拆成两段
  // 例: 22:00-08:00 → [22:00-24:00] @ 当日 + [00:00-08:00] @ 次日
  const wrapsMidnight = startMin >= endMin && !(startMin === 0 && endMin === 1440);

  const windows: TimeWindow[] = [];
  for (const day of days) {
    if (wrapsMidnight) {
      windows.push({ day, startMin, endMin: 1440 });
      const nextDay = (day + 1) % 7;
      windows.push({ day: nextDay, startMin: 0, endMin });
    } else {
      windows.push({ day, startMin, endMin });
    }
  }
  return windows;
}

// ─── 公开 API ───────────────────────────────────────────────────────────────

/**
 * 从原始配置对象解析 schedule。
 *
 * 输入形状（来自 atelier.json / settings.json 的 tier.schedule 字段）：
 *   { allow: string[] }  /  { deny: string[] }  /  undefined / {}
 *
 * 解析失败（语法错误）→ 返回 unrestricted 并 console.warn（不抛——
 * 配置错误不应让 atelier 拒绝启动）。
 */
export function parseSchedule(
  raw: unknown,
  modelLabel?: string,
): ParsedSchedule {
  const tag = modelLabel ? ` (model=${modelLabel})` : "";
  if (!raw || typeof raw !== "object") return { mode: "unrestricted", windows: [] };
  const obj = raw as { allow?: unknown; deny?: unknown };

  const toEntries = (v: unknown): string[] =>
    Array.isArray(v) ? v.filter((s): s is string => typeof s === "string") : [];

  const allow = toEntries(obj.allow);
  const deny = toEntries(obj.deny);

  // allow 优先（更严格语义胜出）
  if (allow.length > 0) {
    try {
      const windows = allow.flatMap(parseEntry);
      return { mode: "allow", windows };
    } catch (err) {
      console.warn(`[atelier:schedule] allow 解析失败${tag}:`, err);
      return { mode: "unrestricted", windows: [] };
    }
  }
  if (deny.length > 0) {
    try {
      const windows = deny.flatMap(parseEntry);
      return { mode: "deny", windows };
    } catch (err) {
      console.warn(`[atelier:schedule] deny 解析失败${tag}:`, err);
      return { mode: "unrestricted", windows: [] };
    }
  }
  return { mode: "unrestricted", windows: [] };
}

/** 取当前时间对应的「星期 + 当日分钟」 */
function nowWindow(now = new Date()): { day: number; minute: number } {
  return {
    day: now.getDay(),
    minute: now.getHours() * 60 + now.getMinutes(),
  };
}

/** 判断给定时刻是否落在某窗口内（闭区间，endMin=1440 视为 24:00 边界） */
function inWindow(w: TimeWindow, day: number, minute: number): boolean {
  if (w.day !== day) return false;
  return minute >= w.startMin && minute < w.endMin;
}

/**
 * 判断模型在「当前时刻」是否允许使用。
 *
 *   unrestricted → 恒 true
 *   allow        → 落在任一窗口内才 true
 *   deny         → 落在任一窗口内则 false，否则 true
 *
 * @param schedule parseSchedule 的结果
 */
export function isModelAllowedNow(
  schedule: ParsedSchedule,
  now: Date = new Date(),
): boolean {
  if (schedule.mode === "unrestricted") return true;
  const { day, minute } = nowWindow(now);
  const hit = schedule.windows.some((w) => inWindow(w, day, minute));
  return schedule.mode === "allow" ? hit : !hit;
}
