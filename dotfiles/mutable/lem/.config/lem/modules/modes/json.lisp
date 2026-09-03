;;; modules/modes/json.lisp — JSON
;;;
;;; json-mode 镜像内建。LSP 走 vscode-json-language-server（--stdio，
;;; 与 typescript-language-server 同款，VSCode 官方扩展同配置）。
;;; 保存格式化走 vs-register-formatter（60-editor-config，*auto-format*
;;; 主开关同在）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-json-mode "JSON-MODE")
             "json"
             '("package.json" "tsconfig.json" ".vscode" ".git")
             '("vscode-json-language-server" "--stdio"))

;; 保存时 clang-format（--assume-filename 注入 buffer 路径定语言与
;; .clang-format 发现）：上游 json-mode 的 :formatter 挂在未安装的
;; prettier 上是死注册，本注册以同 specializer 替换语义覆盖之。
;; clang-format 恒零退出：非法 JSON 走 best-effort 排版（token 全保留），
;; 纯非 JSON 文本原文照排（此时输出=原文，handler 的「输出≠原文才替换」
;; 判断不动 buffer）。
(vs-register-formatter :lem-json-mode "JSON-MODE"
                       '("clang-format" "--assume-filename" :FILE))
