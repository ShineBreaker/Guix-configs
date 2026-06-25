// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * pi-ui — 自写 UI 扩展（替换 pi-powerline-footer 的部分功能）
 *
 * 提供：
 *   1. 启动欢迎 header（WelcomeHeader，永不弹 overlay 覆盖层）
 *   2. starship 风格 status bar（footer）：model · path · git · thinking · context · tokens · timeSpent · time
 *
 * 与其他扩展的互动：
 *   - global-context: 读其 settings 配置展示"实际注入的 context 文件数"
 *   - pi-powerline-footer: 同时存在时，后注册者胜；本扩展通过监听 model_select
 *     防止 pi-powerline-footer 在模型切换时 setHeader(undefined) 清空我们的 header
 *   - 其他本地扩展（atelier / agenote-hooks / custom-shortcuts / default-timeout）：
 *     无冲突，事件不重叠
 *
 * 关键 API 细节：
 *   - ctx.getContextUsage() 返回 { tokens, contextWindow, percent } 三个字段
 *   - pi.getThinkingLevel() 在 factory 闭包中捕获，bindCore 后可用
 *   - setHeader/setFooter 接收 factory：(tui, theme) => Component & {dispose?}
 *   - Component.render 签名 (width: number) => string[]，theme 在工厂里捕获
 *   - 非 TUI 模式（ctx.mode !== "tui"）不渲染装饰性 header/footer
 *   - FooterState 的 gitBranch 由 footerData.getGitBranch() 在 render 时动态获取
 */

import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import type { TUI } from "@earendil-works/pi-tui";
import { readSettings } from "./xdg-settings.ts";
import {
  collectLoaded,
  discoverContextFiles,
  discoverLocalExtensions,
  discoverLocalTemplates,
  runAgenoteHealth,
  type LoadedCounts,
  type RecentSessionInfo,
} from "./plugin-bridge.ts";
import {
  createWelcomeHeader,
  type WelcomeData,
} from "./welcome-box.ts";
import {
  createStatusBar,
  type FooterState,
} from "./status-bar.ts";

/** 缓存渲染所需数据 */
interface UiCache {
  welcome: WelcomeData | null;
  footer: FooterState;
  /** 捕获的 TUI 引用，用于触发重绘（powerline-footer 同款模式） */
  tuiRef: TUI | null;
  sessionStartMs: number;
}

export default function piUiExtension(pi: ExtensionAPI): void {
  const sessionStartMs = Date.now();

  const cache: UiCache = {
    welcome: null,
    footer: {
      modelName: "...",
      thinkingLevel: "off",
      cwd: process.cwd(),
      gitBranch: null,
      contextPercent: null,
      contextTokens: null,
      contextWindow: 0,
      sessionStartMs,
    },
    tuiRef: null,
    sessionStartMs,
  };

  function refreshCacheFromCtx(ctx: ExtensionContext): void {
    const settings = readSettings();
    const loaded: LoadedCounts = {
      contextFiles: discoverContextFiles(settings),
      ...collectLoaded(pi),
      extensions: discoverLocalExtensions(),
      templates: discoverLocalTemplates(),
    };
    const modelName = ctx.model?.name ?? ctx.model?.id ?? "no model";
    const providerName = ctx.model?.provider ?? "unknown";
    cache.footer.modelName = modelName;
    cache.footer.cwd = ctx.cwd ?? process.cwd();

    // thinking level 从 pi API 拿
    try {
      cache.footer.thinkingLevel = pi.getThinkingLevel();
    } catch {
      cache.footer.thinkingLevel = "off";
    }

    // context 用量
    const usage = ctx.getContextUsage?.();
    cache.footer.contextPercent = usage?.percent ?? null;
    cache.footer.contextTokens = usage?.tokens ?? null;
    cache.footer.contextWindow = usage?.contextWindow ?? 0;

    // 默认 tips
    const tips = [
      "/ for commands",
      "! to run bash",
      "Tab cycle thinking",
    ];

    // recent sessions：留到后续实现
// recent sessions：留到后续实现
    const recent: RecentSessionInfo[] = [];

    // Agenote 健康度（运行 kb agenote health 解析，失败时 available=false）
    const agenote = runAgenoteHealth();

    cache.welcome = {
      modelName,
      providerName,
      tips,
      loaded,
      recent,
      agenote,
    };
  }

  /** 主动请求重绘（用于 model_select / tool_call 等事件后刷新 footer） */
  function requestRender(): void {
    cache.tuiRef?.requestRender();
  }

  // ── session_start：注册 header + footer ─────────────────────────────

  pi.on("session_start", async (event, ctx) => {
    // TUI 守卫：非 TUI 模式（pi -p / RPC / SDK）不渲染装饰性 header/footer
    if (ctx.mode !== "tui") return;
    if (ctx.hasUI === false) return;

    refreshCacheFromCtx(ctx);

    // Footer：始终替换
    const statusBarFactory = createStatusBar(() => cache.footer);
    ctx.ui.setFooter((tui, _theme, _footerData) => {
      // 捕获 TUI 引用（首次调用即生效）
      cache.tuiRef = tui as TUI;
      return statusBarFactory(tui, _theme, _footerData);
    });

    // Header：仅 startup reason 注册，避免 resume/branch 时重复渲染
    if (event.reason === "startup") {
      const welcomeFactory = createWelcomeHeader(() => {
        if (!cache.welcome) {
          return {
            modelName: "loading...",
            providerName: "",
            tips: [],
loaded: {
              contextFiles: [],
              tools: 0,
              commands: 0,
              skills: 0,
              extensions: 0,
              templates: 0,
            },
            recent: [],
            agenote: null,
          };
        }
        return cache.welcome;
      });
      ctx.ui.setHeader((tui, _theme) => {
        cache.tuiRef = tui as TUI;
        return welcomeFactory(tui, _theme);
      });
    }
  });

  // ── 事件监听：让 footer/header 跟随运行时变化刷新 ──────────────────

  pi.on("model_select", async (_event, ctx) => {
    cache.footer.modelName = ctx.model?.name ?? ctx.model?.id ?? "no model";
    if (cache.welcome) {
      cache.welcome.modelName = cache.footer.modelName;
      cache.welcome.providerName = ctx.model?.provider ?? "unknown";
    }
    requestRender();
  });

  pi.on("thinking_level_select", async (_event, _ctx) => {
    try {
      cache.footer.thinkingLevel = pi.getThinkingLevel();
    } catch {
      cache.footer.thinkingLevel = "off";
    }
    requestRender();
  });

  // 上下文用量变化：每次 tool_call 后刷新 footer
  pi.on("tool_call", async (_event, ctx) => {
    const usage = ctx.getContextUsage?.();
    const next = usage?.percent ?? null;
    if (next !== cache.footer.contextPercent || (usage?.tokens ?? null) !== cache.footer.contextTokens) {
      cache.footer.contextPercent = next;
      cache.footer.contextTokens = usage?.tokens ?? null;
      cache.footer.contextWindow = usage?.contextWindow ?? 0;
      requestRender();
    }
  });
}
