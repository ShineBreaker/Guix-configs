;;; modules/modes/web.lisp — TypeScript / JavaScript
;;;
;;; typescript-mode / js-mode 镜像内建。LSP 走 typescript-language-server
;;; （两种 language-id 各接一份；--stdio 与上游 js-spec 模板一致）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-typescript-mode "TYPESCRIPT-MODE")
             "typescript"
             '("tsconfig.json" "package.json")
             '("typescript-language-server" "--stdio"))

(vs-lsp-wire (vs$ :lem-js-mode "JS-MODE")
             "javascript"
             '("package.json")
             '("typescript-language-server" "--stdio"))
