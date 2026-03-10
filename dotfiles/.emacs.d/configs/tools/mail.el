;;; mail.el --- 邮件客户端 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Notmuch 邮件客户端。

;;; Code:

;; Notmuch（邮件客户端）
(use-package notmuch
  :commands notmuch
  :bind ("C-c m" . notmuch)
  :custom
  (notmuch-search-oldest-first nil))

(provide 'mail)
;;; mail.el ends here
