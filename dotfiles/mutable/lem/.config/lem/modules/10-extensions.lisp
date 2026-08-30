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

;; process（纯 Lisp 进程管理）→ shell-mode（交互式 shell buffer）。
;; 启动终端面板用 shell-mode：vterm 的 C 层 forkpty 在 SBCL 多线程下
;; 随机失败（实测 fish 进程静默消失、面板恒空白），shell-mode 走
;; uiop:run-program 稳定；TUI 全屏程序（htop 等）不支持属可接受折衷。
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
