// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
//
// SPDX-License-Identifier: MIT

/**
 * 多路复用器后端抽象 — 让 launcher.ts 不感知具体是 tmux 还是 herdr
 *
 * 运行时按环境变量自动选择后端（detectBackend）：
 *   - HERDR_ENV=1 → HerdrBackend（herdr pane split/run/close）
 *   - $TMUX 非空 → TmuxBackend（tmux split-window/kill-pane）
 *   - 都没有    → 抛错（atelier 必须运行在某个多路复用器内）
 *
 * 抽象的操作覆盖 launchSingle/launchParallel 的全部 pane 控制需求：
 *   currentPaneId / splitAbove / splitRight / setTitle / refocus /
 *   isAlive / kill
 *
 * 布局语义差异（接受，不抹平）：
 *   - tmux splitAbove 在主 pane 上方创建子 pane（40% 行）
 *   - herdr split 在主 pane 下方创建子 pane（ratio 0.4）
 *   两者都让子 agent 在独立 pane 跑，主 pane 保持可交互。上方/下方是
 *   纯界面差异，不影响 status.json 文件轮询（monitor.ts multiplexer 无关）。
 */

// ─── 后端接口 ─────────────────────────────────────────────────────────────

/**
 * 多路复用器后端接口。
 *
 * 所有方法同步执行（execFileSync），与原 tmux 封装一致——launchSingle 的
 * 分屏逻辑依赖顺序执行 + 立即拿到 paneId。
 */
export interface MultiplexerBackend {
  /** 后端名（"tmux" / "herdr"），用于日志诊断 */
  readonly name: "tmux" | "herdr";

  /**
   * 获取当前 pane 的 ID（调用 launchSingle 的 pane，subagent 要相对它分屏）。
   * @returns 当前 pane 的稳定 ID 字符串
   */
  currentPaneId(): string;

  /**
   * 在当前 pane 的「上方」（tmux）或「下方」（herdr）垂直分割一个新 pane，
   * 在其中运行 cmd，返回新 pane 的 ID。
   *
   * @param cmd 在新 pane 内执行的 shell 命令（subagent wrapper 调用串）
   * @param ratio 新 pane 占用的高度比例（0-1，如 0.4 = 40%）
   * @returns 新 pane 的 ID
   */
  splitAbove(cmd: string, ratio: number): string;

  /**
   * 在指定 pane 的右侧水平分割一个新 pane，在其中运行 cmd，返回新 pane ID。
   * 用于 parallel/chain 模式在顶部行内逐步扩展子 pane。
   *
   * @param targetPaneId 分割基准 pane 的 ID
   * @param cmd 新 pane 内执行的命令
   * @param ratio 新 pane 占用的宽度比例（0-1）
   * @returns 新 pane 的 ID
   */
  splitRight(targetPaneId: string, cmd: string, ratio: number): string;

  /**
   * 设置 pane 的标题/标签（用于在分屏界面识别 subagent）。
   * tmux: select-pane -T；herdr: pane rename。
   */
  setTitle(paneId: string, title: string): void;

  /**
   * 把焦点切回指定 pane（分屏结束后回主 pane）。
   * tmux: select-pane；herdr: no-op（split 时用 --no-focus，焦点从未离开）。
   */
  refocus(paneId: string): void;

  /**
   * 检查 pane 是否仍存活（用于 monitor 的 pane 死亡检测）。
   * @returns true 存活；false 已关闭
   */
  isAlive(paneId: string): boolean;

  /**
   * 终止指定 pane（用于 abort/timeout 清理）。
   * tmux: kill-pane；herdr: pane close。
   */
  kill(paneId: string): void;
}
