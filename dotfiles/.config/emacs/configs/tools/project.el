;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; project.el --- 项目管理 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Projectile 项目管理工具。

;;; Code:

;; Projectile（项目管理增强）
(use-package projectile
  :demand t
  :bind-keymap ("C-c p" . projectile-command-map)
  :custom
  (projectile-completion-system 'default)
  (projectile-enable-caching t)
  :config
  (projectile-mode 1))

(provide 'project)
;;; project.el ends here
