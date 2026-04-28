;;; debugger.el --- DAP 调试器配置 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 dape（Debug Adapter Protocol for Emacs）调试器。
;;
;; 功能：
;; - 基于 DAP 协议的通用调试前端，支持多种语言
;; - 断点管理（设置/清除/条件断点）
;; - 单步调试（跳过/进入/跳出）
;; - 变量悬停查看
;; - 调试日志查看
;;
;; 快捷键前缀：`C-c d`
;; - `C-c d b` — 设置/取消断点
;; - `C-c d B` — 清除所有断点
;; - `C-c d d` — 开始调试
;; - `C-c d n` — 单步跳过
;; - `C-c d s` — 单步进入
;; - `C-c d o` — 单步跳出
;; - `C-c d c` — 继续运行
;; - `C-c d q` — 停止调试
;; - `C-c d r` — 重启调试
;; - `C-c d l` — 查看日志

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; Dape - DAP 调试器
;; ═════════════════════════════════════════════════════════════════════════════

(use-package dape
  :defer t
  :commands (dape dape-breakpoint-toggle dape-breakpoint-remove-all
             dape-next dape-step-in dape-step-out dape-continue
             dape-quit dape-restart dape-view-log)
  :bind (("C-c d b" . dape-breakpoint-toggle)
         ("C-c d B" . dape-breakpoint-remove-all)
         ("C-c d d" . dape)
         ("C-c d n" . dape-next)
         ("C-c d s" . dape-step-in)
         ("C-c d o" . dape-step-out)
         ("C-c d c" . dape-continue)
         ("C-c d q" . dape-quit)
         ("C-c d r" . dape-restart)
         ("C-c d l" . dape-view-log))
  :config
  ;; 启用断点高亮和悬停提示
  (dape-breakpoint-global-mode 1)
  (dape-tooltip-mode 1))

(provide 'debugger)
;;; debugger.el ends here
