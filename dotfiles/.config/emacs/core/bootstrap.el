;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; bootstrap.el --- 核心常量与路径 -*- lexical-binding: t; -*-

;;; Commentary:
;; 定义核心常量、路径、Guix环境检测等基础设施。
;;
;; 这个文件在启动早期加载，定义了整个配置系统的基础路径和常量。
;; 所有其他模块都依赖这里定义的常量。

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 核心路径常量
;; ═════════════════════════════════════════════════════════════════════════════

(defconst my/emacs-dir user-emacs-directory
  "Emacs 配置根目录（通常是 ~/.emacs.d/ 或 ~/.config/emacs/）。")

(defconst my/core-dir (expand-file-name "core" my/emacs-dir)
  "核心模块目录，存放基础设施代码。")

(defconst my/configs-dir (expand-file-name "configs" my/emacs-dir)
  "配置模块目录，按功能分类存放配置文件。")

;; 将 org 配置目录添加到加载路径
;; 这样可以直接 (require 'org-babel) 而不需要完整路径
(add-to-list 'load-path (expand-file-name "org" my/configs-dir))

;; ═════════════════════════════════════════════════════════════════════════════
;; Guix 环境检测
;; ═════════════════════════════════════════════════════════════════════════════

;; 检测 Guix profile 路径
;; 优先使用环境变量 GUIX_PROFILE，否则使用默认路径
(defconst my/guix-profile
  (or (getenv "GUIX_PROFILE")
      (expand-file-name "~/.guix-profile"))
  "Guix profile 路径，用于查找 Guix 安装的软件包。")

;; 检测是否在 Guix 环境中运行
;; 通过检查环境变量或 profile 目录是否存在来判断
(defconst my/in-guix-environment-p
  (or (getenv "GUIX_ENVIRONMENT")
      (file-exists-p my/guix-profile))
  "是否在 Guix 环境中运行。
如果为 t，表示当前 Emacs 运行在 Guix 管理的环境中。")

;; ═════════════════════════════════════════════════════════════════════════════
;; use-package 配置
;; ═════════════════════════════════════════════════════════════════════════════

;; 加载 use-package（由 Guix 提供）
;; use-package 是一个宏，用于声明式配置 Emacs 包
(require 'use-package)

;; 禁用自动安装包（因为使用 Guix 管理）
;; 重要：所有包必须通过 Guix 安装，不能通过 package.el
(setq use-package-always-ensure nil)

(provide 'bootstrap)
;;; bootstrap.el ends here
