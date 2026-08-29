;;; init.lisp — Lem 编辑器配置：VSCode Dark Modern 一比一复刻
;;;
;;; 部署：dotfiles/mutable/lem/ 经 GNU Stow 直链 ~/.config/lem/（改源即生效）
;;; 色值权威源：microsoft/vscode dark_modern.json
;;;   （调研存档：.agents/workfile/explore/vscode-dark-spec.md）
;;;
;;; 机制约束（勿违反，详见仓库 AGENTS 记忆）：
;;; 1. 必须以 (in-package :lem-user) 开头，否则文件编译期触发包锁崩溃
;;; 2. 本文件里「包前缀引用不存在的符号」会在编译期炸死进程（handler-case
;;;    无效）。因此所有非核心符号一律 find-symbol 动态解析，找不到则跳过
;;; 3. Guix 打包的 lem 镜像内嵌 asdf output-translations 指向只读 store，
;;;    asdf:load-system 不可用；扩展加载走 read+eval 逐 form 管线

(in-package :lem-user)

;;; ============================================================
;;; 0. 动态解析辅助
;;; ============================================================

(defun vs$ (pkg name)
  "find-symbol 动态解析；包或符号不存在返回 nil。"
  (ignore-errors (find-symbol name pkg)))

(defun vs-warn (sym)
  (format *error-output* "~&; [lem] attribute/command 缺失被跳过: ~S~%" sym)
  nil)

;;; ============================================================
;;; 1. store 源码树加载器
;;; ============================================================

(defparameter *lem-source-tree*
  (asdf:system-source-directory :lem)
  "lem 自身源码树（Guix store 只读副本）。升级换 hash 后自动跟随。")

(defun load-lem-source (relpath)
  "从 store 源码树 read+eval 逐 form 加载扩展源文件。
动态绑定 *package*：扩展内部的 in-package 切换在函数返回后恢复，
否则会把本文件后续 form 的裸符号读进扩展包（普通 (load) 的语义）。
逐 form 加 handler-case：单 form 失败（如 ffi.lisp 里冗余的 asdf
相对路径探测）只告警不炸进程；真正的错误会随后续符号缺失暴露。"
  (let ((*package* *package*)
        (*readtable* *readtable*))
    (let ((path (merge-pathnames relpath *lem-source-tree*)))
      (with-open-file (in path)
        (loop :for form := (read in nil nil)
              :while form
              :do (handler-case (eval form)
                   (error (e)
                     (format *error-output* "~&; [lem] ~A: skip form ~S: ~A~%"
                             path (if (consp form) (car form) form) e)))))
      path)))

;;; ============================================================
;;; 2. 扩展加载
;;;    镜像已内置：LSP / dashboard / copilot / markdown / base16 / 语言 modes / tabbar
;;;    需补载：fbar（文件树）/ terminal（vterm）/ legit（git）/ patch-mode（legit 依赖）
;;; ============================================================

(load-lem-source "contrib/fbar/fbar.lisp")
(load-lem-source "extensions/patch-mode/patch-mode.lisp")

;; terminal：serial 顺序 ffi → terminal → terminal-mode（ffi 里 terminal.so 为 store 绝对路径）
(load-lem-source "extensions/terminal/ffi.lisp")
(load-lem-source "extensions/terminal/terminal.lisp")
(load-lem-source "extensions/terminal/terminal-mode.lisp")

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
  (load-lem-source f))

;;; ============================================================
;;; 3. 主题：vscode-dark-modern（运行时构造，杜绝编译期符号风险）
;;;    chrome 三元组：#181818（工作台镶边）/ #1F1F1F（编辑器/激活 tab）/ #2B2B2B（分隔线）
;;;    强调 #0078D4；文字三级 #FFFFFF / #CCCCCC / #9D9D9D
;;; ============================================================

(defun vs-spec (pkg name &rest args)
  "构造一条 (attribute-symbol args...) 主题规格；符号缺失返回 nil。"
  (let ((sym (vs$ pkg name)))
    (if sym (cons sym args) (vs-warn (list pkg name)))))

(let ((specs
       (remove
        nil
        (list
         ;; 工作台
         (list :display-background-mode :dark)
         (list :foreground "#CCCCCC")           ; editor.foreground
         (list :background "#1F1F1F")           ; editor.background
         (list :inactive-window-background "#181818")
         ;; base16 抽象色（isearch 等内部 attribute 按 :baseXX 引用）
         (list :base00 "#1F1F1F") (list :base01 "#252526") (list :base02 "#2B2B2B")
         (list :base03 "#6E7681") (list :base04 "#868686") (list :base05 "#CCCCCC")
         (list :base06 "#D7D7D7") (list :base07 "#FFFFFF")
         (list :base08 "#F14C4C") (list :base09 "#CE9178") (list :base0A "#B5CEA8")
         (list :base0B "#23D18B") (list :base0C "#4EC9B0") (list :base0D "#569CD6")
         (list :base0E "#C586C0") (list :base0F "#D7BA7D")
         ;; 光标 / 选区（editorCursor #AEAFAD、selection #264F78）
         (vs-spec :lem "CURSOR" :background "#AEAFAD")
         (vs-spec :lem "REGION" :foreground nil :background "#264F78")
         ;; 行号（#6E7681 / 当前行 #CCCCCC；背景必须显式，否则用 :base01）
         (vs-spec :lem/line-numbers "LINE-NUMBERS-ATTRIBUTE"
                  :foreground "#6E7681" :background "#1F1F1F")
         (vs-spec :lem/line-numbers "ACTIVE-LINE-NUMBER-ATTRIBUTE"
                  :foreground "#CCCCCC" :background "#1F1F1F")
         ;; isearch（findMatch #9E6A03 / findMatchHighlight 近似）
         (vs-spec :lem/isearch "ISEARCH-HIGHLIGHT-ACTIVE-ATTRIBUTE"
                  :foreground "#1F1F1F" :background "#9E6A03")
         (vs-spec :lem/isearch "ISEARCH-HIGHLIGHT-ATTRIBUTE"
                  :foreground "#CCCCCC" :background "#613214")
         (vs-spec :lem/isearch "UNMATCH-ISEARCH-ATTRIBUTE" :foreground "#868686")
         ;; 语法高亮（Dark+ token 色板）
         (vs-spec :lem "SYNTAX-COMMENT-ATTRIBUTE" :foreground "#6A9955")
         (vs-spec :lem "SYNTAX-KEYWORD-ATTRIBUTE" :foreground "#569CD6")
         (vs-spec :lem "SYNTAX-STRING-ATTRIBUTE" :foreground "#CE9178")
         (vs-spec :lem "SYNTAX-CONSTANT-ATTRIBUTE" :foreground "#4FC1FF")
         (vs-spec :lem "SYNTAX-FUNCTION-NAME-ATTRIBUTE" :foreground "#DCDCAA")
         (vs-spec :lem "SYNTAX-VARIABLE-ATTRIBUTE" :foreground "#9CDCFE")
         (vs-spec :lem "SYNTAX-TYPE-ATTRIBUTE" :foreground "#4EC9B0")
         (vs-spec :lem "SYNTAX-BUILTIN-ATTRIBUTE" :foreground "#569CD6")
         (vs-spec :lem "SYNTAX-WARNING-ATTRIBUTE" :foreground "#CCA700")
         ;; 诊断（error #F14C4C / warning #CCA700 / info #59A4F9）
         (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-ERROR-ATTRIBUTE" :foreground "#F14C4C")
         (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-WARNING-ATTRIBUTE" :foreground "#CCA700")
         (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-INFORMATION-ATTRIBUTE" :foreground "#59A4F9")
         (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-HINT-ATTRIBUTE" :foreground "#9D9D9D")
         ;; modeline → VSCode Status Bar（#181818 全宽条 + #CCCCCC 文字）
         (vs-spec :lem "MODELINE" :background "#181818" :foreground "#CCCCCC")
         (vs-spec :lem "MODELINE-INACTIVE" :background "#181818" :foreground "#868686")
         (vs-spec :lem "MODELINE-NAME-ATTRIBUTE" :background "#181818" :foreground "#CCCCCC")
         (vs-spec :lem "MODELINE-MAJOR-MODE-ATTRIBUTE" :background "#181818" :foreground "#CCCCCC")
         (vs-spec :lem "MODELINE-MINOR-MODES-ATTRIBUTE" :background "#181818" :foreground "#868686")
         (vs-spec :lem "MODELINE-POSITION-ATTRIBUTE" :background "#181818" :foreground "#CCCCCC")
         (vs-spec :lem "MODELINE-POSLINE-ATTRIBUTE" :background "#181818" :foreground "#CCCCCC")
         (vs-spec :lem "INACTIVE-MODELINE-NAME-ATTRIBUTE" :background "#181818" :foreground "#868686")
         (vs-spec :lem "INACTIVE-MODELINE-MAJOR-MODE-ATTRIBUTE" :background "#181818" :foreground "#868686")
         (vs-spec :lem "INACTIVE-MODELINE-MINOR-MODES-ATTRIBUTE" :background "#181818" :foreground "#6E7681")
         (vs-spec :lem "INACTIVE-MODELINE-POSITION-ATTRIBUTE" :background "#181818" :foreground "#868686")
         (vs-spec :lem "INACTIVE-MODELINE-POSLINE-ATTRIBUTE" :background "#181818" :foreground "#868686")
         ;; frame-multiplexer → VSCode Tab 栏（默认开启、带编号切换，是 VSCode
         ;; Tab 的正确对应物；激活 #1F1F1F 白字粗体 / 非激活 #181818 灰 / 栏底 #181818）
         (vs-spec :lem/frame-multiplexer "FRAME-MULTIPLEXER-ACTIVE-FRAME-NAME-ATTRIBUTE"
                  :foreground "#FFFFFF" :background "#1F1F1F" :bold t)
         (vs-spec :lem/frame-multiplexer "FRAME-MULTIPLEXER-FRAME-NAME-ATTRIBUTE"
                  :foreground "#9D9D9D" :background "#181818")
         (vs-spec :lem/frame-multiplexer "FRAME-MULTIPLEXER-BACKGROUND-ATTRIBUTE"
                  :foreground "#CCCCCC" :background "#181818")
         ;; tabbar（buffer 列表条）与 frame-multiplexer 重复，弃用（见布局节）
         ;; fbar 文件树（sideBar #181818；文件夹用 VSCode 资源管理器文件夹黄）
         (vs-spec :lem-fbar "FBAR-FILE" :foreground "#CCCCCC" :background "#181818")
         (vs-spec :lem-fbar "FBAR-DIR" :foreground "#C09553" :bold t :background "#181818")))))
  (setf (gethash "vscode-dark-modern" lem-core::*color-themes*)
        (lem-core::make-color-theme :specs specs :parent "lem-default")))

;; 载入（load-theme 同时把主题名持久化到 ~/.config/lem/config.lisp）
(load-theme "vscode-dark-modern")

;;; ============================================================
;;; 4. 布局：tabbar + VSCode 式 modeline + 行号
;;;    editor variable 同样符号身份敏感：必须用定义包的符号
;;; ============================================================

(defun vs-setvar (pkg name val)
  (let ((sym (vs$ pkg name)))
    (if sym
        (setf (variable-value sym :global) val)
        (vs-warn (list pkg name)))))

;; VSCode Tab 栏由 frame-multiplexer 承担（after-init-hook 默认开启、带编号、
;; C-z 数字快切）；tabbar（buffer 列表条）与之重复，保持默认关闭

;; VSCode Status Bar 风格：左（git 分支）· 右（Ln,Col / 编码 / EOL / 语言）
(defun vscode-modeline-branch (window)
  (declare (ignore window))
  (ignore-errors
    (let* ((file (buffer-filename (current-buffer)))
           (dir (if file
                    (make-pathname :directory (pathname-directory file))
                    (buffer-directory (current-buffer)))))
      (when dir
        (let ((branch (string-trim
                       '(#\Newline #\Space)
                       (uiop:run-program
                        (list "git" "-C" (namestring dir)
                              "rev-parse" "--abbrev-ref" "HEAD")
                        :output '(:string :stripped t)
                        :ignore-error-status t))))
          (when (and branch (plusp (length branch)))
            (values (format nil "  ~A " branch) 'modeline-name-attribute)))))))

(defun vscode-modeline-encoding (window)
  (declare (ignore window))
  (values " UTF-8 " 'modeline-minor-modes-attribute))

(defun vscode-modeline-eol (window)
  (declare (ignore window))
  (values " LF " 'modeline-minor-modes-attribute))

(defun vscode-modeline-language (window)
  (let ((name (mode-name (buffer-major-mode (window-buffer window)))))
    (values (format nil "  ~A  " name) 'modeline-major-mode-attribute)))

(let ((pos (vs$ :lem "MODELINE-POSITION")))
  (vs-setvar
   :lem "MODELINE-FORMAT"
   `(" "
     vscode-modeline-branch
     ,@(when pos `((,pos nil :right)))
     (vscode-modeline-encoding nil :right)
     (vscode-modeline-eol nil :right)
     (vscode-modeline-language nil :right))))

;; 行号 + 当前行高亮（VSCode 编辑器默认行为）
(vs-setvar :lem/line-numbers "LINE-NUMBERS" t)
(vs-setvar :lem "HIGHLIGHT-LINE" t)

;;; ============================================================
;;; 5. 键位：混合模式
;;;    VSCode 高频核心键（C-p/C-f/C-s/C-b/C-`/C-\/C-Tab/F2）覆盖 lem 同位移动键，
;;;    被覆盖的移动退到 Meta 系（与 Emacs 惯例一致）；C-x/C-c 前缀体系完整保留
;;;    键语法注意：Shift 必须写全拼 "Shift-"（S- 是 super！）
;;; ============================================================

;; VSCode Ctrl+B：侧栏（文件树）开关。fbar-on 只开不关，这里做 toggle
(define-command vscode-toggle-sidebar () ()
  (let ((win-sym (vs$ :lem-fbar "*FBAR-WINDOW*")))
    (if (and win-sym (symbol-value win-sym))
        (symbol-call-or-warn :lem-fbar "FBAR-OFF")
        (symbol-call-or-warn :lem-fbar "FBAR-ON"))))

(defun symbol-call-or-warn (pkg name)
  (let ((sym (vs$ pkg name)))
    (if sym
        (funcall (symbol-function sym))
        (vs-warn (list pkg name)))))

;; 逐条 define-key（函数式）：命令符号 find-symbol 动态解析，缺失只告警
(defun vs-bind (keyspec pkg name)
  (let ((sym (vs$ pkg name)))
    (if sym
        (define-key *global-keymap* keyspec sym)
        (vs-warn (list pkg name)))))

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
;; --- 终端（VSCode Ctrl+`） ---
(vs-bind "C-`" :lem-terminal/terminal "TERMINAL")
;; --- F2 符号重命名（LSP） ---
(vs-bind "F2" :lem-lsp-mode "LSP-RENAME")

;;; ============================================================
;;; 6. 其它
;;; ============================================================

;; dashboard（VSCode 欢迎页）镜像内置默认开启
;; line-wrap 关闭（VSCode 默认不换行；Alt+Z 切换语义迭代阶段接）
(vs-setvar :lem "LINE-WRAP" nil)

