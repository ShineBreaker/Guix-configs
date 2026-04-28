;;; languages.el --- 编程语言特定配置 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 集中管理各种编程语言的模式声明与语言注册表。
;;
;; 设计原则：
;; - 语言支持优先保持覆盖面，允许“已安装但按需启用”的保守预留
;; - 对日常会直接触发的 major mode 提供明确 `use-package' 声明
;; - 与语言直接相关的 remap / LSP / formatter / 折叠名单统一收敛到本文件
;; - 对与当前补全体系不完全一致的工具，仅保留按需命令入口，不强行接管默认工作流
;;
;; 添加新语言支持：
;; 1. 通过 Guix 安装 LSP 服务器（参考 CLAUDE.md 包管理章节）
;; 2. 在本文件中补充 use-package 声明
;; 3. 按需补充 `custom:language-*' 注册表
;; 4. 需要安装的包写入 Guix Home 的 Emacs 包清单

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 语言注册表
;; ═════════════════════════════════════════════════════════════════════════════

(defconst custom:language-treesit-remaps
  '((c-mode . c-ts-mode)
    (c++-mode . c++-ts-mode)
    (go-mode . go-ts-mode)
    (java-mode . java-ts-mode)
    (json-mode . json-ts-mode)
    (python-mode . python-ts-mode)
    (rust-mode . rust-ts-mode)
    (typescript-mode . typescript-ts-mode))
  "语言相关的 Tree-sitter major mode remap 列表。")

(defconst custom:language-eglot-auto-modes
  '(c-mode c-ts-mode
    c++-mode c++-ts-mode
    csharp-mode
    gdscript-mode
    go-ts-mode
    java-mode java-ts-mode
    markdown-mode
    nix-mode
    python-mode python-ts-mode
    rust-mode rust-ts-mode
    zig-mode)
  "进入这些 major mode 时自动触发 `eglot-ensure'。")

(defconst custom:language-eglot-server-programs
  '(((c-mode c-ts-mode c++-mode c++-ts-mode) . ("ccls"))
    ((go-ts-mode) . ("gopls"))
    ((python-mode python-ts-mode) . ("pylsp"))
    ((rust-mode rust-ts-mode) . ("rust-analyzer")))
  "附加到 `eglot-server-programs' 的语言服务器配置。
envrc 的 buffer-local PATH 传播确保 eglot 能找到项目虚拟环境中的 pylsp。")

(defconst custom:language-origami-ts-modes
  '(c-ts-mode c++-ts-mode go-ts-mode java-ts-mode json-ts-mode
    python-ts-mode rust-ts-mode typescript-ts-mode dockerfile-ts-mode)
  "启用 `origami-ts' 解析器的 major mode 列表。")

(defconst custom:language-apheleia-formatters
  '((pandoc-markdown "pandoc" "-f" "gfm" "-t" "gfm" "--wrap=none"))
  "集中维护的 Apheleia 自定义 formatter 定义。")

(defconst custom:language-apheleia-mode-alist
  '((c-mode . clang-format)
    (c-ts-mode . clang-format)
    (c++-mode . clang-format)
    (c++-ts-mode . clang-format)
    (fish-mode . fish-indent)
    (go-ts-mode . gofmt)
    (gfm-mode . pandoc-markdown)
    (json-mode . js-beautify)
    (json-ts-mode . js-beautify)
    (js-json-mode . js-beautify)
    (markdown-mode . pandoc-markdown)
    (nix-mode . nixfmt)
    (python-mode . black)
    (python-ts-mode . black)
    (rust-mode . rustfmt)
    (rust-ts-mode . rustfmt)
    (sh-mode . shfmt)
    (bash-mode . shfmt)
    (typescript-mode . js-beautify)
    (typescript-ts-mode . js-beautify)
    (yaml-mode . yq-yaml)
    (zig-mode . zig-fmt))
  "集中维护的 Apheleia major mode 对应关系。")

(defconst custom:language-format-buffer-functions
  '((gdscript-mode . gdscript-format-buffer))
  "需要优先于 Apheleia / Eglot 执行的语言专属整缓冲区格式化命令。")

;; Common Lisp
(use-package sly
  :defer t
  :custom
  (inferior-lisp-program "sbcl"))

;; GDScript
(use-package gdscript-mode
  :mode "\\.gd\\'"
  :defer t
  :commands (gdscript-format-buffer
             gdscript-godot-open-project-in-editor
             gdscript-godot-run-project
             gdscript-godot-run-project-debug
             gdscript-godot-run-current-scene
             gdscript-godot-run-current-scene-debug
             gdscript-godot-edit-current-scene
             gdscript-godot-run-current-script
             gdscript-docs-browse-symbol-at-point)
  :init
  (autoload 'gdscript-format-buffer "gdscript-format" nil t)
  (autoload 'gdscript-godot-open-project-in-editor "gdscript-godot" nil t)
  (autoload 'gdscript-godot-run-project "gdscript-godot" nil t)
  (autoload 'gdscript-godot-run-project-debug "gdscript-godot" nil t)
  (autoload 'gdscript-godot-run-current-scene "gdscript-godot" nil t)
  (autoload 'gdscript-godot-run-current-scene-debug "gdscript-godot" nil t)
  (autoload 'gdscript-godot-edit-current-scene "gdscript-godot" nil t)
  (autoload 'gdscript-godot-run-current-script "gdscript-godot" nil t)
  (autoload 'gdscript-docs-browse-symbol-at-point "gdscript-docs" nil t)
  :custom
  (gdscript-godot-executable (or (executable-find "godot") "godot")))

;; C#
(use-package csharp-mode
  :ensure nil
  :mode ("\\.cs\\'" "\\.csx\\'" "\\.cake\\'")
  :defer t)

;; Fish Shell
(use-package fish-mode
  :mode "\\.fish\\'"
  :defer t)

(use-package fish-completion
  :defer t
  :config
  (when (and (executable-find "fish")
             (require 'fish-completion nil t))
    (global-fish-completion-mode)))

;; Helm Fish Completion
;; 当前默认 shell 补全仍走现有补全体系，仅保留手动命令入口。
(use-package helm-fish-completion
  :defer t
  :commands (helm-fish-completion
             helm-fish-completion-make-eshell-source))

;; JSON
(use-package json-mode
  :mode "\\.json\\'"
  :defer t)

;; kdl
(use-package kdl-mode
  :mode "\\.kdl\\'"
  :defer t)

;; Kotlin
(use-package kotlin-mode
  :mode "\\.kt\\'"
  :defer t)

;; Markdown
(use-package markdown-mode
  :mode ("\\.md\\'" "\\.markdown\\'")
  :defer t
  :custom
  (markdown-command "pandoc")
  (markdown-fontify-code-blocks-natively t))

;; Nix
(use-package nix-mode
  :mode "\\.nix\\'"
  :defer t)

;; YAML
(use-package yaml
  :defer t
  :commands (yaml-parse-string yaml-encode))

(use-package yaml-mode
  :mode ("\\.ya?ml\\'" "\\.yml\\.dist\\'")
  :defer t)

;; Rust
(use-package rust-mode
  :mode "\\.rs\\'"
  :defer t)

;; Scheme (Guile) - 使用 Arei
(use-package arei
  :defer t
  :hook (scheme-mode . arei-mode))

;; TypeScript
(use-package typescript-mode
  :mode "\\.ts\\'"
  :defer t)

;; Web 模板
(use-package web-mode
  :mode ("\\.html\\'" "\\.jsx\\'" "\\.tsx\\'" "\\.vue\\'")
  :defer t)

;; Yasnippet（代码片段）
(use-package yasnippet
  :defer 0.5
  :config
  (yas-global-mode 1))

(use-package yasnippet-snippets
  :after yasnippet
  :defer t)

;; Zig
(use-package zig-mode
  :mode "\\.zig\\'"
  :defer t)

(provide 'languages)
;;; languages.el ends here
