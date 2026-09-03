;;; modules/modes/cc.lisp — C / C++
;;;
;;; c-mode 镜像内建（lem 无独立 c++-mode，.cpp 同走 c-mode）。
;;; LSP 走 clangd。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-c-mode "C-MODE")
             "c"
             '("compile_commands.json" "CMakeLists.txt" "Makefile" ".git")
             '("clangd"))
