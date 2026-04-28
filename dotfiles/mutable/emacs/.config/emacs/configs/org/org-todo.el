;;; org-todo.el --- Org TODO 和任务管理 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 Org TODO 状态、日志记录、归档等任务管理功能。
;; 作为 org-mode.el 的扩展，延迟加载直到 org 包加载完成。
;;
;; 性能优化：通过 `:after org` 和 `:defer t` 确保任务管理逻辑不会
;; 在打开 Org 文件前被加载。
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; TODO 状态、日志、优先级、标签、归档和重排
;; ═════════════════════════════════════════════════════════════════════════════

(use-package org
  :defer t
  :after org
  :custom
  ;; TODO 状态和日志
  (org-todo-keywords
   '((sequence "TODO(t)" "NEXT(n)" "INPROGRESS(i)" "WAITING(w@/!)" "|" "DONE(d!)" "CANCELLED(c@)")))
  (org-log-done 'time)
  (org-log-into-drawer t)
  (org-log-reschedule 'note)
  (org-log-redeadline 'note)
  ;; 优先级和标签
  (org-priority-highest ?A)
  (org-priority-lowest ?E)
  (org-priority-default ?C)
  (org-tags-column -80)
  ;; 归档和重排
  (org-refile-targets '((nil :maxlevel . 3)
                        (org-agenda-files :maxlevel . 3)))
  (org-outline-path-complete-in-steps nil)
  (org-refile-use-outline-path 'file)
  (org-archive-location "%s_archive::"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 任务管理函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/org-todo-done ()
  "将当前 TODO 标记为完成。"
  (interactive)
  (org-todo 'done))

(defun custom/org-todo-todo ()
  "将当前项标记为 TODO。"
  (interactive)
  (org-todo 'todo))

(defun custom/org-todo-next ()
  "将当前项标记为 NEXT。"
  (interactive)
  (org-todo "NEXT"))

(defun custom/org-todo-inprogress ()
  "将当前项标记为 INPROGRESS。"
  (interactive)
  (org-todo "INPROGRESS"))

(defun custom/org-todo-waiting ()
  "将当前项标记为 WAITING。"
  (interactive)
  (org-todo "WAITING"))

(defun custom/org-todo-cancelled ()
  "将当前项标记为 CANCELLED。"
  (interactive)
  (org-todo "CANCELLED"))

(defun custom/org-archive-subtree ()
  "归档当前子树。"
  (interactive)
  (org-archive-subtree-default))

(defun custom/org-narrow-to-subtree ()
  "窄化到当前子树。"
  (interactive)
  (org-narrow-to-subtree))

(defun custom/org-widen ()
  "恢复视图（取消窄化）。"
  (interactive)
  (widen))

(defun custom/org-insert-heading-after ()
  "在当前标题后插入新标题。"
  (interactive)
  (org-insert-heading-after-current))

(defun custom/org-insert-todo-heading ()
  "插入 TODO 标题。"
  (interactive)
  (org-insert-todo-heading nil))

(provide 'org-todo)
;;; org-todo.el ends here
