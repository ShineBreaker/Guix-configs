;;; modules/70-keybindings.lisp — 键位：混合模式
;;;
;;; 依赖：utils（vs-bind）、extensions（terminal/legit/grep）、
;;; explorer + terminal（VSCODE-TOGGLE-* 命令）、icons 之后的全部模块。
;;;
;;; VSCode 高频核心键（C-p/C-f/C-s/C-b/C-`/C-\/C-Tab/F2）覆盖 lem 同位移动键，
;;; 被覆盖的移动退到 Meta 系（与 Emacs 惯例一致）；C-x/C-c 前缀体系完整保留。
;;; 键语法注意：Shift 必须写全拼 "Shift-"（S- 是 super！）

(in-package :lem-user)

;; --- VSCode 核心区 ---
(vs-bind "C-p" :lem "FIND-FILE-RECURSIVELY")      ; Ctrl+P Quick Open
(vs-bind "M-p" :lem "PREVIOUS-LINE")              ; 原 C-p 上移退到 M-p
(vs-bind "C-f" :lem "ISEARCH-FORWARD")            ; Ctrl+F 查找
(vs-bind "M-f" :lem "FORWARD-CHAR")               ; 原 C-f 前进退到 M-f
(vs-bind "C-s" :lem "SAVE-BUFFER")                ; Ctrl+S 保存
(vs-bind "C-b" :lem-user "VSCODE-TOGGLE-SIDEBAR") ; Ctrl+B 侧栏开关
(vs-bind "M-b" :lem "BACKWARD-CHAR")              ; 原 C-b 后退退到 M-b
(vs-bind "C-\\" :lem "SPLIT-ACTIVE-WINDOW-HORIZONTALLY") ; Ctrl+\ 分屏
(vs-bind "Shift-C-e" :lem-user "VSCODE-TOGGLE-SIDEBAR")  ; Ctrl+Shift+E 资源管理器
(vs-bind "Shift-C-g" :lem/legit "LEGIT-STATUS")   ; Ctrl+Shift+G 源代码管理
(vs-bind "Shift-C-f" :lem/grep "PROJECT-GREP")    ; Ctrl+Shift+F 跨文件搜索
;; --- Tab 切换 ---
(vs-bind "C-Tab" :lem/frame-multiplexer "FRAME-MULTIPLEXER-NEXT")       ; 下一个 tab
(vs-bind "Shift-C-Tab" :lem/frame-multiplexer "FRAME-MULTIPLEXER-PREV") ; 上一个
;; --- 终端（VSCode Ctrl+` / Ctrl+J toggle 面板） ---
;; 面板为 shell-mode：listener 键位不绑 C-j，编辑区与面板内均可 toggle。
;; vterm（M-x terminal 呼出）另有约束：Ctrl+` 在传统终端输入协议不可表达
;; （kitty legacy 下就是普通 `；扩展协议序列 ncurses 不解，ESC+` 又被
;; terminal-mode 的 Escape 键拆解）；vterm 聚焦时 0x0A 被 terminfo 报为
;; Return 直喂 vterm（换行语义不可牺牲），故 vterm 内隐藏面板走 M-`。
(vs-bind "C-j" :lem-user "VSCODE-TOGGLE-TERMINAL")
(vs-bind "M-j" :lem "NEXT-LINE")                ; 原 C-j 下移退到 M-j
(vs-bind "C-`" :lem-user "VSCODE-TOGGLE-TERMINAL") ; kitty 协议终端可达时生效
(vs-bind "M-`" :lem-user "VSCODE-TOGGLE-TERMINAL")
(let ((tkm (vs$ :lem-terminal/terminal-mode "*TERMINAL-MODE-KEYMAP*")))
  (when tkm
    (let ((cmd (vs$ :lem-user "VSCODE-TOGGLE-TERMINAL")))
      (define-key (symbol-value tkm) "M-`" cmd))))
;; --- F2 符号重命名（LSP） ---
(vs-bind "F2" :lem-lsp-mode "LSP-RENAME")
