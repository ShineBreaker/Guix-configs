;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; editing.el --- 编辑行为与代码可读性 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置编辑行为、括号匹配、Git 差异显示等。

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

;; 自动清理行尾空格
(use-package ws-butler
  :hook ((text-mode . ws-butler-mode)
         (prog-mode . ws-butler-mode)))

;; 彩色括号
(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; Git 差异高亮
(use-package diff-hl
  :hook ((prog-mode . diff-hl-mode)
         (text-mode . diff-hl-mode)
         (dired-mode . diff-hl-dired-mode))
  :config
  (global-diff-hl-mode 1))

;; Git blame（显示当前行的提交信息）
(use-package git-messenger
  :bind ("C-c g b" . git-messenger:popup-message)
  :custom
  (git-messenger:show-detail t)
  (git-messenger:use-magit-popup t))

;; Sticky 函数头（显示当前函数名）
(use-package stickyfunc-enhance
  :hook (prog-mode . (lambda ()
                       (when (derived-mode-p 'c-mode 'c-ts-mode
                                             'c++-mode 'c++-ts-mode
                                             'python-mode 'python-ts-mode
                                             'emacs-lisp-mode)
                         (ignore-errors (semantic-mode 1)
                                        (semantic-stickyfunc-mode 1))))))

(provide 'editing)
;;; editing.el ends here
