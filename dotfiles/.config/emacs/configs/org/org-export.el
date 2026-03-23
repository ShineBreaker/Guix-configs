;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; org-export.el --- Org 导出配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Org 导出功能，支持 Markdown、HTML、LaTeX 等格式。

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 基础导出设置
;; ═════════════════════════════════════════════════════════════════════════════

(use-package org
  :custom
  (org-export-coding-system 'utf-8)
  (org-export-backends '(ascii html md latex odt org))
  (org-export-with-sub-superscripts nil))

;; ═════════════════════════════════════════════════════════════════════════════
;; Markdown 导出 (ox-gfm)
;; ═════════════════════════════════════════════════════════════════════════════

(use-package ox-gfm
  :after org
  :config
  (eval-after-load "ox"
    '(require 'ox-gfm nil t)))

;; ═════════════════════════════════════════════════════════════════════════════
;; HTML 代码高亮
;; ═════════════════════════════════════════════════════════════════════════════

(use-package htmlize
  :after org)

;; ═════════════════════════════════════════════════════════════════════════════
;; 导出工具函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun my/org-export-to-markdown ()
  "导出当前 Org 文件为 Markdown。"
  (interactive)
  (org-gfm-export-to-markdown))

(defun my/org-export-to-html ()
  "导出当前 Org 文件为 HTML。"
  (interactive)
  (org-html-export-to-html))

(defun my/org-export-to-pdf ()
  "导出当前 Org 文件为 PDF。"
  (interactive)
  (org-latex-export-to-pdf))

(provide 'org-export)
;;; org-export.el ends here
