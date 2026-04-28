;;; init.el --- Emacs 主入口（Guix 版） -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 模块化配置入口，所有包由 Guix 管理。
;;
;; 加载顺序：
;; 1. early-init.el (自动加载，在 GUI 初始化前)
;; 2. core/ - 核心基础设施
;; 3. configs/ - 按类别组织的功能模块

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载核心模块
;; ═════════════════════════════════════════════════════════════════════════════

;; 添加核心目录到加载路径
(add-to-list 'load-path (expand-file-name "core" user-emacs-directory))
(add-to-list 'load-path (expand-file-name "diagnose" user-emacs-directory))

;; 加载核心模块（顺序很重要）
(when init-file-debug
  (message "[init:core] 加载 bootstrap"))
(require 'bootstrap)   ; 路径常量、Guix 环境检测
(when init-file-debug
  (message "[init:core] 加载 lib"))
(require 'lib)         ; 工具函数
(when init-file-debug
  (message "[init:core] 加载 diagnostic"))
(require 'diagnostic)  ; 诊断基础设施（必须在所有配置模块之前）

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载系统配置
;; ═════════════════════════════════════════════════════════════════════════════

(custom/diag-with-context 'phase "system"
  (custom/diag "phase" "═══ 系统配置 ═══")
  (custom/load-config "system" "startup.el")
  (custom/load-config "system" "guix.el"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载 UI 配置
;; ═════════════════════════════════════════════════════════════════════════════

(custom/diag-with-context 'phase "ui"
  (custom/diag "phase" "═══ UI 配置 ═══")
  (custom/load-config "ui" "appearance.el")
  (custom/load-config "ui" "color-scheme.el")
  (custom/load-config "ui" "dashboard.el")
  (custom/load-config "ui" "workspace.el"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载语言声明（供 editor/coding 共享）
;; ═════════════════════════════════════════════════════════════════════════════

(custom/diag-with-context 'phase "languages"
  (custom/diag "phase" "═══ 语言声明 ═══")
  (custom/load-config "coding" "languages.el"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载本地化配置
;; ═════════════════════════════════════════════════════════════════════════════

(custom/diag-with-context 'phase "i18n"
  (custom/diag "phase" "═══ 本地化配置 ═══")
  (custom/load-config "i18n" "context-menu.el")
  (custom/load-config "i18n" "which-key-descriptions.el"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载编辑器配置
;; ═════════════════════════════════════════════════════════════════════════════

(custom/diag-with-context 'phase "editor"
  (custom/diag "phase" "═══ 编辑器配置 ═══")
  (custom/load-config "editor" "keybindings.el")
  (custom/load-config "editor" "prefix-keymaps.el")
  (custom/load-config "editor" "mouse.el")
  (custom/load-config "editor" "help.el")
  (custom/load-config "editor" "completion.el")
  (custom/load-config "editor" "folding.el")
  (custom/load-config "editor" "navigation.el")
  (custom/load-config "editor" "editing.el")
  (custom/load-config "editor" "undo.el"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载编程配置
;; ═════════════════════════════════════════════════════════════════════════════

(custom/diag-with-context 'phase "coding"
  (custom/diag "phase" "═══ 编程配置 ═══")
  (custom/load-config "coding" "env.el")
  (custom/load-config "coding" "lsp.el")
  (custom/load-config "coding" "format.el")
  (custom/load-config "coding" "flycheck.el"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载工具配置
;; ═════════════════════════════════════════════════════════════════════════════

(custom/diag-with-context 'phase "tools"
  (custom/diag "phase" "═══ 工具配置 ═══")
  (custom/load-config "tools" "git.el")
  (custom/load-config "tools" "debugger.el")
  (custom/load-config "tools" "project.el")
  (custom/load-config "tools" "terminal.el")
  (custom/load-config "tools" "pdf.el")
  (custom/load-config "tools" "mail.el")
  (custom/load-config "tools" "calendar.el")
  (custom/load-config "tools" "games.el"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载 Org Mode 配置
;; ═════════════════════════════════════════════════════════════════════════════

(custom/diag-with-context 'phase "org"
  (custom/diag "phase" "═══ Org Mode 配置 ═══")
  (custom/load-config "org" "org-mode.el"))
;; ═════════════════════════════════════════════════════════════════════════════
;; 启动完成信息
;; ═════════════════════════════════════════════════════════════════════════════

;; 在启动完成后显示启动时间
(add-hook 'emacs-startup-hook
          (lambda ()
            (custom/diag-with-context 'phase "startup-hook"
              (message "[init] Emacs 启动完成，用时 %.2fs"
                       (float-time (time-subtract after-init-time before-init-time))))))

(provide 'init)
;;; init.el ends here
