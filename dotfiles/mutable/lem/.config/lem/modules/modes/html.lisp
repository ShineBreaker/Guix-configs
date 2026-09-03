;;; modules/modes/html.lisp — HTML
;;;
;;; html-mode 镜像内建。LSP 走 vscode-html-language-server（--stdio）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-html-mode "HTML-MODE")
             "html"
             '("package.json" "index.html" ".git")
             '("vscode-html-language-server" "--stdio"))
