;;; diagnostic-advice.el --- 自动追踪 advice 包装器 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 围绕 load/require/run-hooks/run-at-time/run-with-idle-timer 的
;; debug-only 上下文追踪 advice 包装器。

;;; Code:

(require 'diagnostic-state)
(require 'diagnostic-log)
(require 'diagnostic-context)

;; ═════════════════════════════════════════════════════════════════════════════
;; 自动追踪 advice 包装器
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--diag-trace-wrapper (orig-fn &rest args)
  "围绕 ORIG-FN 的追踪 advice 包装器。
ARGS 传递给原函数。不打印参数和返回值，仅记录入口、出口和耗时。"
  (let ((fn-name (symbol-name (if (symbolp orig-fn) orig-fn 'anonymous)))
        (start-time (current-time)))
    (condition-case inner-err
        (progn
          (when custom--diag-verbose
            (message "[trace] → %s" fn-name))
          (let ((result (apply orig-fn args)))
            (when custom--diag-verbose
              (message "[trace] ← %s (%.3fs)"
                       fn-name
                       (float-time (time-subtract (current-time) start-time))))
            result))
      (error
        (message "[trace] ✗ %s error: %s"
                fn-name (error-message-string inner-err))
       (signal (car inner-err) (cdr inner-err))))))

(defun custom--diag-load-wrapper (orig-fn file &rest args)
  "为 `load' 提供 debug-only 上下文追踪。"
  (if (custom--diag-internal-path-p file)
      (custom/diag-with-context 'load (format "%s" file)
        (apply orig-fn file args))
    (custom--diag-with-quiet-context 'load (format "%s" file)
      (apply orig-fn file args))))

(defun custom--diag-require-wrapper (orig-fn feature &rest args)
  "为 `require' 提供 debug-only 上下文追踪。"
  (custom--diag-with-quiet-context 'require (format "%s" feature)
    (apply orig-fn feature args)))

(defun custom--diag-run-hooks-wrapper (orig-fn &rest hooks)
  "为 `run-hooks' 提供 debug-only 上下文追踪。"
  (custom--diag-with-quiet-context
      'hook
      (mapconcat #'symbol-name hooks ", ")
    (apply orig-fn hooks)))

(defun custom--diag-run-at-time-wrapper (orig-fn time repeat function &rest args)
  "为 `run-at-time' 创建可追踪的 debug-only 回调。"
  (let ((label (format "timer[%s/%s] %s"
                       time repeat (custom--diag-describe-callable function))))
    (if (custom--diag-should-log-timer-p label)
        (custom/diag "timer" "安排定时器: %s" label)
      (custom--diag-record-suppressed-timer label))
    (apply orig-fn time repeat
            (custom--diag-wrap-function-internal 'timer label function t)
            args)))

(defun custom--diag-run-with-idle-timer-wrapper (orig-fn secs repeat function &rest args)
  "为 `run-with-idle-timer' 创建可追踪的 debug-only 回调。"
  (let ((label (format "idle-timer[%s/%s] %s"
                       secs repeat (custom--diag-describe-callable function))))
    (if (custom--diag-should-log-timer-p label)
        (custom/diag "timer" "安排空闲定时器: %s" label)
      (custom--diag-record-suppressed-timer label))
    (apply orig-fn secs repeat
            (custom--diag-wrap-function-internal 'timer label function t)
            args)))

(provide 'diagnostic-advice)
;;; diagnostic-advice.el ends here
