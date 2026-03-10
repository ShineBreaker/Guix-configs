;;; dashboard.el --- 启动仪表盘配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置启动仪表盘，集成文件管理器和常用功能入口。

;;; Code:

(use-package dashboard
  :custom
  (dashboard-startup-banner 'official)
  (dashboard-set-navigator t)
  (dashboard-items '((recents   . 10)
                     (projects  . 8)
                     (bookmarks . 8)))
  (dashboard-set-heading-icons t)
  (dashboard-set-file-icons t)
  :config
  (dashboard-setup-startup-hook))

(provide 'dashboard)
;;; dashboard.el ends here
