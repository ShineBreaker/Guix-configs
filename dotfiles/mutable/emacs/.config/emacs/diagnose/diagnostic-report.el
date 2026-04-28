;;; diagnostic-report.el --- 通用诊断报告函数 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 通用诊断报告输出到专用缓冲区。仅在 --debug-init 模式下可用。

;;; Code:

(require 'diagnostic-state)

;; ═════════════════════════════════════════════════════════════════════════════
;; 通用诊断报告函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/diag-report (title items)
  "输出诊断报告到专用缓冲区。

TITLE 为报告标题（字符串），同时作为缓冲区名的一部分。
ITEMS 为诊断数据列表，每个元素是 (LABEL . VALUE) 对。

仅在 --debug-init 模式下可用。"
  (when init-file-debug
    (condition-case err
        (let ((buf (get-buffer-create (format "*Diagnostic: %s*" title)))
              (inhibit-read-only t))
          (with-current-buffer buf
            (erase-buffer)
            (insert (format "===== %s =====\n\n" title))
            (dolist (item items)
              (let ((label (car item))
                    (value (cdr item)))
                (insert (format "%s: %s\n" label value))))
            (display-buffer buf))
          (message "[diag:%s] 诊断报告已生成: %s" title buf))
      (error
       (message "[diag:%s] 诊断报告生成失败: %s" title (error-message-string err))))))

(provide 'diagnostic-report)
;;; diagnostic-report.el ends here
