;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; org-mode.el --- Org Mode 配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Org Mode 及其生态（org-modern、org-roam 等）。

;;; Code:

;; 确保 Org 目录存在
(defun my/ensure-org-directories ()
  "确保所有 Org 相关目录存在。"
  (dolist (dir '("~/Documents/Org/"
                 "~/Documents/Org/agenda"
                 "~/Documents/Org/notes"
                 "~/Documents/Org/roam"))
    (let ((expanded (expand-file-name dir)))
      (unless (file-exists-p expanded)
        (make-directory expanded t)))))

(my/ensure-org-directories)

;; Org Mode 基础配置
(use-package org
  :custom
  (org-directory "~/Documents/Org/")
  (org-agenda-files '("~/Documents/Org/agenda"))
  (org-default-notes-file "~/Documents/Org/notes/notes.org")
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
  (org-roam-directory "~/Documents/Org/roam")
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n i" . org-roam-node-insert))
  :config
  (org-roam-db-autosync-mode))

(provide 'org-mode)
;;; org-mode.el ends here
