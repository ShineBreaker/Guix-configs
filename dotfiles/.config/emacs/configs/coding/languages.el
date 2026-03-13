;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; languages.el --- 编程语言特定配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置各种编程语言的模式和工具。

;;; Code:

;; Rust
(use-package rust-mode
  :mode "\\.rs\\'")

;; Zig
(use-package zig-mode
  :mode "\\.zig\\'")

;; TypeScript
(use-package typescript-mode
  :mode "\\.ts\\'")

;; Web 模板
(use-package web-mode
  :mode ("\\.html\\'" "\\.jsx\\'" "\\.tsx\\'" "\\.vue\\'"))

;; JSON
(use-package json-mode
  :mode "\\.json\\'")

;; Markdown
(use-package markdown-mode
  :mode ("\\.md\\'" "\\.markdown\\'")
  :custom
  (markdown-command "pandoc")
  (markdown-fontify-code-blocks-natively t))

;; Kotlin
(use-package kotlin-mode
  :mode "\\.kt\\'")

;; Scheme (Guile)
(use-package geiser
  :custom
  (geiser-active-implementations '(guile))
  :hook (scheme-mode . geiser-mode))

;; Common Lisp
(use-package sly
  :custom
  (inferior-lisp-program "sbcl"))

;; Yasnippet（代码片段）
(use-package yasnippet
  :config
  (yas-global-mode 1))

(use-package yasnippet-snippets
  :after yasnippet)

(provide 'languages)
;;; languages.el ends here
