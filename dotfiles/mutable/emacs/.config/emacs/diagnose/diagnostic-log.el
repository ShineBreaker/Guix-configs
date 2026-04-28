;;; diagnostic-log.el --- 条件日志宏 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; `custom/diag' 宏：仅在 --debug-init 激活时输出诊断消息。
;; 非 debug 模式下参数不被求值，实现真正零开销。

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 条件日志宏
;; ═════════════════════════════════════════════════════════════════════════════

(defmacro custom/diag (category format-string &rest args)
  "当 --debug-init 激活时输出诊断消息。

CATEGORY 为日志类别（如 \"workspace\"、\"ai\"）。
FORMAT-STRING 和 ARGS 传给 `format'。

当 `init-file-debug' 为 nil 时，参数不被求值，实现真正零开销。"
  `(when init-file-debug
     (condition-case err
         (message "[diag:%s] %s" ,category (format ,format-string ,@args))
       (error
        (message "[diag:%s] <format-error: %s>" ,category (error-message-string err))))))

(provide 'diagnostic-log)
;;; diagnostic-log.el ends here
