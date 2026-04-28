;;; diagnostic-install.el --- 自动追踪安装 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 安装 debug-init 专用的运行期诊断增强。
;; 为所有 custom/* 公开交互式命令安装追踪 advice，
;; 以及为 load/require/hook/timer 安装上下文追踪。

;;; Code:

(require 'diagnostic-state)
(require 'diagnostic-advice)

;; ═════════════════════════════════════════════════════════════════════════════
;; 自动追踪安装
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/diag-setup-auto-trace ()
  "为所有 custom/* 公开交互式命令安装追踪 advice。

筛选条件：
- 已绑定为函数（fboundp）
- 名称以 \"custom/\" 开头（公开函数）
- 名称不以 \"custom--\" 开头（排除私有函数）
- 为交互式命令（commandp）"
  (condition-case err
      (when (and init-file-debug custom--diag-enable-auto-trace)
        (let ((count 0))
          (mapatoms
            (lambda (sym)
              (when (and (fboundp sym)
                         (string-prefix-p "custom/" (symbol-name sym))
                         (not (string-prefix-p "custom--" (symbol-name sym)))
                         (commandp sym))
                (advice-add sym :around #'custom--diag-trace-wrapper)
                (setq count (1+ count)))))
           (message "[diag:trace] 已安装 %d 个函数的追踪" count)))
      (error
        (message "[diag:trace] 自动追踪安装失败: %s" (error-message-string err)))))

(defun custom/diag-install-runtime-instrumentation ()
  "安装 debug-init 专用的运行期诊断增强。"
  (when init-file-debug
    (dolist (spec '((load . custom--diag-load-wrapper)
                    (require . custom--diag-require-wrapper)
                    (run-hooks . custom--diag-run-hooks-wrapper)
                    (run-at-time . custom--diag-run-at-time-wrapper)
                    (run-with-idle-timer . custom--diag-run-with-idle-timer-wrapper)))
      (let ((target (car spec))
            (wrapper (cdr spec)))
        (unless (advice-member-p wrapper target)
          (advice-add target :around wrapper))))
    (message "[diag:init] 已启用 load/require/hook/timer 诊断增强")))

(provide 'diagnostic-install)
;;; diagnostic-install.el ends here
