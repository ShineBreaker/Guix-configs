;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; languages.el --- 编程语言特定配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置各种编程语言的模式和工具。

;;; Code:

;; Rust
(use-package rust-mode
  :mode "\\.rs\\'"
  :defer t)

;; Zig
(use-package zig-mode
  :mode "\\.zig\\'"
  :defer t)

;; TypeScript
(use-package typescript-mode
  :mode "\\.ts\\'"
  :defer t)

;; Web 模板
(use-package web-mode
  :mode ("\\.html\\'" "\\.jsx\\'" "\\.tsx\\'" "\\.vue\\'")
  :defer t)

;; JSON
(use-package json-mode
  :mode "\\.json\\'"
  :defer t)

;; Markdown
(use-package markdown-mode
  :mode ("\\.md\\'" "\\.markdown\\'")
  :defer t
  :custom
  (markdown-command "pandoc")
  (markdown-fontify-code-blocks-natively t))

;; Kotlin
(use-package kotlin-mode
  :mode "\\.kt\\'"
  :defer t)

;; Scheme (Guile)
(use-package geiser
  :defer t
  :custom
  (geiser-active-implementations '(guile))
  :hook (scheme-mode . geiser-mode))

;; Common Lisp
(use-package sly
  :defer t
  :custom
  (inferior-lisp-program "sbcl"))

;; Yasnippet（代码片段）
(use-package yasnippet
  :defer 0.5
  :config
  (yas-global-mode 1))

(use-package yasnippet-snippets
  :after yasnippet
  :defer t)

(provide 'languages)
;;; languages.el ends here
