;;; modules/modes/nix.lisp — Nix（source/nix flake）
;;;
;;; nix-mode 镜像内建（自带缩进）。LSP 走 nil（nix language server）。
;;; 保存格式化走 vs-register-formatter（60-editor-config，*auto-format*
;;; 主开关同在）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-nix-mode "NIX-MODE")
             "nix"
             '("flake.nix" "shell.nix" "default.nix" ".git")
             '("nil"))

;; 保存时 nixfmt（stdin→stdout 管道）：语法错误时非零退出，handler
;; 不动 buffer，原文无损。
(vs-register-formatter :lem-nix-mode "NIX-MODE" '("nixfmt"))
