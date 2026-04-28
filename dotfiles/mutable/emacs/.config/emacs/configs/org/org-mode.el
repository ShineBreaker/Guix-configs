;;; org-mode.el --- Org Mode 基础配置 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; Org Mode 配置入口，加载所有 Org 相关模块。
;;
;; 性能优化：通过 `autoload` 延迟加载 Babel、Export 和 TODO 扩展，
;; 仅在执行对应命令（如 `org-agenda` 或 `org-roam` 快捷键）时激活核心环境。
;;
;; 文件位置：
;; - Org 文件目录：~/Documents/Org/
;; - Org-roam 笔记：~/Documents/Org/roam/
;;
;; 模块拆分：
;; - org-mode.el       : 基础配置（本文件）
;; - org-babel.el      : 文学编程 (Babel)
;; - org-export.el     : 导出功能
;; - org-todo.el       : TODO 和任务管理
;; - org-knowledge.el  : 人机协作知识库
;;
;; 集成：
;; - Calfw: 日历视图
;; - Org-roam: 笔记网络
;;
;; 终端模式适配：
;; - TAB 键：终端下 TAB 和 C-i 同键码（均为 [9]），通过显式绑定确保 org-cycle
;;   在 GUI/TTY 与 daemon/client 场景都稳定工作。
;; - org-modern-block-fringe：终端无 fringe，禁用。
;; - org-startup-with-inline-images：动态检查，daemon 模式下每个 frame 独立判断。
;; - 新特性：org-startup-folded 设置为 'overview，使打开 Org 文件时默认仅显示一级标题，其余折叠。
;; - 使用方法：用户仍可通过 TAB 或 org-cycle 展开/折叠子标题，行为保持不变。
;; - 影响范围：此为对所有 Org 文件的默认行为，除非格在文件中覆盖该变量。
;; - org-modern 其他视觉元素：Nerd Font 字符替代 Unicode 符号。
;;
;; Troubleshooting：
;; - Org-roam 数据库错误 → M-x org-roam-db-sync
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 目录设置
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--ensure-org-directories ()
  "确保所有 Org 相关目录存在。"
  (dolist (dir (list custom:org-directory
                     (expand-file-name "agenda" custom:org-directory)
                     (expand-file-name "notes" custom:org-directory)
                     custom:org-roam-directory
                     (expand-file-name "babel" custom:org-directory)
                     (expand-file-name "tangle" custom:org-directory)))
    (unless (file-exists-p dir)
      (make-directory dir t))))

;; 延迟到空闲时创建目录，避免阻塞启动
(run-with-idle-timer 2 nil #'custom--ensure-org-directories)

;; ═════════════════════════════════════════════════════════════════════════════
;; Org Mode 基础配置
;; ═════════════════════════════════════════════════════════════════════════════

(use-package org
  :custom
  (org-directory custom:org-directory)
  (org-agenda-files (list (expand-file-name "agenda" custom:org-directory)))
  (org-default-notes-file custom:org-default-notes-file)
  ;; 视觉设置
  (org-hide-emphasis-markers t)
  (org-startup-indented t)
  (org-pretty-entities t)
  (org-use-sub-superscripts '{})
  (org-cycle-separator-lines 2)
  (org-startup-folded 'overview)
  (org-blank-before-new-entry '((heading . t) (plain-list-item . auto)))
  ;; 代码块显示
  (org-src-fontify-natively t)
  (org-src-tab-acts-natively t)
  (org-src-preserve-indentation t)
  (org-src-window-setup 'current-window)
  (org-edit-src-content-indentation 0)
  (org-image-actual-width '(300))
  :config
  ;; 图片显示：动态检查，确保 daemon 模式下每个 frame 正确判断
  ;; （:custom 中的值在 daemon 启动时固定，可能为 nil；此处每次打开 org 文件时重新评估）
  (defun custom--org-toggle-inline-images ()
    "根据当前 frame 的图形能力设置 org-startup-with-inline-images。"
    (setq-local org-startup-with-inline-images (display-graphic-p)))
  (add-hook 'org-mode-hook #'custom--org-toggle-inline-images)
  ;; ═══════════════════════════════════════════════════════════════════════════
  ;; TAB 键显式绑定
  ;; ═══════════════════════════════════════════════════════════════════════════
  ;; 终端下 TAB 和 C-i 共享同一键码 [9]，在 daemon/client 混合场景下
  ;; 显式绑定能避免不同输入层导致的 org-cycle 偶发失效。
  (define-key org-mode-map (kbd "TAB") #'org-cycle)
  (define-key org-mode-map (kbd "<backtab>") #'org-shifttab))

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
  ;; 终端下禁用 fringe 块标记（终端无 fringe）
  (org-modern-block-fringe (if (display-graphic-p) 4 nil)))

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
  (org-roam-directory custom:org-roam-directory)
  (org-roam-database-connector 'sqlite)
  (org-roam-completion-everywhere t)
  :config
  (org-roam-db-autosync-mode))

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载其他模块
;; ═════════════════════════════════════════════════════════════════════════════

;; 延迟加载扩展模块，在首次使用时自动加载
(autoload 'custom/org-babel-execute-current-block "org-babel" "执行当前代码块" t)
(autoload 'custom/org-babel-tangle-file "org-babel" "Tangle 整个文件" t)
(autoload 'custom/org-todo-done "org-todo" "将当前 TODO 标记为完成" t)
(autoload 'custom/org-todo-todo "org-todo" "将当前项标记为 TODO" t)
(autoload 'custom/org-export-to-markdown "org-export" "导出当前 Org 文件为 Markdown" t)
(autoload 'custom/org-export-to-html "org-export" "导出当前 Org 文件为 HTML" t)
(autoload 'custom/org-export-to-pdf "org-export" "导出当前 Org 文件为 PDF" t)

;; 通过 :after org hook 在 org-mode 加载后自动加载扩展配置
(with-eval-after-load 'org
  (require 'org-babel)
  (require 'org-export)
  (require 'org-todo)
  (require 'org-knowledge))

(provide 'org-mode)
;;; org-mode.el ends here
