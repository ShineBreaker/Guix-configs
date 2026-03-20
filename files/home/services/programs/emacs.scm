;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %emacs-packages-list
  (cons* (specs->pkgs+out
          ;; --- Emacs 核心与 Lisp ---
          "emacs-pgtk"
          "sbcl"
          "emacs-use-package"
          "emacs-general"

          ;; --- 补全与迷你缓冲区 ---
          "emacs-vertico"
          "emacs-marginalia"
          "emacs-orderless"
          "emacs-consult"
          "emacs-embark"
          "emacs-corfu"

          ;; --- Evil 模式（Vim 模拟）---
          "emacs-evil"
          "emacs-evil-collection"

          ;; --- 界面与外观 ---
          "emacs-dashboard"
          "emacs-doom-modeline"
          "emacs-ef-themes"
          "emacs-kind-icon"
          "emacs-nerd-icons"
          "emacs-which-key"
          "emacs-minimap"
          "emacs-rainbow-delimiters"
          "emacs-treemacs"
          "emacs-treemacs-nerd-icons"
          "emacs-diff-hl"
          "emacs-stickyfunc-enhance"
          "emacs-ws-butler"

          ;; --- 开发工具 ---
          "emacs-vterm"
          "emacs-yasnippet"
          "emacs-yasnippet-snippets"
          "emacs-rg"

          ;; --- 编程语言支持 ---
          "emacs-kotlin-mode"
          "emacs-rust-mode"
          "emacs-zig-mode"
          "emacs-typescript-mode"
          "emacs-web-mode"
          "emacs-json-mode"
          "emacs-markdown-mode"
          "emacs-sly"
          "emacs-geiser"
          "emacs-geiser-guile"

          ;; --- Git 集成 ---
          "emacs-magit"
          "emacs-magit-todos"
          "emacs-git-messenger"

          ;; --- 项目管理 ---
          "emacs-projectile"

          ;; --- Org Mode 生态 ---
          "emacs-org-modern"
          "emacs-org-roam"
          "emacs-org-appear"

          ;; --- 帮助与文档 ---
          "emacs-helpful"

          ;; --- 邮件与日历 ---
          "emacs-notmuch"
          "emacs-calfw"

          ;; --- 环境与工具 ---
          "emacs-no-littering"
          "emacs-spinner"
          "emacs-yaml"

          ;; --- Tree-sitter（语法解析）---
          "tree-sitter"
          "tree-sitter-bash"
          "tree-sitter-c"
          "tree-sitter-cpp"
          "tree-sitter-css"
          "tree-sitter-dockerfile"
          "tree-sitter-go"
          "tree-sitter-html"
          "tree-sitter-javascript"
          "tree-sitter-json"
          "tree-sitter-python"
          "tree-sitter-rust"
          "tree-sitter-typescript")))
