;;; dashboard.el --- 启动仪表盘配置 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 配置启动仪表盘，集成待办列表、文件管理器、前缀键概览和鼠标工作流提示。
;; 卡片内容统一保留左右内边距，避免标题提示和双列快捷键贴边。
;; dashboard buffer 强制使用等宽字，避免 variable-pitch 下空格对齐漂移。
;;
;; 待办卡片：
;; 扫描 `org-agenda-files' 中所有未完成 TODO（不限今日），按紧急度排序：
;; 过期 DEADLINE → 今日 DEADLINE → 未来 DEADLINE → 过期 SCHEDULED → 无日期。
;; 无 DEADLINE/SCHEDULED 的纯 TODO 也会显示。
;; TODO/DONE 等状态标签单独上色，标题文字保持 `default' 前景色，避免
;; dashboard item face 把整行染成状态色。
;;
;; Daemon/Client 模式优化：
;; Dashboard 的刷新和显示通过 `literal/add-frame-hook'
;; 统一接入 daemon/client 的 frame 生命周期，确保 emacsclient
;; 启动时能够即时呈现最新内容。
;; 为避免 frame hook 过早触发导致错过真正的 client 占位缓冲区，dashboard
;; 调度会在短暂 idle 后按需重试。自动接管只针对明确的 Emacs 初始占位
;; buffer；Magit、Help、Agenda 等 `special-mode' 工作 buffer 不是空白页，
;; 不能被 dashboard 覆盖。server-edit / with-editor 编辑请求同样跳过。
;;
;; 依赖（同仓库、同 load-path，直接 require，见 ADR-0002）：
;; - `literal-bootstrap'：路径常量（literal:org-directory / literal:org-inbox-file）
;; - `literal-frame'：frame 生命周期（literal/add-frame-hook）
;; - `literal-org-knowledge'：知识库卡片数据收集 / 文件打开
;; - `literal-help'：快捷键卡片数据提取
;; - `literal-color-scheme'：主题切换 buffer 刷新注册
;; 这些模块在 dashboard 加载前（init.el 的加载序列）均已就绪。

;;; Code:

(require 'cl-lib)
(require 'calendar)
(require 'literal-bootstrap)
(require 'literal-frame)
(require 'literal-org-knowledge)
(require 'literal-help)
(require 'literal-color-scheme)

;; ═════════════════════════════════════════════════════════════════════════════
;; 路径与跨模块回调（原 defvar 注入点，改为直接 require 后调用对应模块函数）
;; ═════════════════════════════════════════════════════════════════════════════

(defface dashboard-card
  '((((background light)) :background "#f0f0f0")
    (((background dark))  :background "#1e2030"))
  "Dashboard 卡片背景。默认使用 light/dark 双套回退颜色，
主题加载后由 `literal/color-scheme-apply-custom-face-colors' 覆盖为 `bg-alt'。")

(defface dashboard-card-title
  '((t :inherit font-lock-keyword-face :weight bold))
  "Dashboard 卡片标题的 face。从 `font-lock-keyword-face' 继承强调色。")

(defface dashboard-todo-title
  '((t :inherit default))
  "Dashboard TODO 标题的 face。背景色由卡片行添加。")

(defconst literal:dashboard-card-inner-padding 2
  "Dashboard 卡片内容区左右统一保留的内边距列数。")

(defconst literal:dashboard-shortcuts-column-gap 4
  "Dashboard 快捷键双列之间的固定间隔列数。")

(defconst literal:dashboard-dual-gap 3
  "双列布局左右卡片之间的间隔列数。")

(defvar-local literal/dashboard--rendered-width nil
  "当前 dashboard buffer 最近一次渲染所使用的窗口宽度。")

(defvar literal/dashboard--refresh-in-progress nil
  "非 nil 表示当前正在刷新 dashboard，避免重复重入。")

(defvar literal/dashboard--cached-recentf-list nil
  "dashboard 渲染前保存的 recentf-list 快照，绕过渲染期间的临时清空。")

(defconst literal:dashboard-cache-ttl 60
  "Dashboard 数据源缓存的有效期（秒）。
超过此时间则视为过期，下次取用时重新计算。")

(defvar literal/dashboard--todo-cache nil
  "TODO 项缓存，结构为 (KEY TIME . DATA)，KEY 为 MAX-ITEMS。")

(defvar literal/dashboard--knowledge-cache nil
  "知识库条目缓存，结构为 (KEY TIME . DATA)，KEY 为 MAX-ITEMS。")

(defvar literal/dashboard--projects-cache nil
  "项目列表缓存，结构为 (KEY TIME . DATA)，KEY 恒为 nil（无查询参数）。")

(defun literal/dashboard--cache-valid-p (cache key)
  "判断 CACHE (KEY TIME . DATA) 是否对 KEY 在 TTL 内有效。"
  (and (consp cache)
       (eq (car cache) key)
       (let ((time (cadr cache)))
         (and time
              (<= (float-time (time-since time))
                  literal:dashboard-cache-ttl)))))

(defun literal/dashboard--cached (cache-var key compute-fn)
  "返回 CACHE-VAR 中 KEY 对应的缓存数据；失效则调用 COMPUTE-FN 重算并缓存。
CACHE-VAR 是缓存变量符号，缓存结构统一为 (KEY TIME . DATA)。
COMPUTE-FN 为无参函数或函数符号，返回要缓存的数据。"
  (let ((cache (symbol-value cache-var)))
    (if (literal/dashboard--cache-valid-p cache key)
        (cddr cache)
      (let ((data (funcall compute-fn)))
        (set cache-var (cons key (cons (current-time) data)))
        data))))

(defun literal/dashboard-invalidate-cache ()
  "清除 dashboard 所有数据源缓存。可在 Org 保存、Magit 操作等
改变底层数据后调用，确保下次刷新读取最新结果。"
  (setq literal/dashboard--todo-cache nil
        literal/dashboard--knowledge-cache nil
        literal/dashboard--projects-cache nil))

(defun literal/dashboard--snapshot-recentf (&rest _)
  "在 dashboard 刷新前保存 recentf-list 快照。"
  (when (and (boundp 'recentf-list) recentf-list)
    (setq literal/dashboard--cached-recentf-list recentf-list)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 卡片工具函数
;; ═════════════════════════════════════════════════════════════════════════════

(defvar literal/dashboard--forced-width nil
  "非 nil 时强制覆盖 card-width 计算，用于双列布局。")

(defun literal/dashboard--card-width (margin)
  "返回当前窗口下卡片的可用内容宽度。
如果 `literal/dashboard--forced-width' 非 nil，直接返回该值。"
  (or literal/dashboard--forced-width
      (max 1 (- (window-body-width) (* 2 margin)))))

(defun literal/dashboard--apply-fixed-pitch ()
  "强制 dashboard buffer 使用固定宽度的默认 face。"
  (setq-local face-remapping-alist
              (cons '(default fixed-pitch)
                    (assq-delete-all 'default face-remapping-alist)))
  (setq-local truncate-lines t))

(defun literal/dashboard--valid-color (val)
  "返回可用的颜色值 VAL；过滤 `face-foreground'/`face-background' 在 TTY
frame 下属性未指定时返回的 `unspecified-fg'/`unspecified-bg' 符号。
这些符号直接传给 `add-face-text-property' 的 :foreground/:background
会触发 \"Unable to load color\" 报错。"
  (and val
       (let ((s (if (symbolp val) (symbol-name val) val)))
         (and (not (string-prefix-p "unspecified" s))
              val))))

(defun literal/dashboard--card-row (content width margin &optional face)
  "插入 CONTENT 填充至 WIDTH 宽度的卡片行，背景使用 FACE。
MARGIN 两侧的空额无背景色。
CONTENT 可以是字符串或需要拼接的属性字符串/按钮列表。
超出 WIDTH 的内容用省略号截断。
当 FACE 不是 `dashboard-card' 时，同时将前景色应用到内容。"
  (let* ((parts (if (listp content) content (list content)))
         (content-str (apply #'concat parts))
         (content-width (string-width content-str))
         (face (or face 'dashboard-card))
         (bg (or (literal/dashboard--valid-color (face-background face)) 'unspecified))
         (fg (and (not (eq face 'dashboard-card))
                  (literal/dashboard--valid-color (face-foreground face nil t))))
         (margin-str (make-string margin ?\s)))
    ;; 超出宽度时截断并加 "..."，末尾精确保留 2 列呼吸空间
    (when (> content-width width)
      (setq content-str (truncate-string-to-width content-str (- width 2) 0 nil "...")
            content-width (string-width content-str)))
    (let ((pad-len (max 0 (- width content-width))))
      ;; 给内容补背景色；非默认 face 时同时叠加前景色
      (add-face-text-property
       0 (length content-str)
       (if fg
           (list :background bg :foreground fg)
         (list :background bg))
       t content-str)
      (insert margin-str
              content-str
              (propertize (make-string pad-len ?\s) 'face face)
              margin-str
              "\n"))))

(defun literal/dashboard--make-title-face ()
  "返回卡片标题的 face 符号。
动态设置 `dashboard-card-title' 背景以匹配 `dashboard-card'，
前景色继承 `font-lock-keyword-face' 以实现可靠的主题化。
`face-background' 在未设置时返回 nil，需要回退为 `unspecified'。"
  (let ((bg (or (literal/dashboard--valid-color (face-background 'dashboard-card)) 'unspecified)))
    (face-spec-set 'dashboard-card-title
                   `((t :inherit font-lock-keyword-face
                        :background ,bg
                        :weight bold))))
  'dashboard-card-title)

(defun literal/dashboard--compose-aligned-row (left right width)
  "Compose a WIDTH-wide card row with LEFT and RIGHT content.
Both sides keep `literal:dashboard-card-inner-padding' columns of inner padding."
  (let* ((left (or left ""))
         (right (or right ""))
         (inner-padding (make-string literal:dashboard-card-inner-padding ?\s))
         (gap-len (max 0 (- width
                            (* 2 literal:dashboard-card-inner-padding)
                            (string-width left)
                            (string-width right)))))
    (concat inner-padding left (make-string gap-len ?\s) right inner-padding)))

(defun literal/dashboard--format-shortcut-column (binding width)
  "Format a dashboard shortcut BINDING to fit within WIDTH columns."
  (if (not binding)
      (make-string width ?\s)
    (let* ((key (car binding))
           (desc (cdr binding))
           (key-gap "  ")
           (desc-width (max 0 (- width
                                 (string-width key)
                                 (string-width key-gap))))
           (display-desc (truncate-string-to-width desc desc-width 0 nil "..."))
           (pad-len (max 0 (- width
                              (string-width key)
                              (string-width key-gap)
                              (string-width display-desc)))))
      (concat (propertize key 'face 'font-lock-keyword-face)
              key-gap
              display-desc
              (make-string pad-len ?\s)))))

(defvar literal/dashboard--override-margin nil
  "非 nil 时强制覆盖 card-section 中的 margin 参数，用于双列等特殊布局。")

(defun literal/dashboard--card-section (title icon-key rows margin)
  "Insert a card section with TITLE line and ROWS.
TITLE is the section title string.
ICON-KEY is a cons (icon . key) where icon is a string and key is the shortcut hint.
ROWS is a list; each element is either a string or a list of string parts to concat.
MARGIN is the number of space columns on each side."
  (let* ((margin (or literal/dashboard--override-margin margin))
         (card-width (literal/dashboard--card-width margin))
         (icon (car icon-key))
         (key (cdr icon-key))
         (title-line (concat icon " " title))
         (title-content (literal/dashboard--compose-aligned-row
                         title-line key card-width)))
    ;; 顶部内边距
    (literal/dashboard--card-row "" card-width margin)
    ;; 标题行
    (literal/dashboard--card-row title-content card-width margin
                                (literal/dashboard--make-title-face))
    ;; 标题与内容的分隔行
    (literal/dashboard--card-row "" card-width margin)
    ;; 数据行
    (dolist (row rows)
      (if (listp row)
          (literal/dashboard--card-row (cons "  " row) card-width margin)
        (literal/dashboard--card-row (concat "  " row) card-width margin)))
    ;; 底部内边距
    (literal/dashboard--card-row "" card-width margin)
    (insert "\n")))

(defun literal/dashboard--open-path (path &optional opener)
  "打开 PATH。OPENER 非 nil 时优先调用 OPENER。"
  (if opener
      (funcall opener path)
    (find-file path)))

(defun literal/dashboard--make-item-button (display path &optional opener)
  "返回一个带局部 keymap 的字符串，RET/mouse-1 时打开 PATH。
OPENER 非 nil 时作为打开函数，接收 PATH 一个参数。"
  (let ((button-str (copy-sequence display))
        (keymap (make-sparse-keymap)))
    (set-text-properties 0 (length button-str) nil button-str)
    (define-key keymap (kbd "RET")
                (lambda () (interactive)
                  (literal/dashboard--open-path path opener)))
    (define-key keymap [mouse-1]
                (lambda () (interactive)
                  (literal/dashboard--open-path path opener)))
    (add-text-properties
     0 (length button-str)
     (list 'keymap keymap
           'face 'dashboard-items-face
           'mouse-face 'highlight
           'help-echo (format "打开 %s" path))
     button-str)
    button-str))

(defun literal/dashboard--compact-path (path)
  "将 PATH 中间目录压缩为首字母，首尾保留完整。
隐藏目录（以 . 开头）取其第二个字符，避免 ~/./e 这种怪异的路径。"
  (let* ((parts (split-string path "/" t))
         (len (length parts)))
    (if (<= len 3)
        path
      (let* ((head (car parts))
             (file (car (last parts)))
             (middle (cl-subseq parts 1 (1- len)))
             (compressed (mapcar (lambda (d)
                                   (cond ((string-empty-p d) d)
                                         ((string-prefix-p "." d)
                                          (if (> (length d) 1)
                                              (concat "." (substring d 1 2))
                                            d))
                                         (t (substring d 0 1))))
                                 middle)))
        (concat head "/"
                (mapconcat #'identity compressed "/")
                "/" file)))))

(defun literal/dashboard--abbreviate-path (path max-width)
  "将 PATH 缩写以适应 MAX-WIDTH 列宽。
先压缩中间目录为首字母，仍超宽则从右侧截断并加 \"…\"。"
  (let* ((compact (literal/dashboard--compact-path path))
         (cw (string-width compact)))
    (if (<= cw max-width)
        compact
      (truncate-string-to-width compact max-width 0 nil "..."))))

(defun literal/dashboard--todo-state-face (todo-state)
  "返回 TODO-STATE 在 dashboard 待办卡片中使用的标签 face。"
  (pcase todo-state
    ("TODO" 'font-lock-warning-face)
    ("NEXT" 'font-lock-type-face)
    ("INPROGRESS" 'font-lock-constant-face)
    ("WAITING" 'font-lock-comment-face)
    ("DONE" 'success)
    ("CANCELLED" 'shadow)
    (_ 'font-lock-variable-name-face)))

(defun literal/dashboard--todo-title (title)
  "返回 dashboard 待办标题 TITLE。
标题显式使用普通前景色，只继承卡片背景；状态和日期各自独立上色。"
  (let ((fg (literal/dashboard--valid-color (face-foreground 'default nil t))))
    (face-spec-set 'dashboard-todo-title
                   `((t ,@(when fg (list :foreground fg))))))
  (propertize (or title "") 'face 'dashboard-todo-title))

(defun literal/dashboard--todo-date-info (today-abs deadline-str scheduled-str
                                         deadline-abs scheduled-abs)
  "返回 TODO 项的日期信息字符串，用于 dashboard 待办卡片。"
  (cond
   ((and deadline-abs (< deadline-abs today-abs))
    (propertize (format "  󰥕 过期%d天" (- today-abs deadline-abs))
                'face 'error))
   ((and deadline-abs (= deadline-abs today-abs))
    (propertize "  󰥕 今天截止" 'face 'error))
   (deadline-str
    (let ((diff (- deadline-abs today-abs)))
      (propertize
       (cond ((= diff 1) "  󰥕 明天截止")
             ((<= diff 3) (format "  󰥕 %d天后截止" diff))
             ((<= diff 7) (format "  󰥕 %d天后截止" diff))
             (t (format "  󰥕 %s"
                        (substring deadline-str 1 11))))
       'face (cond ((<= diff 1) 'error)
                   ((<= diff 3) 'warning)
                   ((<= diff 7) 'font-lock-variable-name-face)
                   (t 'font-lock-keyword-face)))))
   ((and scheduled-abs (< scheduled-abs today-abs))
    (propertize (format "  󰔠 过期%d天" (- today-abs scheduled-abs))
                'face 'error))
   ((and scheduled-abs (= scheduled-abs today-abs))
    (propertize (format "  󰔠 %s" (substring scheduled-str 1 11))
                'face 'error))
   (scheduled-str
    (propertize (format "  󰔠 %s" (substring scheduled-str 1 11))
                'face 'font-lock-keyword-face))
   (t "")))

;; ═════════════════════════════════════════════════════════════════════════════
;; 双列布局工具函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/dashboard--call-with-card-width (card-width thunk)
  "以 CARD-WIDTH 覆盖卡片宽度后调用 THUNK，执行完恢复原值。"
  (let ((saved-width literal/dashboard--forced-width))
    (setq literal/dashboard--forced-width card-width)
    (unwind-protect (funcall thunk)
      (setq literal/dashboard--forced-width saved-width))))

(defun literal/dashboard--render-one-card (thunk card-width)
  "在临时 buffer 中以 CARD-WIDTH 渲染单个卡片，返回行列表。"
  (let ((it-lines nil)
        (it-buf (generate-new-buffer " *dual-card*")))
    (unwind-protect
        (progn
          (with-current-buffer it-buf
            (let ((literal/dashboard--forced-width card-width)
                  (literal/dashboard--override-margin 0))
              (funcall thunk))
            (goto-char (point-min))
            (while (not (eobp))
              (push (buffer-substring (line-beginning-position) (line-end-position))
                    it-lines)
              (forward-line 1))))
      (kill-buffer it-buf))
    (nreverse it-lines)))

(defun literal/dashboard--pad-to-width (str width face)
  "将 STR 填充至恰好 WIDTH 列，仅对填充部分应用 FACE。"
  (let* ((pad-len (max 0 (- width (string-width str)))))
    (if (> pad-len 0)
        (concat str (propertize (make-string pad-len ?\s) 'face face))
      str)))

(defun literal/dashboard--insert-card-pair (left-thunk right-thunk
                                           left-width right-width
                                           margin gap)
  "并排插入左右两张卡片。
每张卡片以零内边距渲染到临时 buffer，再按行交错拼接。
MARGIN 为页面左右外边距，GAP 为两卡片间距。"
  (let* ((literal/dashboard--override-margin 0)
         (left-lines (literal/dashboard--render-one-card left-thunk left-width))
         (right-lines (literal/dashboard--render-one-card right-thunk right-width))
         (max-lines (max (length left-lines) (length right-lines)))
         (margin-str (make-string margin ?\s))
         (gap-str (make-string gap ?\s)))
    (dotimes (i max-lines)
      (let ((left (if (< i (length left-lines)) (nth i left-lines) ""))
            (right (if (< i (length right-lines)) (nth i right-lines) "")))
        (insert margin-str
                (literal/dashboard--pad-to-width left left-width 'dashboard-card)
                gap-str
                (literal/dashboard--pad-to-width right right-width 'dashboard-card)
                margin-str
                "\n"))))
  (insert "\n"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 自定义 ASCII Banner（Doom 风格）
;; ═════════════════════════════════════════════════════════════════════════════

(defvar literal/dashboard-ascii-banner
  '(
    ""
    "███████╗ ██╗   ██╗ ███████╗ ██╗  ██████╗  ███╗   ██╗      ███████╗ ███╗   ███╗  █████╗   ██████╗ ███████╗"
    "██╔════╝ ██║   ██║ ██╔════╝ ██║ ██╔═══██╗ ████╗  ██║      ██╔════╝ ████╗ ████║ ██╔══██╗ ██╔════╝ ██╔════╝"
    "█████╗   ██║   ██║ ███████╗ ██║ ██║   ██║ ██╔██╗ ██║      █████╗   ██╔████╔██║ ███████║ ██║      ███████╗"
    "██╔══╝   ██║   ██║ ╚════██║ ██║ ██║   ██║ ██║╚██╗██║      ██╔══╝   ██║╚██╔╝██║ ██╔══██║ ██║      ╚════██║"
    "██║      ╚██████╔╝ ███████║ ██║ ╚██████╔╝ ██║ ╚████║      ███████╗ ██║ ╚═╝ ██║ ██║  ██║ ╚██████╗ ███████║"
    "╚═╝       ╚═════╝  ╚══════╝ ╚═╝  ╚═════╝  ╚═╝  ╚═══╝      ╚══════╝ ╚═╝     ╚═╝ ╚═╝  ╚═╝  ╚═════╝ ╚══════╝"
    ""
    "")
  "Doom 风格 ASCII art banner。")

(defun literal/dashboard-insert-ascii-banner ()
  "插入居中的自定义 ASCII banner，并在 banner 后插入 footer 引言。"
  (let* ((max-len (apply #'max (mapcar #'length literal/dashboard-ascii-banner)))
         (padding (max 0 (/ (- (window-width) max-len) 2)))
         (pad-str (make-string padding ?\s))
         (banner-face (if (facep 'dashboard-banner) 'dashboard-banner 'font-lock-keyword-face)))
    (insert "\n")
    (dolist (line literal/dashboard-ascii-banner)
      (insert pad-str (propertize line 'face banner-face) "\n"))
    ;; 在 banner 后立即插入 footer 引言
    (when (and (boundp 'dashboard-set-footer) dashboard-set-footer
               (boundp 'dashboard-footer) (stringp dashboard-footer))
      (let* ((footer-text dashboard-footer)
             (footer-pad (max 0 (/ (- (window-width) (string-width footer-text)) 2))))
        (insert "\n")
        (insert (make-string footer-pad ?\s)
                (propertize footer-text 'face 'dashboard-footer)
                "\n")))
    (insert "\n")))

;; ═════════════════════════════════════════════════════════════════════════════
;; 卡片风格列表显示
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/dashboard-insert-centered-list (title list list-size &optional icon key)
  "插入一个卡片区块，包含 TITLE，显示 LIST 中的条目。
LIST 中的每个元素是一个 (path . display-string) 构造。
ICON 是 Nerd Font 图标字符串。KEY 是快捷键提示字符串。"
  (when (car list)
    (let* ((card-available (- (literal/dashboard--card-width 4)
                              (* 2 literal:dashboard-card-inner-padding)))
           (items (seq-take list list-size))
           (rows (mapcar (lambda (el)
                           (let ((abbreviated
                                  (literal/dashboard--abbreviate-path
                                   (cdr el) card-available)))
                             (list (literal/dashboard--make-item-button
                                    abbreviated (car el)))))
                         items))
           (margin 4))
      (literal/dashboard--card-section title (cons (or icon "") key) rows margin))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 自定义项目生成器
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/dashboard-insert-recents (list-size)
  "居中插入最近文件列表，无数据时显示 fallback 卡片。"
  (if (bound-and-true-p recentf-mode)
      (let ((items (or literal/dashboard--cached-recentf-list
                       (and (boundp 'recentf-list) recentf-list)
                       (default-value 'recentf-list))))
        (if items
            (literal/dashboard-insert-centered-list
             "最近文件"
             (mapcar (lambda (f) (cons f f))
                     items)
             list-size
             "󰋚" "C-x C-r")
          (literal/dashboard--card-section
           "最近文件" '("󰋚" . "C-x C-r") '(("暂无最近文件")) 4)))
    (literal/dashboard--card-section
     "最近文件" '("󰋚" . "C-x C-r") '(("recentf 未启用")) 4)))

(defun literal/dashboard--compute-known-projects ()
  "实际计算 dashboard 可展示的项目列表（无缓存）。

优先读取 Projectile 的已知项目缓存（仅当 Projectile 已加载），
回落到 `project.el'。"
  (let ((projects nil))
    (when (featurep 'projectile)
      (when (fboundp 'projectile-load-known-projects)
        (projectile-load-known-projects))
      (setq projects
            (and (boundp 'projectile-known-projects)
                 projectile-known-projects)))
    (unless projects
      (setq projects
            (and (fboundp 'project-known-project-roots)
                 (project-known-project-roots))))
    (delete-dups
     (seq-filter #'file-directory-p
                 (mapcar #'file-name-as-directory projects)))))

(defun literal/dashboard--known-projects ()
  "返回 dashboard 可展示的项目列表。

优先读取 Projectile 的已知项目缓存（仅当 Projectile 已加载），
回落到 `project.el'。结果带 TTL 缓存（见 `literal:dashboard-cache-ttl'），
可通过 `literal/dashboard-invalidate-cache' 失效。"
  (literal/dashboard--cached
   'literal/dashboard--projects-cache
   nil
   #'literal/dashboard--compute-known-projects))

(defun literal/dashboard-insert-projects (list-size)
  "居中插入项目列表，无数据时显示 fallback 占位卡片。"
  (let ((projects (literal/dashboard--known-projects)))
    (if projects
        (literal/dashboard-insert-centered-list
         "项目"
         (mapcar (lambda (p) (cons p p))
                 projects)
         list-size
         "󰝰" "C-x p p")
      (literal/dashboard--card-section
       "项目" '("󰝰" . "C-x p p") '(("暂无已知项目（C-x p o 添加）")) 4))))

(defun literal/dashboard-insert-bookmarks (list-size)
  "居中插入书签列表，无数据时显示 fallback 占位卡片。"
  (require 'bookmark)
  (let ((bookmarks (bookmark-all-names)))
    (if bookmarks
        (literal/dashboard-insert-centered-list
         "书签"
         (mapcar (lambda (b)
                   (cons (bookmark-get-filename b) b))
                 bookmarks)
         list-size
         "󰉋" "C-c e b l")
      (literal/dashboard--card-section
       "书签" '("󰉋" . "C-c e b l") '(("暂无书签")) 4))))

(defun literal/dashboard--compute-todo-items (max-items)
  "实际扫描 `org-agenda-files' 计算未完成 TODO 项（无缓存）。"
  (let ((today-abs (calendar-absolute-from-gregorian (calendar-current-date)))
        (count 0)
        raw-items)
    ;; org 已 :defer t:org-agenda-files 虽 autoload,但调用会触发 org 加载。
    ;; org 未加载时返回 nil(agenda 卡片显示"暂无待办事项")。
    (when (and (featurep 'org)
               (fboundp 'org-agenda-files)
               (ignore-errors (org-agenda-files)))
      (dolist (file (org-agenda-files))
        (when (and (< count (* max-items 2)) (file-exists-p file))
          (with-current-buffer (let ((ask-user-about-supersession-threat
                                      (lambda (&rest _) nil)))
                                 (find-file-noselect file))
            (org-with-wide-buffer
             (goto-char (point-min))
             (while (and (< count (* max-items 2))
                         (re-search-forward org-heading-regexp nil t))
               (let* ((components (org-heading-components))
                      (todo-state (nth 2 components))
                      (title (nth 4 components))
                      (scheduled (org-entry-get (point) "SCHEDULED"))
                      (deadline (org-entry-get (point) "DEADLINE")))
                 (when (and todo-state
                            (not (member todo-state '("DONE" "CANCELLED"))))
                   (let* ((deadline-abs (and deadline
                                              (org-time-string-to-absolute deadline)))
                          (scheduled-abs (and scheduled
                                               (org-time-string-to-absolute scheduled)))
                          (urgency
                           (cond
                            ((and deadline-abs (< deadline-abs today-abs)) 0)
                            ((and deadline-abs (= deadline-abs today-abs)) 1)
                            ((and scheduled-abs (< scheduled-abs today-abs)) 2)
                            (deadline-abs 3)
                            (scheduled-abs 4)
                            (t 5))))
                     (push (list urgency todo-state title deadline
                                 scheduled deadline-abs scheduled-abs)
                           raw-items)
                     (setq count (1+ count)))))))))))
    (setq raw-items
          (sort raw-items
                (lambda (a b)
                  (or (< (car a) (car b))
                      (and (= (car a) (car b))
                           (and (nth 5 a) (nth 5 b)
                                (< (nth 5 a) (nth 5 b))))))))
    (let ((result nil)
          (count 0))
      (dolist (item raw-items)
        (when (< count max-items)
          (let* ((todo-state (nth 1 item))
                 (title (nth 2 item))
                 (deadline-str (nth 3 item))
                 (scheduled-str (nth 4 item))
                 (deadline-abs (nth 5 item))
                 (scheduled-abs (nth 6 item))
                 (state-face (literal/dashboard--todo-state-face todo-state))
                 (date-info (literal/dashboard--todo-date-info
                             today-abs deadline-str scheduled-str
                             deadline-abs scheduled-abs)))
            (push (list (propertize (concat todo-state "  ") 'face state-face)
                        (literal/dashboard--todo-title title)
                        date-info)
                  result)
            (setq count (1+ count)))))
      (nreverse result))))

(defun literal/dashboard--todo-items (max-items)
  "返回所有未完成的 Org TODO 项作为带属性的字符串。
扫描 `org-agenda-files' 中状态为 TODO 的条目（TODO, NEXT, INPROGRESS, WAITING）。
按紧急度排序：过期 DEADLINE → 今日 DEADLINE → 未来 DEADLINE → SCHEDULED → 无日期。
MAX-ITEMS 限制返回的条目数量。
结果按 MAX-ITEMS 带 TTL 缓存（见 `literal:dashboard-cache-ttl'），
可通过 `literal/dashboard-invalidate-cache' 失效。"
  (literal/dashboard--cached
   'literal/dashboard--todo-cache
   max-items
   (lambda () (literal/dashboard--compute-todo-items max-items))))

(defun literal/dashboard-insert-agenda (list-size)
  "将所有未完成的 TODO 项作为 dashboard 卡片插入。"
  (let ((items (literal/dashboard--todo-items list-size)))
    (if items
        (literal/dashboard--card-section
         "待办" '("󰃭" . "C-c o f") items 4)
      (literal/dashboard--card-section
       "待办" '("󰃭" . "C-c o f")
       '(("暂无待办事项")) 4))))

(defun literal/dashboard-insert-clock (_list-size)
  "将 Org 计时状态作为 dashboard 卡片插入。"
  ;; org 已 :defer t:org-clocking-p / org-clock-sum-today 虽 autoload,
  ;; 但调用会触发 org-clock 加载,抵消 defer。org 未加载时显示静态卡片。
  (if (not (featurep 'org))
      (literal/dashboard--card-section
       "计时" '("󱎫" . "C-c c i / o")
       '(("打开 org 文件后显示计时")) 4)
    (let* ((clocking-p (and (fboundp 'org-clocking-p) (org-clocking-p)))
           (today-min (if (fboundp 'org-clock-sum-today) (org-clock-sum-today) 0))
           (today-str (format "%dh %dm" (/ today-min 60) (% today-min 60)))
           (rows
            (if clocking-p
                (let* ((clock-string (substring-no-properties (org-clock-get-clock-string)))
                       (task-name (if (string-match org-ts-regexp-both clock-string)
                                      (string-trim (substring clock-string (match-end 0)))
                                    clock-string)))
                  (list (list (propertize "▶ 计时中: " 'face 'success)
                              task-name
                              "  " (propertize today-str 'face 'font-lock-type-face))
                        (list "今日累计: "
                              (propertize today-str 'face 'font-lock-keyword-face))))
              (list "当前没有计时的任务"
                    (list "今日累计: "
                          (propertize today-str 'face 'font-lock-comment-face))))))
      (literal/dashboard--card-section
       "计时" '("󱎫" . "C-c c i / o") rows 4))))

(defun literal/dashboard--compute-recent-knowledge-entries (max-items)
  "实际递归扫描 experiences/ 计算最近知识库条目（无缓存）。"
  (let ((exp-dir (expand-file-name "experiences" literal:org-directory))
        (candidates nil))
    (when (file-directory-p exp-dir)
      (dolist (f (funcall (or (when (fboundp 'literal/knowledge-collect-org-files)
                                #'literal/knowledge-collect-org-files)
                              (lambda (d)
                                (directory-files-recursively d "\\.org\\'")))
                          exp-dir))
        (push (cons f (file-attribute-modification-time (file-attributes f)))
              candidates)))
    (dolist (f (list literal:org-inbox-file))
      (when (file-exists-p f)
        (push (cons f (file-attribute-modification-time (file-attributes f)))
              candidates)))
    (setq candidates (cl-sort candidates (lambda (a b) (time-less-p (cdr b) (cdr a)))))
    (cl-loop for (file . _) in candidates
             for i below max-items
             for title = (literal/dashboard--org-file-title file)
             collect (cons file (or title (file-name-base file))))))

(defun literal/dashboard--recent-knowledge-entries (max-items)
  "返回最近的知识库条目作为 (path . title) 对列表。
递归扫描 experiences/ 子目录。
结果按 MAX-ITEMS 带 TTL 缓存（见 `literal:dashboard-cache-ttl'），
可通过 `literal/dashboard-invalidate-cache' 失效。"
  (literal/dashboard--cached
   'literal/dashboard--knowledge-cache
   max-items
   (lambda () (literal/dashboard--compute-recent-knowledge-entries max-items))))

(defun literal/dashboard--org-file-title (file)
  "从 Org FILE 中提取 #+title。"
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file nil 0 2048)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+title:[ \t]+\\(.+\\)$" nil t)
        (string-trim (match-string 1))))))

(defun literal/dashboard-insert-knowledge (list-size)
  "将最近的知识库条目作为 dashboard 卡片插入。"
  (let* ((entries (literal/dashboard--recent-knowledge-entries list-size))
         (rows (if entries
                   (mapcar (lambda (e)
                             (let* ((path (car e))
                                    (base (cdr e))
                                    (dir (file-name-directory path))
                                    (prefix (concat (file-name-base
                                                     (directory-file-name dir)) "/"))
                                    (display (concat prefix base)))
                               (list (literal/dashboard--make-item-button
                                      display path
                                      (or (when (fboundp 'literal/knowledge-open-file)
                                            #'literal/knowledge-open-file)
                                          #'find-file)))))
                           entries)
                 '(("知识库暂无条目")))))
    (literal/dashboard--card-section
     "知识库" '("󰧑" . "C-c o k I") rows 4)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 快捷键帮助内容（动态提取）
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/dashboard--extract-top-level-bindings ()
  "提取 dashboard 需要展示的关键顶层快捷键。"
  (when (fboundp 'literal/help--extract-dashboard-bindings)
    (funcall #'literal/help--extract-dashboard-bindings)))

(defun literal/dashboard-insert-shortcuts (_list-size)
  "将键盘快捷键作为双列卡片插入。"
  (let* ((prefix-bindings (literal/dashboard--extract-top-level-bindings))
         (col-count 2)
         (margin 4)
         (card-width (literal/dashboard--card-width margin))
         ;; card-section 对字符串行追加 "  " 缩进，需预留 2 列
         (available-width (- card-width 2))
         (col-gap literal:dashboard-shortcuts-column-gap)
         (col-width (/ (max 1 (- available-width col-gap)) col-count))
         (total (length prefix-bindings))
         (rows-count (ceiling total (float col-count)))
         (row-lines nil))
    (dotimes (i rows-count)
      (let* ((left-idx i)
             (right-idx (+ i rows-count))
             (left (nth left-idx prefix-bindings))
             (right (when (< right-idx total) (nth right-idx prefix-bindings)))
             (left-col (literal/dashboard--format-shortcut-column left col-width))
             (right-col (literal/dashboard--format-shortcut-column right col-width)))
        (push (concat left-col
                      (make-string col-gap ?\s)
                      right-col)
              row-lines)))
    (setq row-lines (nreverse row-lines))
    (literal/dashboard--card-section
     "快捷键" '("󰌌" . "F1 ?") row-lines 4)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 双列布局主生成器
;; ═════════════════════════════════════════════════════════════════════════════

(defconst literal:dashboard-dual-margin 4
  "双列布局左右页面边距列数。")

(defun literal/dashboard-insert-dual-layout (_list-size)
  "双列布局 dashboard 主生成器。
Banner 在上方全宽居中，中间卡片对并排，快捷键在下方全宽。"
  (let* ((total-width (window-body-width))
         (margin literal:dashboard-dual-margin)
         (gap literal:dashboard-dual-gap)
         (pair-available (- total-width (* 2 margin) gap))
         (left-card-width (/ pair-available 2))
         (right-card-width (- pair-available left-card-width))
         (full-card-width (- total-width (* 2 margin))))
    ;; Row 1: 待办 | 计时
    (literal/dashboard--insert-card-pair
     (lambda () (literal/dashboard-insert-agenda 5))
     (lambda () (literal/dashboard-insert-clock 1))
     left-card-width right-card-width margin gap)
    ;; Row 2: 最近文件 | 项目
    (literal/dashboard--insert-card-pair
     (lambda () (literal/dashboard-insert-recents 6))
     (lambda () (literal/dashboard-insert-projects 5))
     left-card-width right-card-width margin gap)
    ;; Row 3: 知识库 | 书签
    (literal/dashboard--insert-card-pair
     (lambda () (literal/dashboard-insert-knowledge 5))
     (lambda () (literal/dashboard-insert-bookmarks 4))
     left-card-width right-card-width margin gap)
    ;; Row 4: 快捷键（全宽单卡片）
    (literal/dashboard--call-with-card-width
     full-card-width
     (lambda () (literal/dashboard-insert-shortcuts 1)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Dashboard 配置
;; ═════════════════════════════════════════════════════════════════════════════

(use-package dashboard
  :demand t
  :custom
  (dashboard-startup-banner nil)
  (dashboard-set-navigator t)
  (dashboard-items '((dual . 1)))
  (dashboard-set-heading-icons nil)   ; 由 literal/apply-frame-appearance 按 display 类型覆盖
  (dashboard-set-file-icons nil)      ; 由 literal/apply-frame-appearance 按 display 类型覆盖
  :config
  ;; 抑制 dashboard 按钮点击后的 overlay 无效报错
  ;; 原因：按钮 action 中 find-file 切换了当前 buffer，
  ;; widget-button--check-and-call-button 返回时 overlay 已失效
  (define-advice widget-button--check-and-call-button (:around (fn &rest args) suppress-overlay-error)
    "抑制 overlay 相关的 wrong-type-argument 错误。"
    (condition-case err
        (apply fn args)
      (wrong-type-argument
       (unless (eq (cadr err) 'overlayp)
         (signal (car err) (cdr err))))))
  ;; 在刷新前保存 recentf-list 快照，绕过 dashboard-refresh-buffer 内部的清空
  (advice-add 'dashboard-refresh-buffer :before #'literal/dashboard--snapshot-recentf)
  ;; 插入自定义居中 ASCII banner（内含 footer 引言）
  (advice-add 'dashboard-insert-banner :override #'literal/dashboard-insert-ascii-banner)
  ;; 抑制包原生的 footer 插入（已移至 banner 内部）
  (advice-add 'dashboard-insert-footer :override #'ignore)
  ;; dashboard 使用等宽字，避免 variable-pitch 造成标题和快捷键错位
  (add-hook 'dashboard-mode-hook #'literal/dashboard--apply-fixed-pitch)
  ;; dashboard 在不同宽度的 frame/window 中显示时需要按当前窗口重新渲染
  (add-hook 'window-size-change-functions #'literal/dashboard--maybe-refresh-visible)
  ;; 注册双列布局主生成器（统一渲染所有板块）
  (add-to-list 'dashboard-item-generators '(dual . literal/dashboard-insert-dual-layout))
  ;; 注册到主题切换刷新链：dashboard-mode buffer 在主题切换时主动 re-render，
  ;; 读取新的 face 值烘焙到文本 `:background' 属性。
  (when (fboundp 'literal/register-buffer-refresh!)
    (literal/register-buffer-refresh!
     'dashboard-mode #'dashboard-refresh-buffer))
  (dashboard-setup-startup-hook))

(defconst literal:dashboard-placeholder-buffer-names
  '(" *server*" "*scratch*" "*Messages*")
  "允许 dashboard 自动接管的 Emacs 初始占位 buffer 名称。")

(defun literal/dashboard--placeholder-buffer-p (buffer)
  "判断 BUFFER 是否仍是 client frame 的占位缓冲区。"
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (and (not (minibufferp buffer))
           (not buffer-file-name)
           (or (member (buffer-name buffer)
                       literal:dashboard-placeholder-buffer-names)
               (and (eq major-mode 'fundamental-mode)
                    (string-prefix-p " " (buffer-name buffer))))))))

(defun literal/dashboard--server-edit-buffer-p (buffer)
  "判断 BUFFER 是否正在服务 emacsclient / with-editor 编辑请求。"
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (or (bound-and-true-p server-buffer-clients)
          (bound-and-true-p with-editor-mode)
          (derived-mode-p 'git-commit-mode)))))

(defun literal/dashboard--single-window-frame-p (frame)
  "判断 FRAME 是否仍只有一个普通窗口。
Dashboard 只接管这种新 client frame 的空白启动状态；若 Magit、提交编辑器
或其他命令已经分裂窗口，则保留现有窗口配置。"
  (and (frame-live-p frame)
       (= (length (window-list frame 'no-minibuf)) 1)))

(defun literal/dashboard--refresh-buffer-in-window (window)
  "在 WINDOW 中按当前宽度重新渲染 dashboard。"
  (when (and (window-live-p window)
             (not literal/dashboard--refresh-in-progress))
    (let ((buffer (window-buffer window)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when (derived-mode-p 'dashboard-mode)
            (let ((literal/dashboard--refresh-in-progress t))
              (with-selected-window window
                (dashboard-refresh-buffer)
                (setq-local literal/dashboard--rendered-width
                            (window-body-width window))))))))))

(defconst literal:dashboard-refresh-debounce 0.3
  "window-size-change 触发 dashboard 重新渲染的 idle 延迟（秒）。
连续窗口尺寸变化会被合并为一次刷新。")

(defvar literal/dashboard--refresh-timer nil
  "dashboard 可见性刷新的 pending idle timer。")

(defun literal/dashboard--refresh-visible-now ()
  "立即检查所有可见 dashboard 窗口，宽度变化者按当前窗口重新渲染。"
  (when (timerp literal/dashboard--refresh-timer)
    (cancel-timer literal/dashboard--refresh-timer))
  (setq literal/dashboard--refresh-timer nil)
  (dolist (window (window-list nil 'no-minibuf))
    (let ((buffer (window-buffer window)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when (and (derived-mode-p 'dashboard-mode)
                     (/= (window-body-width window)
                         (or literal/dashboard--rendered-width -1)))
            (literal/dashboard--refresh-buffer-in-window window)))))))

(defun literal/dashboard--maybe-refresh-visible (_frame)
  "若可见 dashboard 的窗口宽度已变化，则延迟重新渲染（合并连续变化）。"
  (when (timerp literal/dashboard--refresh-timer)
    (cancel-timer literal/dashboard--refresh-timer))
  (setq literal/dashboard--refresh-timer
        (run-with-idle-timer literal:dashboard-refresh-debounce
                             nil
                             #'literal/dashboard--refresh-visible-now)))

(defun literal/dashboard--display-in-frame (frame)
  "在 FRAME 中显示并按需刷新 dashboard。"
  (when (and (frame-live-p frame)
             (literal/dashboard--single-window-frame-p frame))
    (with-selected-frame frame
      (when (fboundp 'dashboard-open)
        (dashboard-open)
        (when-let* ((dashboard-buffer (get-buffer "*dashboard*")))
          (when-let* ((window (frame-selected-window frame)))
            (set-window-buffer window dashboard-buffer)
            (literal/dashboard--refresh-buffer-in-window window)))))))

(defconst literal:dashboard-open-idle-delay 0.05
  "新建 client frame 后等待 dashboard 判定的 idle 秒数。")

(defconst literal:dashboard-open-retries 2
  "若首次判定过早，dashboard 允许追加重试的次数。")

(defun literal/dashboard--frame-startup-state (frame)
  "返回 FRAME 当前的启动缓冲区状态。"
  (cond
   ((not (literal/dashboard--single-window-frame-p frame)) 'busy)
   (t
    (if-let* ((window (and (frame-live-p frame)
                           (frame-selected-window frame)))
              (buffer (window-buffer window)))
        (with-current-buffer buffer
          (cond
           ((derived-mode-p 'dashboard-mode) 'dashboard)
           ((literal/dashboard--server-edit-buffer-p buffer) 'server-edit)
           ((buffer-file-name) 'file)
           ((literal/dashboard--placeholder-buffer-p buffer) 'placeholder)
           (t 'busy)))
      'pending))))

(defun literal/dashboard--run-open-check (frame retries-left)
  "根据 FRAME 当前状态决定是否显示或重试 dashboard。"
  (when (frame-live-p frame)
    (set-frame-parameter frame 'literal-dashboard-open-scheduled nil)
    (pcase (literal/dashboard--frame-startup-state frame)
      ('placeholder
       (literal/dashboard--display-in-frame frame))
      ('dashboard
       (when-let* ((window (frame-selected-window frame)))
         (literal/dashboard--refresh-buffer-in-window window)))
      ('file
       nil)
      ('server-edit
       nil)
      ('busy
       nil)
      (_
       (when (> retries-left 0)
         (literal/dashboard--schedule-open-for-frame
          frame
          (1- retries-left)))))))

(defun literal/dashboard--schedule-open-for-frame (frame retries-left)
  "为 FRAME 安排一次 dashboard 打开检查。RETRIES-LEFT 为剩余重试次数。"
  (when (and (frame-live-p frame)
             (not (frame-parameter frame 'literal-dashboard-open-scheduled)))
    ;; daemon 场景下 after-make-frame 与 server-after-make-frame 可能对同一 frame 连续触发。
    ;; 用 frame 参数避免并发重复调度，但在每轮检查结束后允许重新调度。
    (set-frame-parameter frame 'literal-dashboard-open-scheduled t)
    (run-with-idle-timer
     literal:dashboard-open-idle-delay nil
     (lambda (idle-frame idle-retries-left)
       (when (frame-live-p idle-frame)
         (literal/dashboard--run-open-check idle-frame idle-retries-left)))
     frame retries-left)))

(defun literal/dashboard-open-for-client-frame (&optional frame)
  "在 daemon 创建的 client FRAME 中打开 dashboard。
仅当该 frame 仍停留在占位缓冲区时接管，避免覆盖 `emacsclient FILE`。"
  (literal/dashboard--schedule-open-for-frame
   (or frame (selected-frame))
   literal:dashboard-open-retries))

(literal/add-frame-hook #'literal/dashboard-open-for-client-frame)

(provide 'literal-dashboard)
;;; dashboard.el ends here
