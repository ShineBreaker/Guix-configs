;;; org-mode.el --- Org Mode 配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Org Mode 及其生态（org-modern、org-roam 等）。

;;; Code:

;; Org Mode 基础配置
(use-package org
  :custom
  (org-directory "~/org")
  (org-agenda-files '("~/org"))
  (org-default-notes-file "~/org/notes.org")
  (org-hide-emphasis-markers t)
  (org-startup-indented t))

;; Org Modern（现代化样式）
(use-package org-modern
  :hook (org-mode . org-modern-mode))

;; Org Appear（自动显示隐藏元素）
(use-package org-appear
  :hook (org-mode . org-appear-mode))

;; Org Roam（笔记管理系统）
(use-package org-roam
  :custom
  (org-roam-directory "~/org/roam")
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n i" . org-roam-node-insert))
  :config
  (org-roam-db-autosync-mode))

(provide 'org-mode)
;;; org-mode.el ends here
