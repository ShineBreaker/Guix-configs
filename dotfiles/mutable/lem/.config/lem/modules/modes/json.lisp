;;; modules/modes/json.lisp — JSON
;;;
;;; json-mode 镜像内建。LSP 走 vscode-json-language-server（--stdio，
;;; 与 typescript-language-server 同款，VSCode 官方扩展同配置）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-json-mode "JSON-MODE")
             "json"
             '("package.json" "tsconfig.json" ".vscode" ".git")
             '("vscode-json-language-server" "--stdio"))
