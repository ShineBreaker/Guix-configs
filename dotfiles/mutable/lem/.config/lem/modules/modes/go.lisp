;;; modules/modes/go.lisp — Go
;;;
;;; go-mode 镜像内建。LSP 走 gopls（stdio 模式；上游 go-mode 自带的
;;; lsp-config.lisp 用 tcp 端口模式，此处统一 stdio）。保存格式化走
;;; vs-register-formatter（60-editor-config，*auto-format* 主开关同在）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-go-mode "GO-MODE")
             "go"
             '("go.mod")
             '("gopls"))

;; 保存时 gofmt：覆盖上游 go-mode 的「-w 改文件 + revert」注册——该路径
;; 在 after-save-hook 内同秒改写文件时 changed-disk-p 判否跳过回读，
;; 格式化被回写覆盖（详见 60-editor-config 注释）。stdin 管道不碰文件、
;; 无竞态；gofmt 语法错误时非零退出，handler 不动 buffer，原文无损。
(vs-register-formatter :lem-go-mode "GO-MODE" '("gofmt"))
