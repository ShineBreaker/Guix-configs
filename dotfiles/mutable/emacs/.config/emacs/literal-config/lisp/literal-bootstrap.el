;;; literal-bootstrap.el --- 路径常量与启动期外部命令缓存 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai004@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 本配置（literal-config）的基础设施层：
;; - 集中定义所有路径常量（org 目录、guix profile、tree-sitter 库等）
;; - 启动期一次性缓存所有外部命令路径（rg / fd / git / agenote 等），
;;   遵循 doom 范式：defvar 时调 executable-find，运行时零开销。
;;
;; 加载时机：init.el 的最开始处（在任何 use-package 之前），
;; 确保后续配置可以引用 `literal:org-directory' 等常量。

;;; Code:

(require 'cl-lib)

;; ═════════════════════════════════════════════════════════════════════════════
;; 核心路径常量
;; ═════════════════════════════════════════════════════════════════════════════

(defconst literal:emacs-dir user-emacs-directory
  "本 profile 的根目录（chemacs2 已把 user-emacs-directory 指向 literal-config/）。")

(defconst literal:emacs-lisp-dir
  (expand-file-name "lisp" literal:emacs-dir)
  "外置 .el 模块目录。init.el 在加载早期把此目录加入 load-path。")

(defconst literal:org-directory
  (expand-file-name "~/Documents/Org/")
  "Org 文件根目录。")

(defconst literal:org-roam-directory
  (expand-file-name "roam" literal:org-directory)
  "Org-roam 笔记目录。")

(defconst literal:org-inbox-file
  (expand-file-name "inbox.org" literal:org-directory)
  "Org 收件箱。")

(defconst literal:org-default-notes-file
  (expand-file-name "notes/notes.org" literal:org-directory)
  "默认笔记文件。")

(defconst literal:org-knowledge-directory
  (expand-file-name "experiences" literal:org-directory)
  "知识库经验卡片目录（人类域）。")

(defconst literal:agenote-directory
  (expand-file-name "agenote" literal:org-directory)
  "agenote 子域目录（agent 写入的卡片 + index.json）。")

(defconst literal:tree-sitter-lib-dir
  (expand-file-name "~/.guix-home/profile/lib/tree-sitter")
  "Guix Home profile 的 tree-sitter 动态库目录。")

(defconst literal:guix-profile
  (or (getenv "GUIX_PROFILE")
      (expand-file-name "~/.guix-profile"))
  "Guix profile 路径。")

(defconst literal:in-guix-environment-p
  (or (getenv "GUIX_ENVIRONMENT")
      (file-exists-p literal:guix-profile))
  "是否运行在 Guix 环境中。")

;; ═════════════════════════════════════════════════════════════════════════════
;; 外部命令路径缓存（启动期一次性检测，运行时只读）
;; ═════════════════════════════════════════════════════════════════════════════
;;
;; 遵循 doom 范式：defvar 时调 executable-find，后续只读变量。
;; 避免每次使用时都搜 PATH（每次 executable-find ~10-50μs，高频场景累积可观）。
;; early-init.el 已把 GUIX_PROFILE/bin 和 ~/.local/bin 加入 exec-path，
;; 因此这里的缓存能命中 agenote / godot / dot 等用户工具。

(defconst literal:executable-rg (executable-find "rg")
  "ripgrep 路径，启动期缓存。nil 表示未安装。")

(defconst literal:executable-fd (cl-find-if #'executable-find '("fd" "fdfind"))
  "fd 路径，启动期缓存。fdfind 为 Debian/Ubuntu 包名。")

(defconst literal:executable-jq (executable-find "jq")
  "jq 路径，启动期缓存。")

(defconst literal:executable-git (executable-find "git")
  "git 路径，启动期缓存。")

(defconst literal:executable-agenote (executable-find "agenote")
  "agenote CLI 路径（知识库工具），启动期缓存。")

(defconst literal:executable-dot (executable-find "dot")
  "Graphviz dot 路径，启动期缓存。")

(defconst literal:executable-godot (executable-find "godot")
  "Godot 引擎路径，启动期缓存。")

(defconst literal:executable-fish (executable-find "fish")
  "fish shell 路径，启动期缓存。")

(defconst literal:executable-direnv (executable-find "direnv")
  "direnv 路径，启动期缓存。")

(defconst literal:executable-java (executable-find "java")
  "java 路径，启动期缓存。")

(defconst literal:executable-kotlinc (executable-find "kotlinc")
  "kotlinc 路径，启动期缓存。")

(defconst literal:executable-python
  (or (executable-find "python3") (executable-find "python"))
  "python 路径（python3 优先），启动期缓存。")

(defconst literal:executable-aspell (executable-find "aspell")
  "aspell 路径，启动期缓存。")

(defconst literal:executable-hunspell (executable-find "hunspell")
  "hunspell 路径，启动期缓存。")

(provide 'literal-bootstrap)
;;; literal-bootstrap.el ends here
