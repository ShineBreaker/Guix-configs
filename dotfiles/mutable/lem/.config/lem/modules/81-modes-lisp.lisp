;;; modules/modes/lisp.lisp — Common Lisp / Emacs Lisp
;;;
;;; lisp-mode 镜像内建（lem 本体就是 CL：M-x slime 可连 REPL）；
;;; elisp-mode 镜像内建（dotfiles/emacs 的 .el 编辑用）。
;;; 两者不接 LSP（lisp 有 slime 体系），只挂 paredit。

(in-package :lem-user)

(vs-paredit (vs$ :lem-lisp-mode "LISP-MODE"))

(vs-paredit (vs$ :lem-elisp-mode "ELISP-MODE"))
