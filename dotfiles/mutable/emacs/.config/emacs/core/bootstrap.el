;;; bootstrap.el --- 核心常量与路径 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 定义核心常量、路径、Guix环境检测等基础设施。
;;
;; 这个文件在启动早期加载，定义了整个配置系统的基础路径和常量。
;; 所有其他模块都依赖这里定义的常量。

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 核心路径常量
;; ═════════════════════════════════════════════════════════════════════════════

(defconst custom:emacs-dir user-emacs-directory
  "Emacs 配置根目录（通常是 ~/.emacs.d/ 或 ~/.config/emacs/）。")

(defconst custom:core-dir (expand-file-name "core" custom:emacs-dir)
  "核心模块目录，存放基础设施代码。")

(defconst custom:configs-dir (expand-file-name "configs" custom:emacs-dir)
  "配置模块目录，按功能分类存放配置文件。")

;; ═════════════════════════════════════════════════════════════════════════════
;; 外部路径常量
;; ═════════════════════════════════════════════════════════════════════════════

(defconst custom:tree-sitter-lib-dir
  (expand-file-name "~/.guix-home/profile/lib/tree-sitter")
  "Guix Home 的 tree-sitter 动态库目录。")

(defconst custom:org-directory (expand-file-name "~/Documents/Org/")
  "Org 文件根目录。")

(defconst custom:org-roam-directory (expand-file-name "roam" custom:org-directory)
  "Org-roam 笔记目录。")

(defconst custom:org-inbox-file (expand-file-name "inbox.org" custom:org-directory)
  "Org 收件箱文件路径。")

(defconst custom:org-default-notes-file (expand-file-name "notes/notes.org" custom:org-directory)
  "Org 默认笔记文件路径。")

(defconst custom:org-knowledge-directory (expand-file-name "experiences" custom:org-directory)
  "知识库经验卡片目录。")

(defconst custom:org-knowledge-patterns-file (expand-file-name "patterns.org" custom:org-directory)
  "知识库模式/原则文件路径。")

;; 将 org 配置目录添加到加载路径
(add-to-list 'load-path (expand-file-name "org" custom:configs-dir))

;; ═════════════════════════════════════════════════════════════════════════════
;; Guix 环境检测
;; ═════════════════════════════════════════════════════════════════════════════

;; 检测 Guix profile 路径
(defconst custom:guix-profile
  (or (getenv "GUIX_PROFILE")
      (expand-file-name "~/.guix-profile"))
  "Guix profile 路径，用于查找 Guix 安装的软件包。")

;; 检测是否在 Guix 环境中运行
(defconst custom:in-guix-environment-p
  (or (getenv "GUIX_ENVIRONMENT")
      (file-exists-p custom:guix-profile))
  "是否在 Guix 环境中运行。")

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
