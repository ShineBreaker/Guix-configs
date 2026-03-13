;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; init.el --- Emacs 主入口（Guix 版） -*- lexical-binding: t; -*-

;;; Commentary:
;; 模块化配置入口，所有包由 Guix 管理。

;;; Code:

;; 添加核心目录到加载路径
(add-to-list 'load-path (expand-file-name "core" user-emacs-directory))

;; 加载核心模块
(require 'bootstrap)
(require 'lib)
(require 'autoloads)

;; 加载配置模块
(my/load-config "system" "startup.el")
(my/load-config "system" "guix.el")

(my/load-config "ui" "appearance.el")
(my/load-config "ui" "dashboard.el")
(my/load-config "ui" "workspace.el")

(my/load-config "editor" "keybindings.el")
(my/load-config "editor" "leader.el")
(my/load-config "editor" "completion.el")
(my/load-config "editor" "editing.el")

(my/load-config "coding" "lsp.el")
(my/load-config "coding" "languages.el")

(my/load-config "tools" "git.el")
(my/load-config "tools" "project.el")
(my/load-config "tools" "terminal.el")
(my/load-config "tools" "ai.el")
(my/load-config "tools" "mail.el")
(my/load-config "tools" "calendar.el")

(my/load-config "org" "org-mode.el")

;; 启动信息
(message "[init] 配置加载完成，用时 %.2fs"
         (float-time (time-subtract after-init-time before-init-time)))

(provide 'init)
;;; init.el ends here
