;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; org-mode.el --- Org Mode 基础配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; Org Mode 配置入口，加载所有 Org 相关模块。
;;
;; 模块拆分：
;; - org-mode.el    : 基础配置
;; - org-babel.el   : 文学编程 (Babel)
;; - org-export.el  : 导出功能
;; - org-todo.el    : TODO 和任务管理

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 目录设置
;; ═════════════════════════════════════════════════════════════════════════════

(defun my/ensure-org-directories ()
  "确保所有 Org 相关目录存在。"
  (dolist (dir '("~/Documents/Org/"
                 "~/Documents/Org/agenda"
                 "~/Documents/Org/notes"
                 "~/Documents/Org/roam"
                 "~/Documents/Org/babel"
                 "~/Documents/Org/tangle"))
    (let ((expanded (expand-file-name dir)))
      (unless (file-exists-p expanded)
        (make-directory expanded t)))))

(my/ensure-org-directories)

;; ═════════════════════════════════════════════════════════════════════════════
;; Org Mode 基础配置
;; ═════════════════════════════════════════════════════════════════════════════

(use-package org
  :custom
  (org-directory "~/Documents/Org/")
  (org-agenda-files '("~/Documents/Org/agenda"))
  (org-default-notes-file "~/Documents/Org/notes/notes.org")
  ;; 视觉设置
  (org-hide-emphasis-markers t)
  (org-startup-indented t)
  (org-pretty-entities t)
  (org-use-sub-superscripts '{})
  (org-cycle-separator-lines 2)
  (org-blank-before-new-entry '((heading . t) (plain-list-item . auto)))
  ;; 代码块显示
  (org-src-fontify-natively t)
  (org-src-tab-acts-natively t)
  (org-src-preserve-indentation t)
  (org-src-window-setup 'current-window)
  (org-edit-src-content-indentation 0)
  ;; 图片显示
  (org-startup-with-inline-images t)
  (org-image-actual-width '(300)))

;; ═════════════════════════════════════════════════════════════════════════════
;; UI 增强
;; ═════════════════════════════════════════════════════════════════════════════

(use-package org-modern
  :hook (org-mode . org-modern-mode)
  :custom
  (org-modern-star 'replace)
  (org-modern-hide-stars t)
  (org-modern-table nil)
  (org-modern-keyword t)
  (org-modern-todo t)
  (org-modern-tag t)
  (org-modern-block-name t)
  (org-modern-block-fringe 4))

(use-package org-appear
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autoemphasis t)
  (org-appear-autolinks t)
  (org-appear-autosubmarkers t))

;; ═════════════════════════════════════════════════════════════════════════════
;; 笔记系统
;; ═════════════════════════════════════════════════════════════════════════════

(use-package org-roam
  :custom
  (org-roam-directory "~/Documents/Org/roam")
  (org-roam-database-connector 'sqlite)
  (org-roam-completion-everywhere t)
  :config
  (org-roam-db-autosync-mode))

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载其他模块
;; ═════════════════════════════════════════════════════════════════════════════

(require 'org-babel)
(require 'org-export)
(require 'org-todo)

(provide 'org-mode)
;;; org-mode.el ends here
