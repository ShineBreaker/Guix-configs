;;; mail.el --- 邮件客户端 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 Notmuch 邮件客户端。
;;
;; Troubleshooting：
;; - Notmuch 无法启动 → 确保已安装：guix install notmuch
;; - 首次使用需要初始化：notmuch setup && notmuch new

;;; Code:

;; Notmuch（邮件客户端）
(use-package notmuch
  :commands notmuch
  :custom
  (notmuch-search-oldest-first nil))

(provide 'mail)
;;; mail.el ends here
