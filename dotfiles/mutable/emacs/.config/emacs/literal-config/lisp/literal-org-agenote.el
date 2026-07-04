;;; org-agenote.el --- agenote 子域浏览（agent 写入的经验卡片） -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;;; Commentary:
;; agenote 子域浏览视图：在 Emacs 内呈现 `~/Documents/Org/agenote/` 下
;; 由 agent 写入的经验卡片（与人类域 experiences/ 平行）。
;;
;; 为什么不直接调 agenote CLI：agenote CLI 多数只读分析命令（health/gaps/
;; list/deduplicate/get/search）默认不跨域，只能看到人类域。agent 卡片的
;; 唯一可靠结构化数据源是 `agenote/index.json`，本模块直接解析它，绕开 CLI
;; 的跨域限制。
;;
;; 两个 Tab：
;; - Tab 1 按类别：按 category 分组列出所有卡片
;; - Tab 2 时间线：按 created 降序列出，标注陈旧度
;;
;; 渲染范式（对齐 org-knowledge-viz.el）：
;; - 自定义 `literal/agenote-mode'，派生 `special-mode'
;; - 纯 face 符号着色（`propertize ... 'face'），不烘焙背景色
;;   → 主题切换由 Emacs 自动重算，无需 `register-buffer-refresh!'
;; - mtime 缓存（按 index.json 修改时间决定是否重解析）
;;
;; 命名约定：literal/agenote--*（函数）、literal--agenote-*（私有变量）
;; 入口：`C-c o k O' → `literal/agenote-browse'
;;
;; 自包含设计：本模块不 require 任何 literal-* 模块。
;; 下方两个 defvar 由 init.el 在 require 本模块前注入真实值。

;;; Code:

(require 'cl-lib)

;; ═════════════════════════════════════════════════════════════════════════════
;; 注入点：路径与外部命令（由 init.el 注入）
;; ═════════════════════════════════════════════════════════════════════════════
(defvar literal:agenote-directory nil
  "agenote 子域目录路径（agent 写入的卡片 + index.json）。
由 init.el 注入；nil 时 index.json 路径回退到 nil。")
(defvar literal:executable-agenote nil
  "agenote CLI 可执行文件路径。nil 表示未注入（命令不可用）。")

(defun literal/agenote--call-process (command &rest args)
  "同步执行 COMMAND 与 ARGS，返回 (STATUS . OUTPUT)。
本模块私有拷贝，避免依赖 literal-bootstrap。
STATUS 为进程退出码（0 = 成功），OUTPUT 为 stdout 的 trimmed 字符串。"
  (with-temp-buffer
    (cons (or (apply #'call-process command nil t nil (remq nil args))
              -1)
          (string-trim (buffer-string)))))

;; =============================================================================
;; 常量
;; =============================================================================

(defconst literal:agenote-index-file
  (expand-file-name "index.json" literal:agenote-directory)
  "agenote 子域 index.json 路径。")

;; =============================================================================
;; 数据层（纯函数）
;; =============================================================================

(defun literal/agenote--load-index ()
  "读取 agenote/index.json，返回卡片 plist 列表。空或不可读返回 nil。"
  (when (file-readable-p literal:agenote-index-file)
    (let ((json-object-type 'plist)
          (json-array-type 'list)
          (json-key-type 'keyword))
      (with-temp-buffer
        (insert-file-contents literal:agenote-index-file)
        (goto-char (point-min))
        (condition-case nil
            (plist-get (json-read) :cards)
          (error nil))))))

(defun literal/agenote--group-by-category (cards)
  "按 category 分组 CARDS，返回 ((CATEGORY . CARDS-IN-CAT) ...) 列表。
类别按字典序，每组内卡片按 created 降序。"
  (let (groups)
    (dolist (card cards)
      (let ((cat (or (plist-get card :category) "unknown")))
        (if-let* ((pair (assoc cat groups)))
            (push card (cdr pair))
          (push (cons cat (list card)) groups))))
    ;; 每组内按 created 降序
    (dolist (group groups)
      (setcdr group (sort (cdr group)
                          (lambda (a b)
                            (string> (or (plist-get a :created) "")
                                     (or (plist-get b :created) ""))))))
    (sort groups (lambda (a b) (string< (car a) (car b))))))

(defun literal/agenote--sort-by-recency (cards)
  "按 created 降序排列 CARDS（最新在前）。"
  (sort cards
        (lambda (a b)
          (string> (or (plist-get a :created) "")
                   (or (plist-get b :created) "")))))

;; =============================================================================
;; 面板状态（buffer-local）
;; =============================================================================

(defvar-local literal--agenote-cards nil
  "当前 buffer 已加载的卡片 plist 列表。")
(defvar-local literal--agenote-index-mtime nil
  "当前 buffer 已加载 index.json 的修改时间，用于 mtime 缓存。")
(defvar-local literal--agenote-current-tab 1
  "当前激活的 tab：1=按类别，2=时间线。")

(defun literal/agenote--refresh ()
  "按 mtime 缓存策略刷新 `literal--agenote-cards'。
index.json 修改时间变化才重解析，否则保留缓存。"
  (let ((mt (nth 5 (file-attributes literal:agenote-index-file))))
    (unless (and literal--agenote-cards literal--agenote-index-mtime
                 (time-equal-p mt literal--agenote-index-mtime))
      (setq literal--agenote-cards (literal/agenote--load-index))
      (setq literal--agenote-index-mtime mt))))

(defun literal/agenote--force-refresh (&rest _)
  "强制重读 index.json（置空 mtime 缓存）后刷新渲染。"
  (interactive)
  (setq literal--agenote-index-mtime nil)
  (literal/agenote--refresh)
  (literal/agenote--render-current-tab))

;; =============================================================================
;; Face（纯符号，随主题自动更新）
;; =============================================================================

(defface literal/agenote-category-header
  '((t :inherit font-lock-function-name-face :weight bold))
  "类别分组标题。")
(defface literal/agenote-entry-type
  '((t :inherit font-lock-type-face))
  "ENTRY_TYPE 标注（note/mistake/ascended）。")
(defface literal/agenote-source-agent
  '((t :inherit font-lock-builtin-face))
  "SOURCE_AGENT 来源标注。")
(defface literal/agenote-status
  '((t :inherit success))
  "STATUS 标注。")
(defface literal/agenote-title
  '((t :inherit link))
  "卡片标题（可点击）。")
(defface literal/agenote-meta
  '((t :inherit shadow))
  "次要元信息（id/日期等）。")

;; =============================================================================
;; 渲染
;; =============================================================================

(defun literal/agenote--format-card-line (card)
  "渲染单张 CARD 为一行带 text properties 的字符串。
点击标题打开卡片文件；显示 ENTRY_TYPE / SOURCE_AGENT / STATUS 标注。"
  (let* ((title (or (plist-get card :title) "(无标题)"))
         (id (or (plist-get card :id) ""))
         (cat (or (plist-get card :category) "?"))
         (etype (or (plist-get card :entry_type) ""))
         (agent (or (plist-get card :source_agent) ""))
         (status (or (plist-get card :status) ""))
         (created (or (plist-get card :created) ""))
         (file (expand-file-name (or (plist-get card :file) "")
                                 literal:agenote-directory)))
    (concat
     (propertize title 'face 'literal/agenote-title
                 'mouse-face 'highlight
                 'help-echo (format "点击打开: %s" file)
                 'keymap (let ((m (make-sparse-keymap)))
                           (define-key m [mouse-1]
                             (lambda () (interactive)
                               (when (file-exists-p file) (find-file file))))
                           (define-key m (kbd "RET")
                             (lambda () (interactive)
                               (when (file-exists-p file) (find-file file))))
                           m))
     "  "
     (propertize (format "[%s]" etype) 'face 'literal/agenote-entry-type)
     (if (string-empty-p agent) ""
       (concat " " (propertize (format "@%s" agent)
                               'face 'literal/agenote-source-agent)))
     " "
     (propertize status 'face 'literal/agenote-status)
     "  "
     (propertize (format "%s · %s · %s" cat created id)
                 'face 'literal/agenote-meta))))

(defun literal/agenote--render-tab-category (cards)
  "渲染 Tab 1：按类别分组的卡片列表。"
  (let ((groups (literal/agenote--group-by-category cards)))
    (dolist (group groups)
      (insert (propertize (format "╸ %s (%d)\n"
                                  (car group) (length (cdr group)))
                          'face 'literal/agenote-category-header))
      (dolist (card (cdr group))
        (insert "  " (literal/agenote--format-card-line card) "\n"))
      (insert "\n"))))

(defun literal/agenote--render-tab-timeline (cards)
  "渲染 Tab 2：按 created 降序的时间线。"
  (dolist (card (literal/agenote--sort-by-recency cards))
    (insert "  " (literal/agenote--format-card-line card) "\n")))

(defun literal/agenote--render-header-line ()
  "根据当前 tab 设置 `header-line-format'。"
  (setq header-line-format
        (format " agenote 子域 · %d 张卡片  [1]按类别 %s  [2]时间线 %s  (g 刷新, q 退出)"
                (length literal--agenote-cards)
                (if (= literal--agenote-current-tab 1) "●" "○")
                (if (= literal--agenote-current-tab 2) "●" "○"))))

(defun literal/agenote--render-current-tab ()
  "按 `literal--agenote-current-tab' 渲染当前 tab。"
  (let ((inhibit-read-only t))
    (erase-buffer)
    (cond
     ((null literal--agenote-cards)
      (insert (propertize "agenote 子域无卡片（index.json 为空或不可读）\n"
                          'face 'warning)))
     ((= literal--agenote-current-tab 1)
      (literal/agenote--render-tab-category literal--agenote-cards))
     ((= literal--agenote-current-tab 2)
      (literal/agenote--render-tab-timeline literal--agenote-cards)))
    (goto-char (point-min))
    (literal/agenote--render-header-line)))

;; =============================================================================
;; Tab 切换
;; =============================================================================

(defmacro literal/agenote--defswitch (tab-num)
  "生成切到 TAB-NUM 的命令。"
  `(defun ,(intern (format "literal/agenote--switch-tab-%d" tab-num)) ()
     ,(format "切到 Tab %d。" tab-num)
     (interactive)
     (setq literal--agenote-current-tab ,tab-num)
     (literal/agenote--render-current-tab)))

(literal/agenote--defswitch 1)
(literal/agenote--defswitch 2)

;; =============================================================================
;; Mode 定义
;; =============================================================================

(defvar literal/agenote-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m "1" #'literal/agenote--switch-tab-1)
    (define-key m "2" #'literal/agenote--switch-tab-2)
    (define-key m "g" #'literal/agenote--force-refresh)
    m))

(define-derived-mode literal/agenote-mode special-mode "agenote"
  "浏览 agenote 子域经验卡片（agent 写入）。
数据源直接读 `agenote/index.json'（agenote CLI 不跨域）。

\\{literal/agenote-mode-map}"
  (setq buffer-read-only t)
  (setq-local revert-buffer-function #'literal/agenote--force-refresh))

;; =============================================================================
;; 交互入口
;; =============================================================================

;;;###autoload
(defun literal/agenote-browse ()
  "打开 agenote 子域浏览视图 *agenote-browse*。"
  (interactive)
  (let ((buf (get-buffer-create "*agenote-browse*")))
    (with-current-buffer buf
      (unless (eq major-mode 'literal/agenote-mode)
        (literal/agenote-mode))
      (literal/agenote--refresh)
      (literal/agenote--render-current-tab))
    (switch-to-buffer buf)))

;; =============================================================================
;; 健康度面板（agenote health，人类域）
;; =============================================================================
;;
;; `agenote health' 输出本身已是结构化人类可读文本（节标题 / 指标行带阈值与
;; ✅），无需重新解析。直接展示在 special-mode buffer，`g' 调
;; `agenote health --quality' 取更全数据（含内容长度 / 质量问题节）。
;; 注意：agenote health 只读人类域（experiences/），agent 子域健康度需另查
;; index.json（见浏览视图）。

(define-derived-mode literal/agenote-health-mode special-mode "agenote-health"
  "展示 `agenote health' 知识库健康度报告（人类域）。
\\{literal/agenote-health-mode-map}")

(defvar literal/agenote-health-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m "g" #'literal/agenote-health)
    m))

(defun literal/agenote--refresh-health-buffer ()
  "重新调 `agenote health --quality' 并填充当前 health buffer。"
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (or (cdr (literal/agenote--call-process literal:executable-agenote
                                          "health" "--quality"))
                "（agenote 命令不可用）"))
    (goto-char (point-min))))

;;;###autoload
(defun literal/agenote-health ()
  "打开知识库健康度面板 *agenote-health*（调 `agenote health --quality'）。
`g' 刷新。"
  (interactive)
  (if literal:executable-agenote
      (let ((buf (get-buffer-create "*agenote-health*")))
        (with-current-buffer buf
          (unless (eq major-mode 'literal/agenote-health-mode)
            (literal/agenote-health-mode))
          (literal/agenote--refresh-health-buffer))
        (switch-to-buffer buf))
    (message "未找到 agenote 命令")))

(provide 'literal-org-agenote)
;;; org-agenote.el ends here
