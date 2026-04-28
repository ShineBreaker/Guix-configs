;;; diagnostic-state.el --- 诊断系统状态变量 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 诊断系统的共享状态变量。所有其他诊断子模块依赖本模块。

;;; Code:

(require 'seq)

;; ═════════════════════════════════════════════════════════════════════════════
;; 结构化诊断状态
;; ═════════════════════════════════════════════════════════════════════════════

(defvar custom--diag-context-stack nil
  "当前 debug-init 诊断上下文栈。")

(defvar custom--diag-failures nil
  "当前会话收集到的结构化失败记录。")

(defvar custom--diag-debugger-active nil
  "防止诊断 debugger 递归重入。")

(defvar custom--diag-error-recorded nil
  "当前错误是否已被诊断系统记录，防止嵌套上下文重复入账。")

(defvar custom--diag-verbose nil
  "非 nil 表示输出更详细的 debug-init 诊断日志。")

(defvar custom--diag-enable-auto-trace nil
  "非 nil 表示自动追踪 `custom/' 交互命令。默认关闭以避免噪音。")

(defvar custom--diag-enable-timer-trace nil
  "非 nil 表示记录所有 timer/idle-timer 的安排日志。")

(defvar custom--diag-suppressed-timers (make-hash-table :test 'equal)
  "被聚合抑制的 timer 日志统计。")

(defconst custom--diag-noisy-timer-patterns
  '("gcmh-idle-garbage-collect"
    "blink-cursor"
    "tooltip-timeout"
    "flycheck-"
    "desktop-auto-save"
    "treemacs--follow"
    "vterm--delayed-redraw"
    "which-key--update"
    "symbol-overlay-idle-timer"
    "diff-hl--update-buffer"
    "rng-validate"
    "undo-auto--boundary-timer"
    "pfuture--delete-process")
  "常见高频 timer 名称模式，用于 debug-init 降噪。")

(provide 'diagnostic-state)
;;; diagnostic-state.el ends here
