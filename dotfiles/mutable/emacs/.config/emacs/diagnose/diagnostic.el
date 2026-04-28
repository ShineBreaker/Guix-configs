;;; diagnostic.el --- 诊断基础设施主入口 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 自包含的诊断框架模块，仅使用 Emacs 内置函数。
;; 仅在 emacs --debug-init 时激活，正常运行时零开销。
;;
;; 组成部分：
;; - custom/diag 宏：条件日志输出到 *Messages* 缓冲区
;; - custom/diag-with-context：为关键调用建立上下文栈
;; - custom/diag-wrap-function：为 hook/timer/callback 返回 debug-only 包装器
;; - custom/diag-dump-env：环境信息快照（Emacs 版本、系统、Guix 环境等）
;; - custom/diag-setup-auto-trace：自动追踪所有 custom/* 交互式命令的入口/出口/耗时
;;
;; 核心目标：
;; - 吐出"哪个阶段 -> 哪个模块 -> 哪个调用"出错的证据链
;; - 在保留 Emacs 原生 debugger/backtrace 的同时，把上下文汇总到专用报告缓冲区
;; - 覆盖 load/require/run-hooks/run-at-time/run-with-idle-timer 等关键边界
;;
;; 诊断类别前缀：
;; - [init:phase]   — 定位加载到哪个阶段
;; - [init:load]    — 查看哪些模块加载失败（✗ 标记）
;; - [init:env]     — 检查环境配置是否正确
;; - [init:error]   — 真正的失败摘要（错误消息、上下文链、报告位置）
;; - [init:summary] — 启动完成后的失败汇总
;; - [diag:*]       — 查看特定模块的运行状态
;; - [trace]        — 查看函数调用链路
;;
;; 使用方法：
;; 1. 启动调试：emacs --debug-init
;; 2. 查看 *Messages* 中的上下文链和失败摘要
;; 3. 查看 *Init Diagnostics* 缓冲区中的完整报告与 backtrace
;; 4. 新增关键路径时，用 custom/diag-with-context 或 custom/diag-wrap-function 接入

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载子模块（按依赖顺序）
;; ═════════════════════════════════════════════════════════════════════════════

(require 'diagnostic-state)
(require 'diagnostic-log)
(require 'diagnostic-context)
(require 'diagnostic-env)
(require 'diagnostic-advice)
(require 'diagnostic-report)
(require 'diagnostic-install)

;; ═════════════════════════════════════════════════════════════════════════════
;; 调试模式增强
;; ═════════════════════════════════════════════════════════════════════════════

(when init-file-debug
  (setq message-log-max 16384
        debug-ignored-errors nil
        use-package-verbose t
        use-package-compute-statistics t))

(defvar use-package-verbose)
(defvar use-package-compute-statistics)

;; ═════════════════════════════════════════════════════════════════════════════
;; Hook 注册
;; ═════════════════════════════════════════════════════════════════════════════

(when init-file-debug
  (custom/diag-install-runtime-instrumentation)
  (add-hook 'emacs-startup-hook #'custom/diag-dump-env t)
  (add-hook 'emacs-startup-hook #'custom/diag-setup-auto-trace t)
  (add-hook 'emacs-startup-hook #'custom/diag-summarize-timers t)
  (add-hook 'emacs-startup-hook #'custom/diag-summarize-failures t))

(provide 'diagnostic)
;;; diagnostic.el ends here
