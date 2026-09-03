;;; modules/modes/css.lisp — CSS
;;;
;;; css-mode 镜像内建。LSP 走 vscode-css-language-server（--stdio）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-css-mode "CSS-MODE")
             "css"
             '("package.json" "style.css" ".git")
             '("vscode-css-language-server" "--stdio"))
