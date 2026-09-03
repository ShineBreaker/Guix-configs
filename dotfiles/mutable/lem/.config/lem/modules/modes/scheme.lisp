;;; modules/modes/scheme.lisp — Scheme/Guile（Guix 配置主力语言）
;;;
;;; scheme-mode 镜像内建（自带语法缩进 / REPL / swank 客户端，
;;; 文件类型 scm/sld/rkt/ss 自动关联）。LSP 走 guile-lsp-server。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-scheme-mode "SCHEME-MODE")
             "scheme"
             '(".git" "guix.scm" "hall.scm")
             '("guile-lsp-server"))

(vs-paredit (vs$ :lem-scheme-mode "SCHEME-MODE"))
