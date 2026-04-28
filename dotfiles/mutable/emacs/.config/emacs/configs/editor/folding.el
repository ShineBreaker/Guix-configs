;;; folding.el --- 代码折叠配置 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 基于 origami + origami-ts (Tree-sitter) 的代码折叠。
;;
;; 支持的 major mode 列表由 `configs/coding/languages.el' 统一维护，
;; 本文件只负责消费 `custom:language-origami-ts-modes' 并启用折叠逻辑。
;;
;; 操作方式：
;; - `C-c z a/c/o/m/r`: 折叠主入口
;; - `TAB`: 在 Org / 编程模式下按上下文切换折叠或缩进
;; - Org Mode 保持原有 org-cycle，不使用 origami

;;; Code:

;; 由 languages.el 集中维护；此处声明以兼容单独加载 folding.el 的场景。
(defvar custom:language-origami-ts-modes nil)

;; ═════════════════════════════════════════════════════════════════════════════
;; Origami 代码折叠框架
;; ═════════════════════════════════════════════════════════════════════════════

;; Origami 是可扩展的代码折叠框架
;; origami-ts 提供基于 Tree-sitter 的通用解析器，精确折叠函数、类等语法结构
(use-package origami
  :defer t
  :config
  (dolist (mode custom:language-origami-ts-modes)
    (add-hook (intern (format "%s-hook" mode)) #'origami-mode))
  ;; 加载 origami-ts 并为所有 Tree-sitter 模式注册解析器
  ;; origami-ts-parser 是 origami 内部调用的函数符号，直接注册而非调用
  (when (require 'origami-ts nil t)
    (dolist (mode custom:language-origami-ts-modes)
      (add-to-list 'origami-parser-alist (cons mode #'origami-ts-parser)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 手动折叠切换
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/code-fold-tab-dwim ()
  "根据模式智能切换折叠或执行默认操作。
Org 模式使用 org-cycle，编程模式使用 origami 折叠，其他模式执行默认缩进。"
  (interactive)
  (cond
   ;; Org Mode 保持原有行为
   ((derived-mode-p 'org-mode)
    (org-cycle))
   ;; 支持 origami 的编程模式
   ((and (bound-and-true-p origami-mode)
         (fboundp 'origami-toggle-node))
    (origami-toggle-node (current-buffer) (point)))
   ;; 其他情况执行默认行为
   (t
    (indent-for-tab-command))))

(defun custom/code-fold-close ()
  "关闭当前代码块。"
  (interactive)
  (cond
   ((and (bound-and-true-p origami-mode)
         (fboundp 'origami-close-node))
    (origami-close-node (current-buffer) (point)))
   ((fboundp 'hs-hide-block)
    (hs-hide-block))
   (t
    (message "未启用代码折叠"))))

(defun custom/code-fold-open ()
  "打开当前代码块。"
  (interactive)
  (cond
   ((and (bound-and-true-p origami-mode)
         (fboundp 'origami-open-node))
    (origami-open-node (current-buffer) (point)))
   ((fboundp 'hs-show-block)
    (hs-show-block))
   (t
    (message "未启用代码折叠"))))

(defun custom/code-fold-toggle ()
  "切换当前代码块的折叠状态。"
  (interactive)
  (cond
   ((and (bound-and-true-p origami-mode)
         (fboundp 'origami-toggle-node))
    (origami-toggle-node (current-buffer) (point)))
   (t
    (message "未启用代码折叠"))))

(defun custom/code-fold-all ()
  "折叠当前缓冲区的所有代码块。"
  (interactive)
  (cond
   ((and (bound-and-true-p origami-mode)
         (fboundp 'origami-close-all-nodes))
    (origami-close-all-nodes (current-buffer)))
   (t
    (message "未启用代码折叠"))))

(defun custom/code-unfold-all ()
  "展开当前缓冲区的所有代码块。"
  (interactive)
  (cond
   ((and (bound-and-true-p origami-mode)
         (fboundp 'origami-open-all-nodes))
    (origami-open-all-nodes (current-buffer)))
   (t
    (message "未启用代码折叠"))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 非单一总前缀的 Vim 缩写式折叠快捷键
;; ═════════════════════════════════════════════════════════════════════════════

(global-set-key (kbd "C-c z a") #'custom/code-fold-toggle)
(global-set-key (kbd "C-c z c") #'custom/code-fold-close)
(global-set-key (kbd "C-c z o") #'custom/code-fold-open)
(global-set-key (kbd "C-c z m") #'custom/code-fold-all)
(global-set-key (kbd "C-c z r") #'custom/code-unfold-all)

(provide 'folding)
;;; folding.el ends here
