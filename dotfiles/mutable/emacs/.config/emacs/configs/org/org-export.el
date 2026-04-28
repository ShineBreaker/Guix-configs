;;; org-export.el --- Org 导出配置 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 Org 导出功能，支持 Markdown、HTML、LaTeX 等格式。
;; 作为 org-mode.el 的扩展，延迟加载直到 org 包加载完成。
;;
;; 性能优化：通过 `:after org` 确保导出格式相关的库（ox-gfm、htmlize）
;; 仅在 Org 环境下按需初始化。
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 基础导出设置
;; ═════════════════════════════════════════════════════════════════════════════

(use-package org
  :defer t
  :after org
  :custom
  (org-export-coding-system 'utf-8)
  (org-export-backends '(ascii html md latex odt org))
  (org-export-with-sub-superscripts nil))

;; ═════════════════════════════════════════════════════════════════════════════
;; Markdown 导出 (ox-gfm)
;; ═════════════════════════════════════════════════════════════════════════════

(use-package ox-gfm
  :defer t
  :after org)

;; ═════════════════════════════════════════════════════════════════════════════
;; HTML 代码高亮
;; ═════════════════════════════════════════════════════════════════════════════

(use-package htmlize
  :defer t
  :after org)

;; ═════════════════════════════════════════════════════════════════════════════
;; 导出工具函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/org-export-to-markdown ()
  "导出当前 Org 文件为 Markdown。"
  (interactive)
  (org-gfm-export-to-markdown))

(defun custom/org-export-to-html ()
  "导出当前 Org 文件为 HTML。"
  (interactive)
  (org-html-export-to-html))

(defun custom/org-export-to-pdf ()
  "导出当前 Org 文件为 PDF。"
  (interactive)
  (org-latex-export-to-pdf))

(provide 'org-export)
;;; org-export.el ends here
