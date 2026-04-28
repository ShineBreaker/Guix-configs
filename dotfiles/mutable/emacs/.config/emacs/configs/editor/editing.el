;;; editing.el --- 编辑行为与代码可读性 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置编辑行为、括号匹配、选区扩展、Git 差异显示等。
;;
;; 文档模式自动换行：
;; markdown-mode、org-mode 等文档类 major mode 自动启用 visual-line-mode，
;; 其余模式（编程等）保持默认截断显示。

;;; Code:

;; 通用编辑习惯
(setq-default indent-tabs-mode nil
              tab-width 2
              fill-column 100
              truncate-lines t
              word-wrap nil)

;; 基础编辑功能
(electric-pair-mode 1)        ; 自动配对括号
(show-paren-mode 1)           ; 高亮匹配括号
(delete-selection-mode 1)     ; 选中后输入替换
(global-auto-revert-mode 1)   ; 自动重载外部修改

;; Expand Region - 逐步扩展/收缩选区
;; 由 `C-x s e` / `C-x s E` 触发。
(use-package expand-region
  :defer t
  :commands (er/expand-region er/contract-region))

;; 自动清理行尾空格
(use-package ws-butler
  :defer t
  :hook ((text-mode . ws-butler-mode)
         (prog-mode . ws-butler-mode)))

;; Git 差异高亮
;; GUI 模式使用 fringe 显示，终端模式使用 margin 显示
(use-package diff-hl
  :defer t
  :hook ((prog-mode . diff-hl-mode)
         (text-mode . diff-hl-mode))
  :config
  (global-diff-hl-mode 1)
  ;; 终端模式下使用 margin 方式显示 diff-hl（fringe 在终端不可用）
  (unless (display-graphic-p)
    (diff-hl-margin-mode 1)))

;; Git blame（显示当前行的提交信息）
(use-package git-messenger
  :defer t
  :bind ("C-c g b" . git-messenger:popup-message)
  :custom
  (git-messenger:show-detail t)
  (git-messenger:use-magit-popup t))

;; ═════════════════════════════════════════════════════════════════════════════
;; 文档模式自动换行
;; ═════════════════════════════════════════════════════════════════════════════

(dolist (hook '(org-mode-hook markdown-mode-hook gfm-mode-hook text-mode-hook))
  (add-hook hook #'visual-line-mode))

(provide 'editing)
;;; editing.el ends here
