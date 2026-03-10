;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; git.el --- Git 版本控制 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Magit（Git 界面）和相关工具。

;;; Code:

;; Magit（强大的 Git 界面）
(use-package magit
  :bind ("C-x g" . magit-status)
  :custom
  (magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1))

;; Magit Todos（显示代码中的 TODO）
(use-package magit-todos
  :after magit
  :config
  (magit-todos-mode 1))

(provide 'git)
;;; git.el ends here
