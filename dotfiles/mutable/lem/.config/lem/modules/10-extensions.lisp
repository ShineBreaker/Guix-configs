;;; modules/10-extensions.lisp — store 扩展补载
;;;
;;; 依赖：utils（vs-load-lem-source）；被 explorer/terminal/keybindings
;;; 依赖（legit/terminal-mode/shell-mode 的符号）。必须先于它们加载。
;;;
;;; 镜像已内置：LSP / dashboard / copilot / markdown / base16 / 语言 modes / filer 骨架
;;; 需补载：terminal（vterm）/ legit（git）/ patch-mode（legit 依赖）/ process + shell-mode

(in-package :lem-user)

(load-lem-source "extensions/patch-mode/patch-mode.lisp")

;; terminal：serial 顺序 ffi → terminal → terminal-mode（ffi 里 terminal.so 为 store 绝对路径）
(vs-load-lem-source "extensions/terminal/ffi.lisp")
(vs-load-lem-source "extensions/terminal/terminal.lisp")
(vs-load-lem-source "extensions/terminal/terminal-mode.lisp")

;; process（纯 Lisp 进程管理）→ shell-mode（交互式 listener buffer，M-x
;; run-shell 仍可用）。终端面板 2026-08-30 起用 vterm：shell-mode 底下的
;; async-process 开 pty 从不设控制终端（O_NOCTTY + 无 TIOCSCTTY），fish
;; 4.7.1 无 ctty 直接 exit 1（bash 容忍），面板成空壳；vterm 的 forkpty
;; 标准流程实测 fish 正常，早年「forkpty 在 SBCL 多线程下随机失败」未再
;; 复现。详见 50-terminal 头注释。
(vs-load-lem-source "extensions/process/package.lisp")
(vs-load-lem-source "extensions/process/process.lisp")
(vs-load-lem-source "extensions/process/stream.lisp")
(vs-load-lem-source "extensions/shell-mode/shell-mode.lisp")

;; legit：serial 顺序（porcelain 抽象 → git/hg/fossil 后端 → 交互层）
(dolist (f '("extensions/legit/porcelain.lisp"
             "extensions/legit/porcelain-git.lisp"
             "extensions/legit/porcelain-hg.lisp"
             "extensions/legit/porcelain-fossil.lisp"
             "extensions/legit/legit-common.lisp"
             "extensions/legit/peek-legit.lisp"
             "extensions/legit/legit.lisp"
             "extensions/legit/legit-rebase.lisp"
             "extensions/legit/legit-commit.lisp"))
  (vs-load-lem-source f))
