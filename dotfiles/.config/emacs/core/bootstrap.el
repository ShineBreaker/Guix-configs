;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; bootstrap.el --- 核心常量与路径 -*- lexical-binding: t; -*-

;;; Commentary:
;; 定义核心常量、路径、Guix环境检测等基础设施。

;;; Code:

;; 核心路径常量
(defconst my/emacs-dir user-emacs-directory
  "Emacs 配置根目录。")

(defconst my/core-dir (expand-file-name "core" my/emacs-dir)
  "核心模块目录。")

(defconst my/configs-dir (expand-file-name "configs" my/emacs-dir)
  "配置模块目录。")

;; 将配置子目录添加到加载路径
(add-to-list 'load-path (expand-file-name "org" my/configs-dir))

;; Guix 环境检测
(defconst my/guix-profile
  (or (getenv "GUIX_PROFILE")
      (expand-file-name "~/.guix-profile"))
  "Guix profile 路径。")

(defconst my/in-guix-environment-p
  (or (getenv "GUIX_ENVIRONMENT")
      (file-exists-p my/guix-profile))
  "是否在 Guix 环境中运行。")

;; 确保 use-package 可用（Guix 已安装）
(require 'use-package)
(setq use-package-always-ensure nil) ; Guix 管理包，禁用自动安装

(provide 'bootstrap)
;;; bootstrap.el ends here
