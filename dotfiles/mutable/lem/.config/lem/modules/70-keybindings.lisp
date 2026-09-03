;;; modules/70-keybindings.lisp — 键位：VSCode 核心 + Emacs 体验对齐
;;;
;;; 依赖：utils（vs-bind/vs-declare-group/vs-help-note）、keyhelp（F1）、
;;; completion（M-/）、explorer + terminal + editor-config
;;; （VSCODE-TOGGLE-* 命令、vs-terminal-buffer）、上游内置扩展（terminal/legit/grep，
;;; nightly 全内置）、icons 之后的全部模块。
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

;; --- 自研命令：行移动/复制（VSCode Alt+Up/Down、Shift+Alt+Down；
;;     上游无对应命令。实现只用已验证 API：LINE-NUMBER-AT-POINT 取整数
;;     行号（point-line 返回 LINE 对象非整数，不能算术，v6 实测）、
;;     line-string 取行文本、KILL-WHOLE-LINE 删整行（有命令类可
;;     funcall）、move-to-line 绝对定位（溢出钳制，v6 实测）、
;;     insert-string/character 插入、point-column/move-to-column 保持列。
;;     kill 后光标落点前端不一致（末行 kill 落尾空行，v45 实测），故全程
;;     用绝对行号定位，不依赖 kill 后光标位置） ---
(defun vs-restore-column (col)
  "尽量恢复列 col（行短则钳制行尾）。"
  (ignore-errors (move-to-column (current-point) col)))

(defun vs-line-num ()
  "当前整数行号。"
  (let ((fn (vs$ :lem "LINE-NUMBER-AT-POINT")))
    (and fn (funcall fn (current-point)))))

(define-command vs-move-line-up () ()
  (let ((n (vs-line-num)))
    (when (and n (> n 1))
      (let ((text (line-string (current-point)))
            (col (point-column (current-point)))
            (kill (vs$ :lem "KILL-WHOLE-LINE")))
        (when kill
          (funcall kill)
          ;; 到 N-1 行行首插入 text+换行，原 N-1 行被挤到 N；再到 N 行。
          (move-to-line (current-point) (1- n))
          (line-start (current-point))
          (insert-string (current-point) text)
          (insert-character (current-point) #\newline)
          (move-to-line (current-point) n)
          (vs-restore-column col))))))

(define-command vs-move-line-down () ()
  ;; 下移 N 行 = 先到 N+1 行再上移（复用已验证的 up 逻辑）。到底判定：
  ;; buffer 尾空行语义下 last-line-p 不可靠；且 NEXT-LINE 在末行会开新
  ;; 空行（非钳制），故分两支：下去后行号不变即钳制到底；行号 +1 但新
  ;; 行是空的即开新行到底——删掉空行回 N 行 no-op。
  ;; 注意 NEXT-LINE 的可选参数 N 无缺省值（PREVIOUS-LINE 缺省 1），无参
  ;; funcall 会在内部算术上炸 NIL 不是 REAL，必须显式传 1。
  (let ((n (vs-line-num))
        (next (vs$ :lem "NEXT-LINE"))
        (kill (vs$ :lem "KILL-WHOLE-LINE")))
    (when (and n next kill)
      (funcall next 1)
      (let ((m (or (vs-line-num) n)))
        (cond ((= m n)
               (move-to-line (current-point) n))
              ((and (= m (1+ n))
                    (string= (line-string (current-point)) ""))
               (funcall kill)
               (move-to-line (current-point) n))
              (t (funcall 'vs-move-line-up)))))))

(define-command vs-duplicate-line () ()
  (let ((n (vs-line-num)))
    (when n
      (let ((text (line-string (current-point)))
            (col (point-column (current-point))))
        (line-end (current-point))
        (insert-character (current-point) #\newline)
        (insert-string (current-point) text)
        (vs-restore-column col)))))

;; --- 自研命令：多光标向上加光标（VSCode Ctrl+Alt+Up；上游
;;     lem-core/commands/multiple-cursors 只有 next-line 版（经 :lem
;;     use-reexport），无上一行版。本命令镜像上游 add-cursors-to-next-line：
;;     buffer-cursors 按 point< 升序，向上落点撞上前一项（上方光标）即
;;     跳过防叠；make-fake-cursor/buffer-cursors 走 vs$，旧构建缺失时
;;     整条 no-op 不炸） ---
(define-command vs-add-cursors-to-previous-line () ()
  (let ((make-cursor (vs$ :lem "MAKE-FAKE-CURSOR"))
        (get-cursors (vs$ :lem "BUFFER-CURSORS")))
    (when (and make-cursor get-cursors)
      (let ((cursors (funcall get-cursors (current-buffer)))
            prev)
        (dolist (cursor cursors)
          (with-point ((p cursor))
            (when (and (line-offset p -1 (point-charpos p))
                       (or (null prev)
                           (not (same-line-p p prev))))
              (funcall make-cursor p)))
          (setf prev cursor))))))

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
(vs-bind "C-f" :lem/isearch "ISEARCH-FORWARD" "nav" "查找（isearch）")
(vs-bind "M-f" :lem "FORWARD-CHAR" "nav" "前进一字符（原 C-f 退位）")
(vs-bind "C-s" :lem "SAVE-BUFFER" "editor" "保存")
(vs-bind "C-b" :lem-user "VSCODE-TOGGLE-SIDEBAR" "ui" "侧栏开关")
(vs-bind "M-b" :lem "BACKWARD-CHAR" "nav" "后退一字符（原 C-b 退位）")
(vs-bind "C-\\" :lem "SPLIT-ACTIVE-WINDOW-HORIZONTALLY" "window" "垂直分屏")
(vs-bind "Shift-C-e" :lem-user "VSCODE-TOGGLE-SIDEBAR" "ui" "切换侧栏（资源管理器）")
(vs-bind "Shift-C-g" :lem/legit "LEGIT-STATUS" "ui" "源代码管理（Git 状态）")
(vs-bind "Shift-C-f" :lem/grep "PROJECT-GREP" "nav" "跨文件搜索（项目 grep）")
;; --- Tab 切换（VSCode C-Tab 循环编辑器 tab；不能直接用
;;     frame-multiplexer：它循环虚拟 frame，单 frame 下恒 no-op
;;     （ncurses 实测连按三次不动），且会落到 tabbar 不显示的隐藏
;;     buffer（真机主窗变空视图实证）。自研命令只在文件 buffer 内
;;     循环，与 tabbar 显示口径一致；0/1 个文件时 no-op） ---
(defun vs-tab-file-buffers ()
  "文件 buffer 列表（buffer-filename 非空；ncurses 下 tabbar 管线关闭，
此处不走 GET-TABBAR-BUFFERS，保证双前端一致）。"
  (remove-if-not (lambda (b) (ignore-errors (buffer-filename b)))
                 (buffer-list)))

(defun vs-tab-cycle (dir)
  "DIR=+1 下一个/-1 上一个：当前 buffer 在表内则顺/逆移一位，
在表外（终端等）则落到首个文件 tab。"
  (let ((tabs (vs-tab-file-buffers)))
    (when (cdr tabs)
      (let ((pos (position (current-buffer) tabs)))
        (switch-to-buffer
         (nth (mod (+ (or pos (if (plusp dir) -1 0)) dir)
                   (length tabs))
              tabs))))))

(define-command vs-tab-next-file () ()
  (vs-tab-cycle 1))

(define-command vs-tab-prev-file () ()
  (vs-tab-cycle -1))

;; 旧 multiplexer 绑定退位：先清掉该键串既有登记再落键，否则帮助页
;; 一行两条（重载配置也不会复加）。
(setf *vs-binding-registry*
      (remove-if (lambda (e)
                   (member (first e) '("C-Tab" "Shift-C-Tab")
                           :test #'string=))
                 *vs-binding-registry*))
(vs-bind "C-Tab" :lem-user "VS-TAB-NEXT-FILE" "ui" "下一个 Tab")
(vs-bind "Shift-C-Tab" :lem-user "VS-TAB-PREV-FILE" "ui" "上一个 Tab")
;; --- 终端（VSCode Ctrl+` / Ctrl+J toggle 面板；双通道设计见 50-terminal） ---
;; 终端 buffer 内 mode keymap 的 undefined-key 透传优先，全局绑定不可达，
;; 聚焦时局部覆盖键（M-` / C-`；C-j 与 Return 同码 0x0A 不绑，保留多行
;; 输入）由 50-terminal 在 mode keymap 显式落键。
(vs-bind "C-j" :lem-user "VSCODE-TOGGLE-TERMINAL" "ui" "终端面板开关")
(vs-bind "M-j" :lem "NEXT-LINE" "nav" "光标下移（原 C-j 退位）")
(vs-bind "C-`" :lem-user "VSCODE-TOGGLE-TERMINAL" "ui" "终端面板开关（kitty 协议）")
(vs-bind "M-`" :lem-user "VSCODE-TOGGLE-TERMINAL" "ui" "终端面板开关")
;; --- F2 符号重命名（LSP） ---
(vs-bind "F2" :lem-lsp-mode "LSP-RENAME" "code" "重命名符号（LSP）")
;; --- Code Action（VSCode C-. 快速修复/重构菜单，LSP） ---
(vs-bind "C-." :lem-lsp-mode "LSP-CODE-ACTION" "code" "代码操作（快速修复/重构，LSP）")
;; --- 转到符号（VSCode Ctrl+Shift+O 同位；LSP documentSymbol，
;;     结果渲染进 peek 内联视图，Enter 跳转 / Esc 或 q 退出；
;;     命令是 define-command 产物但未导出，vs$ find-symbol 可达，
;;     与下方 LSP-RENAME 同法） ---
(vs-bind "Shift-C-o" :lem-lsp-mode "LSP-DOCUMENT-SYMBOL" "code" "转到文件内符号（大纲）")
;; --- 多光标（VSCode Ctrl+D 同位键：isearch 活动时逐个命中加光标，
;;     非搜索态安全 no-op；Delete 键仍承担删字符） ---
(vs-bind "C-d" :lem/isearch "ISEARCH-ADD-CURSOR-TO-NEXT-MATCH" "editor"
         "多光标：查找时逐个命中加光标")
;; --- 多光标上下加光标（VSCode Ctrl+Alt+Down/Up 同位；next-line 是
;;     上游命令（lem-core/commands/multiple-cursors 经 :lem reexport），
;;     previous-line 上游无对应，绑自研 wrapper（定义见自研命令区）。
;;     注意 C-M-n/p 已被 isearch 局部 keymap 占为逐命中加光标，本组
;;     全局键与其互不干扰） ---
(vs-bind "C-M-Down" :lem "ADD-CURSORS-TO-NEXT-LINE" "code" "在下方加光标（多光标）")
(vs-bind "C-M-Up" :lem-user "VS-ADD-CURSORS-TO-PREVIOUS-LINE" "code" "在上方加光标（多光标）")
;; isearch 局部 keymap 默认键（上游 *isearch-keymap* 绑定，仅 isearch
;; 活动期内生效；与上面 C-d 同族，不经 vs-bind 只进帮助页）：
(vs-help-note "editor" "C-M-n" "多光标：查找时在下一命中处加光标（isearch 内）")
(vs-help-note "editor" "C-M-p" "多光标：查找时在上一命中处加光标（isearch 内）")
;; --- 行操作（VSCode C-S-k / C-S-d 删除整行；上游 KILL-WHOLE-LINE 为
;;     define-command 产物可直接绑，两键同绑防终端拦截差异） ---
(vs-bind "Shift-C-k" :lem "KILL-WHOLE-LINE" "editor" "删除整行")
(vs-bind "Shift-C-d" :lem "KILL-WHOLE-LINE" "editor" "删除整行（备用）")
;; --- 行移动/复制（VSCode Alt+Up/Down 移动行、Shift+Alt+Down 复制行；
;;     M-方向已被窗口焦点占用，此处用 M-S- 系：M-S-Up/Down 移动行、
;;     M-S-d 复制行。命令定义见上自研区，v42-v44 探针确认键全局空闲） ---
(vs-bind "M-S-Up" :lem-user "VS-MOVE-LINE-UP" "editor" "上移当前行")
(vs-bind "M-S-Down" :lem-user "VS-MOVE-LINE-DOWN" "editor" "下移当前行")
(vs-bind "M-S-d" :lem-user "VS-DUPLICATE-LINE" "editor" "复制当前行到下方")
;; --- 换行开关（VSCode Alt+Z；命令定义在 60-editor-config） ---
(vs-bind "M-z" :lem-user "VSCODE-TOGGLE-LINE-WRAP" "editor" "切换自动换行")
;; --- 右键菜单（define-key 不接受 Mouse-Right 键串，parse error；
;;     接线在 60-editor-config：around 方法先走原分发再调自研
;;     VSCODE-CONTEXT-MENU（75-context-menu），与 Shift-F10 同命令） ---
(vs-help-note "editor" "鼠标右键" "上下文菜单（同 Shift-F10）")

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
;; --- 编辑器组焦点（VSCode C-1/2/3；终端面板不占组号，无对应组时 no-op） ---
(defun vs-editor-windows ()
  "编辑器组窗口（window-list 排除终端面板；侧栏是 leftside 不在其中）。"
  (let ((tb (ignore-errors (vs-terminal-buffer))))
    (if tb
        (remove-if (lambda (w) (eq (window-buffer w) tb)) (window-list))
        (window-list))))

(define-command vs-focus-group-1 () ()
  (let ((ws (vs-editor-windows)))
    (when (first ws) (switch-to-window (first ws)))))

(define-command vs-focus-group-2 () ()
  (let ((ws (vs-editor-windows)))
    (when (second ws) (switch-to-window (second ws)))))

(define-command vs-focus-group-3 () ()
  (let ((ws (vs-editor-windows)))
    (when (third ws) (switch-to-window (third ws)))))

(vs-bind "C-1" :lem-user "VS-FOCUS-GROUP-1" "window" "焦点到第 1 编辑器组")
(vs-bind "C-2" :lem-user "VS-FOCUS-GROUP-2" "window" "焦点到第 2 编辑器组")
(vs-bind "C-3" :lem-user "VS-FOCUS-GROUP-3" "window" "焦点到第 3 编辑器组")
(vs-bind "M-g g" :lem "GOTO-LINE" "nav" "跳转到行")
(vs-bind "Shift-C-p" :lem "EXECUTE-COMMAND" "nav" "命令面板（M-x 等价）")
(vs-bind "Shift-C-w" :lem-user "VS-KILL-CURRENT-BUFFER" "editor" "关闭当前 buffer（不问名）")
(vs-bind "C-=" :lem "FONT-SIZE-INCREASE" "ui" "字号增大")
(vs-bind "C--" :lem "FONT-SIZE-DECREASE" "ui" "字号减小")
(vs-bind "C-F12" :lem/language-mode "FIND-DEFINITIONS" "code" "跳转定义")
(vs-bind "Shift-C-F12" :lem/language-mode "FIND-REFERENCES" "code" "查找引用（peek 内联视图）")
;; M-F12（VSCode Alt+F12 Peek 定义）不设：上游无独立 peek-definition
;; 命令，peek 内联视图即 FIND-DEFINITIONS 多结果时的展示路径
;; （language-mode:display-xref-locations：多结果 peek 窗口、单结果直接
;; 跳转+高亮），与 C-F12 同管线；要做「永不跳转的纯 peek」得克隆上游
;; 未导出渲染内部（call-with-collecting-sources/xref-insert-headline/
;; sort-xref-locations），脆弱且不值，故放弃。
(vs-bind "F1" :lem-user "VS-TRANSIENT-SHOW" "help" "键位菜单（选组→选键→执行）")
(vs-bind "C-c h" :lem-user "VS-SHOW-KEYBINDINGS" "help" "键位帮助页（静态全量）")

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
(vs-help-note "nav" "F3 / Shift-F3" "查找下一个 / 上一个（isearch 高亮）")

;; --- nightly 内置默认键收编（上游 global keymap 已绑，只进帮助页） ---
(vs-help-note "editor" "C-u" "数字参数前缀（C-u 3 → 三倍重复）")
(vs-help-note "editor" "M-0..M-9 / M--" "数字参数 / 负数参数")
(vs-help-note "editor" "C-x ( / C-x )" "键盘宏 录制开始 / 结束")
(vs-help-note "editor" "C-x e" "键盘宏 执行（C-u n 连跑 n 次）")
(vs-help-note "editor" "C-x SPC" "矩形选区模式（列选区；常规复制/剪切按列生效，C-o 插列、C-t 填串）")
(vs-help-note "editor" "M-x query-replace-symbol" "按符号边界替换")
(vs-help-note "editor" "M-%" "查找替换（isearch 通道；VSCode C-h 同位）")
(vs-help-note "editor" "C-Space / C-@" "设置选区标记（VSCode Shift+方向同位，默认已绑）")
(vs-help-note "editor" "C-Shift-Backspace" "删除整行（上游默认键）")
(vs-help-note "editor" "C-z 数字 0-9" "原 multiplexer 数字快切：已被撤销覆盖，仅剩 C-Tab 顺序切换")
(vs-help-note "code" "C-c h" "hover 文档（LSP buffer 内，同鼠标悬停；非 LSP buffer 是全局帮助页）")
(vs-help-note "code" "鼠标悬停" "hover 文档（webview 前端原生）")
