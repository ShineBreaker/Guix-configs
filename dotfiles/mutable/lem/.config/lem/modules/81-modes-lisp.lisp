;;; modules/modes/lisp.lisp — Common Lisp / Emacs Lisp
;;;
;;; lisp-mode 镜像内建（lem 本体就是 CL：M-x slime 可连 REPL）；
;;; elisp-mode 镜像内建（dotfiles/emacs 的 .el 编辑用）。
;;; 两者不接 LSP（lisp 有 slime 体系），只挂 paredit。
;;; 依赖：utils（vs$/vs-paredit/vs-help-note）、keyhelp（帮助页附注）。

(in-package :lem-user)

(vs-paredit (vs$ :lem-lisp-mode "LISP-MODE"))

(vs-paredit (vs$ :lem-elisp-mode "ELISP-MODE"))

;; Hyperspec 查询（SLIME 风格 C-c C-d h）。绑在 lisp-mode 局部 keymap
;; （vs-bind 只落全局），命令由 define-command 产物直接引用；
;; 符号动态解析，缺失只跳过。
(let ((keymap (vs$ :lem-lisp-mode "*LISP-MODE-KEYMAP*"))
      (cmd (vs$ :lem-lisp-mode/hyperspec "HYPERSPEC-AT-POINT")))
  (when (and keymap cmd)
    (define-key (symbol-value keymap) "C-c C-d h" cmd)
    (vs-help-note "code" "C-c C-d h" "CL Hyperspec（光标下符号，lisp-mode）")))
