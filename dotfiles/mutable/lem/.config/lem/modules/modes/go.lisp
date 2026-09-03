;;; modules/modes/go.lisp — Go
;;;
;;; go-mode 镜像内建。LSP 走 gopls（stdio 模式；上游 go-mode 自带的
;;; lsp-config.lisp 用 tcp 端口模式，此处统一 stdio）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-go-mode "GO-MODE")
             "go"
             '("go.mod")
             '("gopls"))
