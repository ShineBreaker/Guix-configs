;;; modules/modes/nix.lisp — Nix（source/nix flake）
;;;
;;; nix-mode 镜像内建（自带缩进）。LSP 走 nil（nix language server）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-nix-mode "NIX-MODE")
             "nix"
             '("flake.nix" "shell.nix" "default.nix" ".git")
             '("nil"))
