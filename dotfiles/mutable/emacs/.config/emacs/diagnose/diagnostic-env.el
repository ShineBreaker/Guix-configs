;;; diagnostic-env.el --- 环境信息快照 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 环境信息快照：Emacs 版本、系统、Guix 环境等。
;; 启动失败汇总和 timer 抑制统计。

;;; Code:

(require 'diagnostic-state)
(require 'diagnostic-context)

;; ═════════════════════════════════════════════════════════════════════════════
;; 环境信息快照
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/diag-dump-env ()
  "输出当前 Emacs 环境信息到 *Messages* 缓冲区。"
  (condition-case err
      (progn
        (message "[init:env] Emacs %s / %s / window-system: %s"
                 emacs-version system-type (or window-system "none"))
        (message "[init:env] Guix 环境: %s / Profile: %s"
                 (bound-and-true-p custom/in-guix-environment-p)
                 (bound-and-true-p custom:guix-profile))
        (message "[init:env] GUIX_ENVIRONMENT: %s"
                 (or (getenv "GUIX_ENVIRONMENT") "<未设置>"))
        (message "[init:env] features: %d 个 / load-path: %d 条"
                 (length features) (length load-path))
        (message "[init:env] GC: threshold=%s / elapsed=%.3fs / 次数=%d"
                 gc-cons-threshold
                 gc-elapsed
                 gcs-done))
    (error
     (message "[init:env] 环境快照出错: %s" (error-message-string err)))))

(defun custom/diag-summarize-failures ()
  "在启动完成时输出失败摘要。"
  (when init-file-debug
    (if custom--diag-failures
        (progn
          (message "[init:summary] 共记录 %d 个失败，详见 *Init Diagnostics*"
                   (length custom--diag-failures))
          (dolist (entry (reverse custom--diag-failures))
            (message "[init:summary] %s | %s"
                     (plist-get entry :message)
                     (custom--diag-format-context-summary
                      (plist-get entry :contexts)))))
      (message "[init:summary] 未记录到失败"))))

(defun custom/diag-summarize-timers ()
  "输出被聚合抑制的 timer 摘要。"
  (when (and init-file-debug
             (> (hash-table-count custom--diag-suppressed-timers) 0))
    (let (items)
      (maphash (lambda (label count)
                 (push (cons label count) items))
               custom--diag-suppressed-timers)
      (setq items (sort items (lambda (a b) (> (cdr a) (cdr b)))))
      (message "[diag:timer] 已聚合抑制 %d 类高频 timer：%s"
               (length items)
               (mapconcat
                (lambda (item)
                  (format "%s x%d" (car item) (cdr item)))
                (seq-take items (min 5 (length items)))
                ", ")))))

(provide 'diagnostic-env)
;;; diagnostic-env.el ends here
