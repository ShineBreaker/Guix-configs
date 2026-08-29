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
  (format *error-output* "~&; [lem] 符号缺失被跳过: ~S~%" sym)
  nil)

(defun vs-call (pkg name &rest args)
  "动态解析并调用；符号缺失只告警返回 nil。"
  (let ((sym (vs$ pkg name)))
    (if sym
        (apply sym args)
        (vs-warn (list pkg name)))))

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
;;;    镜像已内置：LSP / dashboard / copilot / markdown / base16 / 语言 modes / filer 骨架
;;;    需补载：terminal（vterm）/ legit（git）/ patch-mode（legit 依赖）
;;; ============================================================

(load-lem-source "extensions/patch-mode/patch-mode.lisp")

;; terminal：serial 顺序 ffi → terminal → terminal-mode（ffi 里 terminal.so 为 store 绝对路径）
(load-lem-source "extensions/terminal/ffi.lisp")
(load-lem-source "extensions/terminal/terminal.lisp")
(load-lem-source "extensions/terminal/terminal-mode.lisp")

;; process（纯 Lisp 进程管理）→ shell-mode（交互式 shell buffer）。
;; 启动终端面板用 shell-mode：vterm 的 C 层 forkpty 在 SBCL 多线程下
;; 随机失败（实测 fish 进程静默消失、面板恒空白），shell-mode 走
;; uiop:run-program 稳定；TUI 全屏程序（htop 等）不支持属可接受折衷。
(load-lem-source "extensions/process/package.lisp")
(load-lem-source "extensions/process/process.lisp")
(load-lem-source "extensions/process/stream.lisp")
(load-lem-source "extensions/shell-mode/shell-mode.lisp")

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
;;; 3. Nerd Font 图标（codicon 集）
;;;    终端字体 Maple Mono NF CN；码点已经 fontTools cmap 逐一验证在册，
;;;    git-branch 用经典 U+E0A0（cod-git_branch U+EC6F 本字体未收录）。
;;;    PUA 区单宽字形，wcwidth=1，无双宽陷阱。
;;; ============================================================

(defparameter *vs-icons*
  '((:files . #xEAF0) (:search . #xEA6D) (:scm . #xEA68) (:debug . #xEB91)
    (:extensions . #xEAE6) (:account . #xEB99) (:gear . #xEAF8)
    (:chevron-right . #xEAB6) (:chevron-down . #xEAB4)
    (:folder . #xEA83) (:folder-opened . #xEAF7)
    (:file . #xEA7B) (:file-code . #xEAE9)
    (:branch . #xF418) (:error . #xEA87) (:warning . #xEA6C)
    (:sync . #xEA77) (:ellipsis . #xEA7C) (:refresh . #xEB37)))

(defun vs-icon (name)
  (let ((code (cdr (assoc name *vs-icons*))))
    (if code (code-char code) #\Space)))

;; 同步注册进 lem icon 系统（icon-string "vscode-folder" 等可查）
(let ((reg (or (vs$ :lem "REGISTER-ICON")
               (vs$ :lem/common/character/icon "REGISTER-ICON"))))
  (when reg
    (dolist (i *vs-icons*)
      (funcall reg (format nil "vscode-~A" (string (car i))) (cdr i)))))

;;; ============================================================
;;; 4. 主题：vscode-dark-modern（运行时构造，杜绝编译期符号风险）
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
                  :foreground "#CCCCCC" :background "#181818")))))
  (setf (gethash "vscode-dark-modern" lem-core::*color-themes*)
        (lem-core::make-color-theme :specs specs :parent "lem-default")))

;; 载入（load-theme 同时把主题名持久化到 ~/.config/lem/config.lisp）
(load-theme "vscode-dark-modern")

;;; ============================================================
;;; 5. Explorer 常驻侧栏（VSCode 侧边栏复刻）
;;;    架构：lem 框架级 leftside window（make-leftside-window）承载
;;;    自绘 buffer —— EXPLORER 标题 + 内嵌 Activity 图标行（grilling 拍板
;;;    形态）+ 工作区 section + 文件树（目录记忆 + git 状态染色）。
;;;    fbar（浮窗文件树）已被本方案取代并移除。
;;; ============================================================

;; --- 侧栏 attribute（直接定义、不经主题：load-theme 不会覆盖） ---
(define-attribute vs-sidebar-bg (t :foreground "#CCCCCC" :background "#181818"))
(define-attribute vs-explorer-title (t :foreground "#CCCCCC" :background "#181818" :bold t))
(define-attribute vs-explorer-titlebar (t :foreground "#9D9D9D" :background "#181818"))
(define-attribute vs-activity-active (t :foreground "#FFFFFF" :background "#181818" :bold t))
(define-attribute vs-activity-inactive (t :foreground "#6E7681" :background "#181818"))
(define-attribute vs-section-header (t :foreground "#CCCCCC" :background "#181818" :bold t))
(define-attribute vs-tree-chevron (t :foreground "#9D9D9D" :background "#181818"))
;; VSCode Seti 风格文件夹黄
(define-attribute vs-tree-folder (t :foreground "#C09553" :background "#181818"))
(define-attribute vs-tree-file (t :foreground "#CCCCCC" :background "#181818"))
;; git 染色（list.warningForeground 系：modified/delete/undo 系）
(define-attribute vs-git-modified (t :foreground "#E2C08D" :background "#181818"))
(define-attribute vs-git-untracked (t :foreground "#73C991" :background "#181818"))
(define-attribute vs-git-deleted (t :foreground "#C74E39" :background "#181818"))
(define-attribute vs-git-conflict (t :foreground "#E4676B" :background "#181818"))

;; --- 状态 ---
(defparameter *vs-explorer-buffer-name* "*Explorer*")
(defparameter *vs-explorer-width* 34 "VSCode Side Bar ≈300px ≈ 34 列")
(defparameter *vs-explorer-root* nil)
(defparameter *vs-open-dirs* (make-hash-table :test 'equal)
  "展开状态记忆：目录 namestring → t（侧栏关闭重开后仍保持）")
(defparameter *vs-git-status* (make-hash-table :test 'equal)
  "相对路径 → :modified/:untracked/:deleted/:conflict")
(defparameter *vs-code-exts*
  '("lisp" "lsp" "scm" "el" "py" "c" "h" "cc" "cpp" "rs" "go" "js" "ts"
    "json" "yaml" "yml" "toml" "nix" "sh" "org" "md"))

;; --- 工作区根探测：向上走 .git（与 VSCode 默认 workspace 语义一致） ---
(defun vs-project-root ()
  (labels ((walk (dir count)
             (cond ((or (null dir) (> count 32)
                        (equal (namestring dir) "/"))
                    nil)
                   ((probe-file (merge-pathnames ".git" dir))
                    dir)
                   (t (walk (uiop:pathname-parent-directory-pathname dir)
                            (1+ count))))))
    (let ((start (or (ignore-errors (buffer-directory (current-buffer)))
                     (uiop:getcwd))))
      (or (walk start 0) start))))

;; --- git 状态表（文件 + 祖先目录染色；优先级 conflict>deleted>modified>untracked） ---
(defun vs-status-priority (s)
  (ecase s (:conflict 4) (:deleted 3) (:modified 2) (:untracked 1)))

(defun vs-refresh-git-status ()
  (let ((table (make-hash-table :test 'equal)))
    (when *vs-explorer-root*
      (ignore-errors
        (dolist (line (uiop:run-program
                       (list "git" "-C" (namestring *vs-explorer-root*)
                             "status" "--porcelain" "-uall")
                       :output :lines :ignore-error-status t))
          (when (>= (length line) 4)
            (let* ((xy (subseq line 0 2))
                   (raw (subseq line 3))
                   ;; rename「old -> new」取 new；C 引号路径剥外层引号
                   (path (let ((p (if (and (>= (length raw) 2)
                                           (char= (char raw 0) #\"))
                                      (string-trim '(#\") raw)
                                      raw)))
                           (let ((arrow (search " -> " p)))
                             (if arrow (subseq p (+ arrow 4)) p))))
                   (status (cond ((find #\U xy) :conflict)
                                 ((find #\D xy) :deleted)
                                 ((char= (char line 0) #\?) :untracked)
                                 ((find #\A xy) :untracked)
                                 (t :modified))))
              (setf (gethash path table) status)
              ;; 祖先目录按最高优先级染色
              (loop :for i :from 0 :below (length path)
                    :when (char= (char path i) #\/)
                    :do (let ((dir (subseq path 0 i)))
                          (let ((old (gethash dir table)))
                            (when (or (null old)
                                      (< (vs-status-priority old)
                                         (vs-status-priority status)))
                              (setf (gethash dir table) status))))))))))
    (setf *vs-git-status* table)))

(defun vs-status-attribute (s)
  (ecase s
    (:modified 'vs-git-modified)
    (:untracked 'vs-git-untracked)
    (:deleted 'vs-git-deleted)
    (:conflict 'vs-git-conflict)))

;; --- 文件系统辅助 ---
(defun vs-item-name (path)
  (if (uiop:directory-pathname-p path)
      (car (last (pathname-directory path)))
      (file-namestring path)))

(defun vs-relative (path)
  "相对工作区根的 namestring；目录去掉尾斜杠（与 git status 键对齐）。"
  (let ((s (enough-namestring path *vs-explorer-root*)))
    (if (and (plusp (length s))
             (char= (char s (1- (length s))) #\/))
        (subseq s 0 (1- (length s)))
        s)))

(defun vs-dir-children (dir)
  "子项列表：目录在前、各自大小写不敏感字典序；排除 .git。"
  (sort
   (remove-if (lambda (p)
                (member (vs-item-name p) '(".git") :test #'equal))
              (list-directory dir))
   (lambda (a b)
     (let ((da (uiop:directory-pathname-p a))
           (db (uiop:directory-pathname-p b)))
       (cond ((and da db) (string-lessp (vs-item-name a) (vs-item-name b)))
             (da t)
             (db nil)
             (t (string-lessp (vs-item-name a) (vs-item-name b))))))))

;; --- 渲染 ---
(defun vs-pad-to-width (point)
  (let ((pad (- *vs-explorer-width* (point-charpos point))))
    (when (plusp pad)
      (insert-string point (make-string pad :initial-element #\space)
                     :attribute 'vs-sidebar-bg))))

(defun vs-explorer-render-header (point)
  ;; 标题行（EXPLORER + 右缘 ⋯）
  (insert-string point " EXPLORER" :attribute 'vs-explorer-title)
  (vs-pad-to-width point)
  (insert-string point (string (vs-icon :ellipsis))
                 :attribute 'vs-explorer-titlebar)
  (insert-character point #\newline)
  ;; Activity Bar 内嵌图标行（explorer 激活白，其余灰）
  (let ((icons '(:files :search :scm :debug :extensions)))
    (insert-string point " " :attribute 'vs-sidebar-bg)
    (dolist (i icons)
      (insert-string point (string (vs-icon i))
                     :attribute (if (eq i :files)
                                    'vs-activity-active
                                    'vs-activity-inactive))
      (insert-string point "  " :attribute 'vs-sidebar-bg))
    (vs-pad-to-width point)
    (insert-character point #\newline))
  (insert-character point #\newline)
  ;; 工作区 section 头（▾ 大写项目名，VSCode 形态）
  (insert-string point (format nil " ~C " (vs-icon :chevron-down))
                 :attribute 'vs-tree-chevron)
  (insert-string point (string-upcase
                        (or (car (last (pathname-directory *vs-explorer-root*)))
                            "WORKSPACE"))
                 :attribute 'vs-section-header)
  (vs-pad-to-width point)
  (insert-character point #\newline))

(defun vs-insert-tree-line (point path depth)
  (let* ((dir-p (uiop:directory-pathname-p path))
         (open (and dir-p (gethash (namestring path) *vs-open-dirs*)))
         (name (vs-item-name path))
         (status (gethash (vs-relative path) *vs-git-status*))
         (name-attr (cond (status (vs-status-attribute status))
                          (dir-p 'vs-tree-folder)
                          (t 'vs-tree-file)))
         (glyph (cond ((and dir-p open) (vs-icon :folder-opened))
                      (dir-p (vs-icon :folder))
                      ((member (pathname-type path) *vs-code-exts*
                               :test #'equalp)
                       (vs-icon :file-code))
                      (t (vs-icon :file)))))
    (insert-string point (make-string (* 2 depth) :initial-element #\space)
                   :attribute 'vs-sidebar-bg)
    (if dir-p
        (insert-string point
                       (string (vs-icon (if open :chevron-down :chevron-right)))
                       :attribute 'vs-tree-chevron)
        (insert-string point " " :attribute 'vs-sidebar-bg))
    (insert-string point " " :attribute 'vs-sidebar-bg)
    (insert-string point (string glyph) :attribute name-attr)
    (insert-string point " " :attribute 'vs-sidebar-bg)
    (insert-string point name :attribute name-attr)
    (vs-pad-to-width point)
    ;; 整行挂 item 属性（路径 + 目录标志），供 select/折叠命令读取
    (with-point ((start point))
      (line-start start)
      (put-text-property start point :vs-item
                         (list :path path :dir-p dir-p)))))

(defun vs-render-dir (point dir depth)
  (dolist (child (vs-dir-children dir))
    (let ((open (and (uiop:directory-pathname-p child)
                     (gethash (namestring child) *vs-open-dirs*))))
      (vs-insert-tree-line point child depth)
      (insert-character point #\newline)
      (when open
        (vs-render-dir point child (1+ depth))))))

(defun vs-explorer-buffer ()
  (or (get-buffer *vs-explorer-buffer-name*)
      (let ((buffer (make-buffer *vs-explorer-buffer-name* :temporary t)))
        (change-buffer-mode buffer 'vscode-explorer-mode)
        (setf (not-switchable-buffer-p buffer) t)
        buffer)))

(defun vs-explorer-render ()
  (when *vs-explorer-root*
    (let ((buffer (vs-explorer-buffer)))
      (when buffer
        (handler-case
            (progn
              (vs-refresh-git-status)
              (with-buffer-read-only buffer nil
                (let ((line (line-number-at-point (buffer-point buffer))))
                  (erase-buffer buffer)
                  (vs-explorer-render-header (buffer-point buffer))
                  (vs-render-dir (buffer-point buffer) *vs-explorer-root* 0)
                  (move-to-line (buffer-point buffer) line))))
          (error (e)
            (message "Explorer 渲染失败: ~A" e)))))))

;; --- major mode + 键位 ---
(defparameter *vs-explorer-keymap* (make-keymap))

(define-major-mode vscode-explorer-mode ()
    (:name "Explorer"
     :keymap *vs-explorer-keymap*)
  (setf (variable-value 'line-wrap :buffer (current-buffer)) nil)
  (setf (buffer-read-only-p (current-buffer)) t))

(defun vs-item-at-point ()
  (text-property-at (back-to-indentation (current-point)) :vs-item))

(defun vs-focus-main-window ()
  (unless (member (current-window) (window-list))
    (setf (current-window) (car (window-list)))))

(define-command vscode-explorer-select () ()
  "Return：目录展开/折叠，文件在主窗打开并把焦点交还编辑区。"
  (let ((item (vs-item-at-point)))
    (when item
      (if (getf item :dir-p)
          (progn
            (let ((key (namestring (getf item :path))))
              (if (gethash key *vs-open-dirs*)
                  (remhash key *vs-open-dirs*)
                  (setf (gethash key *vs-open-dirs*) t)))
            (vs-explorer-render))
          (progn
            (vs-focus-main-window)
            (find-file (getf item :path)))))))

(define-command vscode-explorer-toggle-dir () ()
  "Tab：只切换展开态，不打开文件。"
  (let ((item (vs-item-at-point)))
    (when (and item (getf item :dir-p))
      (let ((key (namestring (getf item :path))))
        (if (gethash key *vs-open-dirs*)
            (remhash key *vs-open-dirs*)
            (setf (gethash key *vs-open-dirs*) t)))
      (vs-explorer-render))))

(define-command vscode-explorer-collapse () ()
  "Left：折叠当前目录。"
  (let ((item (vs-item-at-point)))
    (when (and item (getf item :dir-p))
      (remhash (namestring (getf item :path)) *vs-open-dirs*)
      (vs-explorer-render))))

(define-command vscode-explorer-expand () ()
  "Right：展开当前目录。"
  (let ((item (vs-item-at-point)))
    (when (and item (getf item :dir-p))
      (setf (gethash (namestring (getf item :path)) *vs-open-dirs*) t)
      (vs-explorer-render))))

(define-command vscode-explorer-refresh () ()
  "r/g：重扫文件系统 + git 状态。"
  (vs-explorer-render))

(define-key *vs-explorer-keymap* "Return" 'vscode-explorer-select)
(define-key *vs-explorer-keymap* "Space" 'vscode-explorer-select)
(define-key *vs-explorer-keymap* "Tab" 'vscode-explorer-toggle-dir)
(define-key *vs-explorer-keymap* "Left" 'vscode-explorer-collapse)
(define-key *vs-explorer-keymap* "Right" 'vscode-explorer-expand)
(define-key *vs-explorer-keymap* "r" 'vscode-explorer-refresh)
(define-key *vs-explorer-keymap* "g" 'vscode-explorer-refresh)

;; Activity 图标行对应视图（1-5 跳转；4/5 暂无对应物）
(defun vs-run-command (pkg name)
  (vs-focus-main-window)
  (vs-call pkg name))

(define-command vscode-activity-explorer () ()
  (message "Explorer"))

(define-command vscode-activity-search () ()
  (vs-run-command :lem/grep "PROJECT-GREP"))

(define-command vscode-activity-scm () ()
  (vs-run-command :lem/legit "LEGIT-STATUS"))

(define-command vscode-activity-debug () ()
  (message "Run and Debug：暂无对应物"))

(define-command vscode-activity-extensions () ()
  (message "Extensions：暂无对应物"))

(define-key *vs-explorer-keymap* "1" 'vscode-activity-explorer)
(define-key *vs-explorer-keymap* "2" 'vscode-activity-search)
(define-key *vs-explorer-keymap* "3" 'vscode-activity-scm)
(define-key *vs-explorer-keymap* "4" 'vscode-activity-debug)
(define-key *vs-explorer-keymap* "5" 'vscode-activity-extensions)

;; --- 侧栏开关（Ctrl+B / Ctrl+Shift+E） ---
(defun vs-explorer-window ()
  "本侧栏专属的 leftside 窗口（按 buffer major-mode 判定归属，避免误认 filer 等其它侧窗）。"
  (let ((accessor (vs$ :lem-core "FRAME-LEFTSIDE-WINDOW")))
    (let ((w (and accessor (funcall accessor (current-frame)))))
      (and w
           (eq 'vscode-explorer-mode
               (buffer-major-mode (window-buffer w)))
           w))))

(defun vs-explorer-buffer ()
  "当前侧栏正在显示的 buffer（刷新路径用；开启路径每次造全新 buffer）。"
  (let ((w (vs-explorer-window)))
    (and w (window-buffer w))))

(define-command vscode-toggle-sidebar () ()
  "VSCode Ctrl+B：显示/隐藏 Explorer 侧栏（展开状态存全局表，跨开关保持）。
开启路径每次造全新 buffer：lem 2.3.0 里经 vs-explorer-buffer 复用的 buffer
会被 display 层拒绘（实测恒空白，全新 buffer 同管线正常），unique 名避开
get-buffer 撞名；树状态在 *vs-open-dirs*，buffer 无状态损失。"
  (let ((win (vs-explorer-window)))
    (if win
        (progn
          (when (eq (current-window) win)
            (vs-focus-main-window))
          (delete-leftside-window))
        (let ((buffer (make-buffer (unique-buffer-name *vs-explorer-buffer-name*)
                                   :temporary t)))
          (change-buffer-mode buffer 'vscode-explorer-mode)
          (setf (not-switchable-buffer-p buffer) t)
          (setf *vs-explorer-root* (vs-project-root))
          (vs-refresh-git-status)
          (with-buffer-read-only buffer nil
            (erase-buffer buffer)
            (vs-explorer-render-header (buffer-point buffer))
            (vs-render-dir (buffer-point buffer) *vs-explorer-root* 0)
            (move-to-line (buffer-point buffer) 1))
          (make-leftside-window buffer :width *vs-explorer-width*)))))

;; --- resize 自愈：上游只给 rightside 挂 resize 补偿（window.lisp 只调
;; resize-rightside-window），leftside 的 ncurses view 在终端尺寸变化后
;; 失效且重开也无法恢复（实测恒空白）。治疗动作（关开一遍侧栏，toggle
;; 开启路径每次造 fresh window+view）不能在 size-change 钩子内同步执行
;; ——开关窗口本身又触发 size-change，重入死锁。改为标志位，post-command
;; 安全期执行；run-hooks 会传 window 参数，签名必须收下。
(defparameter *vs-need-heal* nil)
(defparameter *vs-healing* nil)

(defun vs-resize-heal (window)
  (declare (ignore window))
  (setf *vs-need-heal* t))

;;; ============================================================
;;; 6. 终端面板：VSCode Ctrl+` toggle 语义
;;;    显示 = 主窗底部切 1/3；隐藏 = 删窗不杀 buffer（vterm 进程保活）。
;;;    terminal-mode 的 execute 方法会把一切命令改道喂给 vterm，
;;;    本命令及编辑区高频键必须登记进 *bypass-commands* 旁路表。
;;; ============================================================

(defun vs-terminal-buffer ()
  (vs-call :lem-terminal/terminal "FIND-TERMINAL-BUFFER"))

(defun vs-main-window ()
  (if (member (current-window) (window-list))
      (current-window)
      (car (window-list))))

(define-command vscode-toggle-terminal () ()
  "VSCode Ctrl+`：显示/隐藏底部终端面板。
显示走上游原生 TERMINAL 命令（pop-to-buffer 标准 split+redraw 路径；
post-command 钩子内手动 split-window-vertically 实测会因重绘时序产生
空白窗污染）；隐藏只删窗不杀 buffer（vterm 进程保活，重开续用会话）。"
  (let* ((tbuf (vs-terminal-buffer))
         (twin (and tbuf (find tbuf (window-list) :key #'window-buffer))))
    (if twin
        (if (cdr (window-list))
            (delete-window twin)
            (message "最后一个窗口，不能隐藏终端"))
        (vs-call :lem-terminal/terminal-mode "TERMINAL" nil))))

;; 终端焦点下仍生效的编辑区命令（VSCode commandsToSkipShell 对应物）。
;; 上游 *bypass-commands* 的消费处用 (member ... :test #'typep) 把命令符号
;; 当类型指示符，SBCL 对非类符号直接炸 unknown type specifier（潜伏 bug，
;; 终端内执行任何 bypass 命令必触发）。这里重定义 execute 方法改用 eq，
;; 原生 bypass 列表与下述追加项一并修复。
(let ((execute-sym (vs$ :lem "EXECUTE"))
      (mode-sym (vs$ :lem-terminal/terminal-mode "TERMINAL-MODE"))
      (input-sym (vs$ :lem-terminal/terminal-mode "TERMINAL-INPUT"))
      (bypass-sym (vs$ :lem-terminal/terminal-mode "*BYPASS-COMMANDS*")))
  (when (and execute-sym mode-sym input-sym bypass-sym)
    (eval
     `(sb-ext:without-package-locks
        (defmethod ,execute-sym ((mode ,mode-sym) command argument)
          (declare (ignore argument))
          (if (member command (symbol-value ',bypass-sym) :test #'eq)
              (call-next-method)
              (,input-sym)))))
    (dolist (cmd (list 'vscode-toggle-terminal
                       'vscode-toggle-sidebar
                       (vs$ :lem "FIND-FILE-RECURSIVELY")
                       (vs$ :lem "SAVE-BUFFER")
                       (vs$ :lem "SPLIT-ACTIVE-WINDOW-HORIZONTALLY")
                       (vs$ :lem/legit "LEGIT-STATUS")
                       (vs$ :lem/grep "PROJECT-GREP")))
      (when cmd
        (pushnew cmd (symbol-value bypass-sym))))))

;;; ============================================================
;;; 7. 布局：VSCode 式 modeline + 行号
;;;    editor variable 同样符号身份敏感：必须用定义包的符号
;;; ============================================================

(defun vs-setvar (pkg name val)
  (let ((sym (vs$ pkg name)))
    (if sym
        (setf (variable-value sym :global) val)
        (vs-warn (list pkg name)))))

;; VSCode Tab 栏由 frame-multiplexer 承担（after-init-hook 默认开启、带编号、
;; C-z 数字快切）；tabbar（buffer 列表条）与之重复，保持默认关闭

;; VSCode Status Bar 风格：左（ 分支）· 右（Ln,Col / 编码 / EOL / 语言）
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
            (values (format nil "  ~C ~A " (vs-icon :branch) branch)
                    'modeline-name-attribute)))))))

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
;;; 8. 键位：混合模式
;;;    VSCode 高频核心键（C-p/C-f/C-s/C-b/C-`/C-\/C-Tab/F2）覆盖 lem 同位移动键，
;;;    被覆盖的移动退到 Meta 系（与 Emacs 惯例一致）；C-x/C-c 前缀体系完整保留
;;;    键语法注意：Shift 必须写全拼 "Shift-"（S- 是 super！）
;;; ============================================================

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
;; --- 终端（VSCode Ctrl+` / Ctrl+J toggle 面板） ---
;; 现实约束：Ctrl+` 在传统终端输入协议不可表达（kitty legacy 下就是普通 `；
;; 扩展协议序列 ncurses 不解，ESC+` 又被 terminal-mode 的 Escape 键拆解）。
;; Ctrl+J 是 VSCode 官方 togglePanel 键（0x0A 恒可表达）——但它仅在编辑区
;; 生效：终端聚焦时 0x0A 被 terminfo 报为 Return、terminal-key-return 直喂
;; vterm（换行语义，不可牺牲）。终端内隐藏面板走 M-x vscode-toggle-terminal
;; 或 M-`（输入层若能解出该键则生效）。
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

;;; ============================================================
;;; 9. 启动行为与其它
;;; ============================================================

;; VSCode 开箱布局：启动即展开 Explorer 侧栏 + 底部终端面板，焦点停在编辑区。
;; 注意：after-init 阶段创建的 side window + buffer 会被 display 层拒绘
;; （lem 2.3.0 实测恒空白；交互期同样代码显示正常），故挂 post-command
;; 首次触发——此时命令循环与重绘世界已就绪。remove-hook 是宏不可 funcall，
;; 用标志位空转代替自摘除。
(defparameter *vs-startup-opened* nil)

(defun vs-open-workspace-on-startup ()
  (unless *vs-startup-opened*
    (setf *vs-startup-opened* t)
    ;; 1) Explorer 侧栏（leftside 独立槽位，不影响主窗树）
    (vscode-toggle-sidebar)
    ;; 2) 底部终端面板：手动垂直切出下 1/3 塞入 shell-mode buffer。
    ;;    split 必须晚于侧栏——make-leftside-window 的 balance-windows
    ;;    会把已 split 的窗树重新均分（先 split 后侧栏实测比例失控）。
    (let* ((before (window-list))
           (root (vs-main-window))
           (total (window-height root))
           (panel (max 6 (floor total 3))))
      (split-window-vertically root :height (max 2 (- total panel)))
      (let ((new (find-if-not (lambda (w) (member w before))
                              (window-list))))
        (when new
          (setf (current-window) new)
          (let ((buf (vs-call :lem-shell-mode "RUN-SHELL-INTERNAL")))
            (when buf (switch-to-buffer buf))))))
    ;; 3) 焦点交还主编辑区
    (vs-focus-main-window)))
(add-hook *post-command-hook* 'vs-open-workspace-on-startup)
(add-hook *window-size-change-functions* 'vs-resize-heal)

;; dashboard（VSCode 欢迎页）镜像内置默认开启
;; line-wrap 关闭（VSCode 默认不换行；Alt+Z 切换语义迭代阶段接）
(vs-setvar :lem "LINE-WRAP" nil)
