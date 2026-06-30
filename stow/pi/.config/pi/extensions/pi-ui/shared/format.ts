// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * format.ts — 纯格式化 helper 集合（单一真相源）。
 *
 * 重构前这些函数散落在多个文件且部分重复：
 *   - fmtDuration：pet.ts + status-bar.ts 两份完全相同
 *   - formatBytes / shortModel / fmtTokens / makeBar / iconText：各居一处
 *   - formatTimeAgo：原在 plugin-bridge.ts，现由 collectRecentSessions 调用
 *
 * 现统一收拢。全部纯函数、无副作用、无外部依赖。
 */

/** 毫秒 → "1h2m" / "3m4s" / "45s" 时长格式 */
export function fmtDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const h = Math.floor(m / 60);
  if (h > 0) return `${h}h${m % 60}m`;
  if (m > 0) return `${m}m${s % 60}s`;
  return `${s}s`;
}

/** 字节数 → "1.2 KB" / "3.4 MB" 人类可读格式 */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/** 去掉 "Claude " 等厂商前缀，得到短模型名 */
export function shortModel(name: string): string {
  return name.startsWith("Claude ") ? name.slice(7) : name;
}

/** token 数 → "1.2k" / "45k" / "1.3M" 紧凑格式 */
export function fmtTokens(n: number): string {
  if (n < 1000) return String(n);
  if (n < 10000) return `${(n / 1000).toFixed(1)}k`;
  if (n < 1000000) return `${Math.round(n / 1000)}k`;
  return `${(n / 1000000).toFixed(1)}M`;
}

/** 百分比 → 8 格字符画进度条（█▓ ▱▱…） */
export function makeBar(pct: number): string {
  const filled = Math.max(0, Math.min(8, Math.round(pct / 12.5)));
  return "\u2593".repeat(filled) + "\u2591".repeat(8 - filled);
}

/** 图标 + 文本拼接；text 为空返回空串，icon 为空返回纯文本 */
export function iconText(icon: string, text: string): string {
  if (!text) return "";
  if (!icon) return text;
  return `${icon} ${text}`;
}

/**
 * mtime ms → "just now" / "5m ago" / "2h ago" / "3d ago" / "1w ago" / "2mo ago"。
 * 供 recent sessions 的 age 显示。
 */
export function formatTimeAgo(ms: number): string {
  const now = Date.now();
  const seconds = Math.floor((now - ms) / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  if (days < 30) return `${Math.floor(days / 7)}w ago`;
  return `${Math.floor(days / 30)}mo ago`;
}

// ═══════════════════════════════════════════════════════════════════════════
// TTL 缓存 helper
// ═══════════════════════════════════════════════════════════════════════════

/**
 * 进程内 TTL（time-to-live）缓存。重构前 status-bar.ts 有 4 个结构相同的
 * 全局变量（_dirtyCache / _aheadBehindCache / _hashCache / _langCache），
 * 每个都重复写 "if (now - fetchedAt < ttl) return cached; ... fetchedAt = now"
 * 这套样板。统一收口。
 *
 * 用法：
 *   const dirty = createTtlCache<number>(5000);
 *   const count = dirty.get(() => parseInt(execSync(...), 10) || 0);
 *
 * 带 key 的场景（如按 cwd 缓存）用 createKeyedTtlCache。
 */
export function createTtlCache<T>(ttlMs: number): {
  get: (fetch: () => T) => T;
} {
  let value: T | undefined;
  let fetchedAt = 0;
  let hasValue = false;
  return {
    get(fetch: () => T): T {
      const now = Date.now();
      if (hasValue && now - fetchedAt < ttlMs) return value as T;
      value = fetch();
      fetchedAt = now;
      hasValue = true;
      return value;
    },
  };
}

/**
 * 带 string key 的 TTL 缓存（如按 cwd 缓存项目语言）。每个 key 独立 TTL。
 */
export function createKeyedTtlCache<T>(ttlMs: number): {
  get: (key: string, fetch: () => T) => T;
} {
  const map = new Map<string, { value: T; fetchedAt: number }>();
  return {
    get(key: string, fetch: () => T): T {
      const now = Date.now();
      const hit = map.get(key);
      if (hit && now - hit.fetchedAt < ttlMs) return hit.value;
      const value = fetch();
      map.set(key, { value, fetchedAt: now });
      return value;
    },
  };
}
