;;; modules/70-keybindings.lisp — 键位：VSCode 核心 + Emacs 体验对齐
;;;
;;; 依赖：utils（vs-bind/vs-declare-group/vs-help-note）、keyhelp（F1）、
;;; completion（M-/）、explorer + terminal（VSCODE-TOGGLE-* 命令）、
;;; extensions（terminal/legit/grep）、icons 之后的全部模块。
;;;
;;; 三节结构：
;;;   1. 自研命令：M-方向窗口焦点（windmove 对齐，lem 无现成方向切窗）
;;;      与 C-S-w 关闭当前 buffer（kill-buffer 带 prompt，这里不问名）；
;;;   2. VSCode 核心区：高频键覆盖 lem 同位移动键，被覆盖的移动退到
;;;      Meta 系（与 Emacs 惯例一致）；C-x/C-c 前缀体系完整保留；
;;;   3. Emacs 对齐区：对齐用户 emacs.org 的 IDE 风格键组（undo/注释/
;;;      全选/dabbrev/goto-line/字号/xref），全部键位带分组+中文描述，
;;;      F1 帮助页按此渲染（which-key 替代，见 45-keyhelp）。
;;; 键语法注意：Shift 必须写全拼 "Shift-"（S- 是 super！）

(in-package :lem-user)

;; --- 自研命令：窗口方向焦点（对齐 Emacs windmove 的 M-方向） ---
;; lem 无方向切窗命令，按窗口几何中心找 dx/dy 半轴方向上最近的窗口。
;; 侧栏/终端面板同在 window-list 内，因此 M-方向也能移出/移回面板。
(defun vs-window-in-direction (dx dy)
  "返回 cur 在 dx/dy 方向上的最近窗口（无则 nil）。"
  (let ((cur (current-window))
        (best nil)
        (best-d most-positive-fixnum))
    (let ((cx (+ (window-x cur) (floor (window-width cur) 2)))
          (cy (+ (window-y cur) (floor (window-height cur) 2))))
      (dolist (w (window-list))
        (unless (eq w cur)
          (let* ((ddx (- (+ (window-x w) (floor (window-width w) 2)) cx))
                 (ddy (- (+ (window-y w) (floor (window-height w) 2)) cy)))
            (when (and (or (zerop dx) (plusp (* ddx dx)))
                       (or (zerop dy) (plusp (* ddy dy))))
              (let ((d (+ (* ddx ddx) (* ddy ddy))))
                (when (< d best-d)
                  (setf best w best-d d))))))))
    best))

(define-command vs-window-focus-left () ()
  (let ((w (vs-window-in-direction -1 0)))
    (when w (switch-to-window w))))

(define-command vs-window-focus-right () ()
  (let ((w (vs-window-in-direction 1 0)))
    (when w (switch-to-window w))))

(define-command vs-window-focus-up () ()
  (let ((w (vs-window-in-direction 0 -1)))
    (when w (switch-to-window w))))

(define-command vs-window-focus-down () ()
  (let ((w (vs-window-in-direction 0 1)))
    (when w (switch-to-window w))))

;; --- 自研命令：关闭当前 buffer（C-S-w，对齐用户 Emacs kill-current-buffer） ---
(define-command vs-kill-current-buffer () ()
  (kill-buffer (current-buffer)))

;; --- 分组声明（F1 帮助页按此顺序渲染） ---
(vs-declare-group "nav" "移动与查找")
(vs-declare-group "editor" "编辑与文件")
(vs-declare-group "ui" "界面与面板")
(vs-declare-group "window" "窗口")
(vs-declare-group "code" "代码智能")
(vs-declare-group "help" "帮助")

;; --- VSCode 核心区 ---
(vs-bind "C-p" :lem "FIND-FILE-RECURSIVELY" "nav" "Quick Open 打开文件")
(vs-bind "M-p" :lem "PREVIOUS-LINE" "nav" "光标上移（原 C-p 退位）")
(vs-bind "C-f" :lem "ISEARCH-FORWARD" "nav" "查找（isearch）")
(vs-bind "M-f" :lem "FORWARD-CHAR" "nav" "前进一字符（原 C-f 退位）")
(vs-bind "C-s" :lem "SAVE-BUFFER" "editor" "保存")
(vs-bind "C-b" :lem-user "VSCODE-TOGGLE-SIDEBAR" "ui" "侧栏开关")
(vs-bind "M-b" :lem "BACKWARD-CHAR" "nav" "后退一字符（原 C-b 退位）")
(vs-bind "C-\\" :lem "SPLIT-ACTIVE-WINDOW-HORIZONTALLY" "window" "垂直分屏")
(vs-bind "Shift-C-e" :lem-user "VSCODE-TOGGLE-SIDEBAR" "ui" "切换侧栏（资源管理器）")
(vs-bind "Shift-C-g" :lem/legit "LEGIT-STATUS" "ui" "源代码管理（Git 状态）")
(vs-bind "Shift-C-f" :lem/grep "PROJECT-GREP" "nav" "跨文件搜索（项目 grep）")
;; --- Tab 切换（frame-multiplexer；C-z 数字快切被 undo 覆盖，见下） ---
(vs-bind "C-Tab" :lem/frame-multiplexer "FRAME-MULTIPLEXER-NEXT" "ui" "下一个 Tab")
(vs-bind "Shift-C-Tab" :lem/frame-multiplexer "FRAME-MULTIPLEXER-PREV" "ui" "上一个 Tab")
;; --- 终端（VSCode Ctrl+` / Ctrl+J toggle 面板） ---
;; 面板为 vterm。输入协议约束（传统终端 legacy 序列下）：Ctrl+` 不可表达
;; （就是普通 `；扩展协议序列 ncurses 不解，ESC+` 又被 terminal-mode 的
;; Escape 键拆解）；C-j 与 Return 同码 0x0A，vterm 聚焦时被 terminfo 报为
;; Return 直喂终端（换行语义不可牺牲）。故 vterm 内隐藏面板走 M-`
;; （terminal-mode-keymap 显式绑定）；SDL2 前端无此约束，C-j / C-` 原样可达
;; （bypass 表保证终端聚焦时命令仍生效，见 50-terminal 尾部）。
(vs-bind "C-j" :lem-user "VSCODE-TOGGLE-TERMINAL" "ui" "终端面板开关（SDL2/协议终端）")
(vs-bind "M-j" :lem "NEXT-LINE" "nav" "光标下移（原 C-j 退位）")
(vs-bind "C-`" :lem-user "VSCODE-TOGGLE-TERMINAL" "ui" "终端面板开关（kitty 协议）")
(vs-bind "M-`" :lem-user "VSCODE-TOGGLE-TERMINAL" "ui" "终端面板开关")
(let ((tkm (vs$ :lem-terminal/terminal-mode "*TERMINAL-MODE-KEYMAP*")))
  (when tkm
    (let ((cmd (vs$ :lem-user "VSCODE-TOGGLE-TERMINAL")))
      (define-key (symbol-value tkm) "M-`" cmd))))
(vs-help-note "ui" "M-`" "终端聚焦时隐藏面板（terminal-mode 内）")
;; --- F2 符号重命名（LSP） ---
(vs-bind "F2" :lem-lsp-mode "LSP-RENAME" "code" "重命名符号（LSP）")

;; --- Emacs 体验对齐区（对齐 emacs.org 的 IDE 风格键组） ---
(vs-bind "C-z" :lem "UNDO" "editor" "撤销（覆盖 multiplexer C-z 快切前缀）")
(vs-bind "C-x u" :lem "UNDO" "editor" "撤销（Emacs 传统键）")
(vs-bind "Shift-C-z" :lem "REDO" "editor" "重做")
(vs-bind "C-/" :lem/language-mode "COMMENT-OR-UNCOMMENT-REGION" "editor"
         "注释/反注释（无选区注释当前行；覆盖默认 redo）")
(vs-bind "C-a" :lem "MARK-SET-WHOLE-BUFFER" "editor" "全选（行首退 Home）")
(vs-bind "M-/" :lem-user "VS-DABBREV-COMPLETE" "editor" "dabbrev 词补全（弹窗）")
(vs-bind "M-Left" :lem-user "VS-WINDOW-FOCUS-LEFT" "window" "焦点移到左窗口")
(vs-bind "M-Right" :lem-user "VS-WINDOW-FOCUS-RIGHT" "window" "焦点移到右窗口")
(vs-bind "M-Up" :lem-user "VS-WINDOW-FOCUS-UP" "window" "焦点移到上窗口")
(vs-bind "M-Down" :lem-user "VS-WINDOW-FOCUS-DOWN" "window" "焦点移到下窗口")
(vs-bind "M-g g" :lem "GOTO-LINE" "nav" "跳转到行")
(vs-bind "Shift-C-p" :lem "EXECUTE-COMMAND" "nav" "命令面板（M-x 等价）")
(vs-bind "Shift-C-w" :lem-user "VS-KILL-CURRENT-BUFFER" "editor" "关闭当前 buffer（不问名）")
(vs-bind "C-=" :lem "FONT-SIZE-INCREASE" "ui" "字号增大（SDL2）")
(vs-bind "C--" :lem "FONT-SIZE-DECREASE" "ui" "字号减小（SDL2）")
(vs-bind "C-F12" :lem/language-mode "FIND-DEFINITIONS" "code" "跳转定义")
(vs-bind "Shift-C-F12" :lem/language-mode "FIND-REFERENCES" "code" "查找引用")
(vs-bind "F1" :lem-user "VS-SHOW-KEYBINDINGS" "help" "键位帮助页（本配置全量）")

;; --- 默认键附注（不经 vs-bind 的绑定，只进帮助页） ---
(vs-help-note "code" "M-." "跳转定义（language-mode 默认）")
(vs-help-note "code" "M-?" "查找引用（language-mode 默认）")
(vs-help-note "code" "M-," "返回跳转前位置")
(vs-help-note "code" "C-M-i" "符号补全（LSP，弹窗）")
(vs-help-note "editor" "Tab" "缩进并补全（language-mode buffer）")
(vs-help-note "editor" "C-_" "重做（默认保留）")
(vs-help-note "editor" "M-;" "注释/反注释（language-mode 默认）")
(vs-help-note "editor" "C-x C-f" "打开文件")
(vs-help-note "editor" "C-x b" "切换 buffer")
(vs-help-note "editor" "C-x k" "关闭 buffer（问名）")
(vs-help-note "editor" "C-x C-b" "buffer 列表")
(vs-help-note "editor" "M-w / C-w / C-y" "复制 / 剪切 / 粘贴")
(vs-help-note "nav" "Home / End" "行首 / 行尾")
(vs-help-note "nav" "C-M-a / C-M-e" "defun 首 / 尾（language-mode）")
(vs-help-note "nav" "M-<" "buffer 开头")
(vs-help-note "nav" "M->" "buffer 结尾")
