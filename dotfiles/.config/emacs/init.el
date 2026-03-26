;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; init.el --- Emacs 主入口（Guix 版） -*- lexical-binding: t; -*-

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

;; 加载核心模块（顺序很重要）
(require 'bootstrap)  ; 路径常量、Guix 环境检测
(require 'lib)        ; 工具函数

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载系统配置
;; ═════════════════════════════════════════════════════════════════════════════

(my/load-config "system" "startup.el")  ; 启动优化、GC、持久化
(my/load-config "system" "guix.el")     ; Guix 环境集成

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载 UI 配置
;; ═════════════════════════════════════════════════════════════════════════════

(my/load-config "ui" "appearance.el")  ; 主题、字体、行号
(my/load-config "ui" "dashboard.el")   ; 启动仪表盘
(my/load-config "ui" "workspace.el")   ; 工作区布局、文件树
(my/load-config "ui" "sidebar.el")     ; 右侧功能栏

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载编辑器配置
;; ═════════════════════════════════════════════════════════════════════════════

(my/load-config "editor" "keybindings.el")  ; Evil 模式、快捷键
(my/load-config "editor" "leader.el")       ; Leader 键系统
(my/load-config "editor" "help.el")         ; 帮助系统
(my/load-config "editor" "completion.el")   ; 补全框架
(my/load-config "editor" "editing.el")      ; 编辑增强

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载编程配置
;; ═════════════════════════════════════════════════════════════════════════════

(my/load-config "coding" "lsp.el")       ; LSP 客户端
(my/load-config "coding" "languages.el") ; 语言特定配置

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载工具配置
;; ═════════════════════════════════════════════════════════════════════════════

(my/load-config "tools" "git.el")      ; Git 版本控制
(my/load-config "tools" "project.el")  ; 项目管理
(my/load-config "tools" "terminal.el") ; 终端模拟器
(my/load-config "tools" "mail.el")     ; 邮件客户端
(my/load-config "tools" "calendar.el") ; 日历

;; ═════════════════════════════════════════════════════════════════════════════
;; 加载 Org Mode 配置
;; ═════════════════════════════════════════════════════════════════════════════

(my/load-config "org" "org-mode.el")  ; Org Mode 及相关模块
;; ═════════════════════════════════════════════════════════════════════════════
;; 启动完成信息
;; ═════════════════════════════════════════════════════════════════════════════

;; 在启动完成后显示启动时间
(add-hook 'emacs-startup-hook
          (lambda ()
            (message "[init] Emacs 启动完成，用时 %.2fs"
                     (float-time (time-subtract after-init-time before-init-time)))))

(provide 'init)
;;; init.el ends here
