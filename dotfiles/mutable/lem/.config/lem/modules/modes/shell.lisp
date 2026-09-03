;;; modules/modes/shell.lisp — POSIX shell
;;;
;;; posix-shell-mode 镜像内建（.sh/.bashrc/.profile，上游 define-file-type）。
;;; 保存格式化走 vs-register-formatter（60-editor-config，*auto-format*
;;; 主开关同在）。终端面板的 shell-mode/run-shell-mode 是 pty 伪模式，
;;; 与本文件的 posix-shell-mode 无关，不受影响。

(in-package :lem-user)

;; 保存时 shfmt（stdin→stdout 管道）：语法错误时非零退出，handler
;; 不动 buffer，原文无损。
(vs-register-formatter :lem-posix-shell-mode "POSIX-SHELL-MODE" '("shfmt"))
