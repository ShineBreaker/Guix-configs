;;; modules/modes/cc.lisp — C / C++
;;;
;;; c-mode 镜像内建（lem 无独立 c++-mode，.cpp 同走 c-mode）。
;;; LSP 走 clangd。保存格式化走 vs-register-formatter（60-editor-config，
;;; *auto-format* 主开关同在）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-c-mode "C-MODE")
             "c"
             '("compile_commands.json" "CMakeLists.txt" "Makefile" ".git")
             '("clangd"))

;; 保存时 clang-format：覆盖上游 c-mode 的「-i 改文件 + revert」注册——
;; 该路径在 after-save-hook 内同秒改写文件时 changed-disk-p 判否跳过
;; 回读，格式化被回写覆盖（详见 60-editor-config 注释）。stdin 管道
;; 不碰文件、无竞态；--assume-filename 注入 buffer 路径保留 .clang-format
;; 项目样式发现。clang-format 对非法 C 恒零退出 best-effort（token 保留），
;; 输出=原文时 handler 不动 buffer。
(vs-register-formatter :lem-c-mode "C-MODE"
                       '("clang-format" "--assume-filename" :FILE "--style" "file"))
