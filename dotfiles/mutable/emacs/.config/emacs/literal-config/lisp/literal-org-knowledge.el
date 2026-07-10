;;; org-knowledge.el --- 人类主笔知识库 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 人类主笔知识库：Emacs 端提供 Capture 写入 + 检索集成，
;; 底层由 agenote CLI（只读）提供跨会话搜索能力。
;;
;; 设计思路：
;; - 经验卡片存储在 ~/Documents/Org/experiences/ 按类别分子目录
;;   （如 experiences/emacs/、experiences/guix/）
;; - 卡片使用 Org PROPERTIES + 可选 TAGS 结构化存储元数据
;;   （CATEGORY、TECH、TYPE、STATUS 等）
;; - agenote CLI 是知识库的只读查询工具（get/list/search/fields/tags/stats）
;; - 写入完全由人类在 Emacs 中通过 Capture 完成
;; - 检索层使用 consult-ripgrep + agenote CLI
;;
;; 知识库目录结构（位于 literal:org-directory 下）：
;; - experiences/       经验卡片（按类别分子目录，capture 直接创建文件）
;; - inbox.org          通用收件箱
;;
;; 模板文件位于配置目录（版本控制）：
;; - configs/org/templates/experience-template.org
;;
;; 属性体系（对齐 agenote CLI 解析器）：
;; - CATEGORY:   类别（emacs、guix、general 等，自由输入）
;; - TECH:       技术栈（逗号分隔）
;; - TYPE:       类型（debug|refactor|research|workflow|feature|config）
;; - STATUS:     状态（inprogress|done|stable|cancelled）
;;
;; 快捷键（C-c o k 前缀）：
;; - C-c o k c    新建经验卡片（走 org-capture，选 entry_type：note/mistake/ascended）
;; - C-c o k s    全文检索经验（ripgrep）
;; - C-c o k t    按标签检索经验（agenote tags）
;; - C-c o k I    打开收件箱
;; - C-c o k S    知识库统计（agenote stats）
;; - C-c o k v    可视化知识库（类别树 / 时间线，见 org-knowledge-viz.el）
;; - C-c o k V    在浏览器打开知识库可视化（agenote viz --open）
;; 生命周期管理（agenote CRUD）：
;; - C-c o k a    将 inbox 条目归档到 experiences/<category>/
;; - C-c o k d    检测重复卡片（agenote deduplicate）
;; - C-c o k e    合并卡片（次卡并入主卡，agenote merge）
;; - C-c o k l    格式校验所有经验卡片（agenote lint，前缀参数则 --fix）
;; - C-c o k m    记忆系统概览/操作（agenote memory）
;; - C-c o k n    双向链接两张卡片（agenote connect）
;; - C-c o k o    提交知识库变更到 git（agenote commit）
;; - C-c o k r    审查当前经验卡片（agenote review）
;; - C-c o k u    更新卡片 LAST_USED + LAST_VERIFIED（agenote touch）
;;
;; capture 实现：org-mode.el 的 `org-capture-templates' 定义 kn/km/ka 三条
;; 模板（对齐 agenote-base entry-types 语义），`C-c o k c' 调
;; `literal/knowledge-capture' → `(org-capture nil "k")' 分发。
;;
;; 作为 org-mode.el 的扩展，延迟加载直到 org 包加载完成。

;;; Code:

(require 'cl-lib)
(require 'seq)

;; ═════════════════════════════════════════════════════════════════════════════
;; 注入点：路径与外部命令（由 init.el 注入）
;; ═════════════════════════════════════════════════════════════════════════════
(defvar literal:org-directory nil
  "Org 文件根目录。由 init.el 注入。")
(defvar literal:org-inbox-file nil
  "通用收件箱文件路径。由 init.el 注入。")
(defvar literal:org-knowledge-directory nil
  "知识库经验卡片目录（人类域）。由 init.el 注入。")
(defvar literal:executable-agenote nil
  "agenote CLI 可执行文件路径。nil 表示未注入（命令不可用）。")

(defun literal/knowledge--call-process (command &rest args)
  "同步执行 COMMAND 与 ARGS，返回 (STATUS . OUTPUT)。
本模块私有拷贝，避免依赖 literal-bootstrap。
STATUS 为进程退出码（0 = 成功），OUTPUT 为 stdout 的 trimmed 字符串。"
  (with-temp-buffer
    (cons (or (apply #'call-process command nil t nil (remq nil args))
              -1)
          (string-trim (buffer-string)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 辅助：递归扫描 experiences 目录
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/knowledge--collect-org-files (dir)
  "递归收集 DIR 下所有 .org 文件（含子目录）。"
  (when (file-directory-p dir)
    (let (result)
      (dolist (entry (directory-files-and-attributes dir t nil t))
        (let ((name (car entry))
              (type (file-attribute-type (cdr entry))))
          (cond
           ((string-prefix-p "." (file-name-nondirectory name)))
           ((eq type t)
            (setq result (nconc result (literal/knowledge--collect-org-files name))))
           ((string-match-p "\\.org\\'" name)
            (push name result)))))
      (nreverse result))))

;; 公开别名:双横线名为模块私有约定,跨模块调用(dashboard 收集知识库文件)
;; 应走公开 API。defalias 让 dashboard 调 literal/knowledge-collect-org-files。
(defalias 'literal/knowledge-collect-org-files #'literal/knowledge--collect-org-files)

;; ═════════════════════════════════════════════════════════════════════════════
;; 目录确保
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--ensure-knowledge-directories ()
  "确保知识库相关目录和索引文件存在。
experiences/ 下的类别子目录在 Capture 时按需创建，不在此处预建。"
  (let ((dirs (list (expand-file-name "experiences" literal:org-directory))))
    (dolist (dir dirs)
      (unless (file-exists-p dir)
        (make-directory dir t))))
  (dolist (file (list literal:org-inbox-file))
    (unless (file-exists-p file)
      (let ((base (file-name-base file)))
        (with-temp-buffer
          (insert (format "#+title: %s\n#+date: [%s]\n\n* Inbox\n"
                          base (format-time-string "%Y-%m-%d %a")))
          (write-region (point-min) (point-max) file))))))

(run-with-idle-timer 3 nil #'custom--ensure-knowledge-directories)

;; ═════════════════════════════════════════════════════════════════════════════
;; 新建经验卡片
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/knowledge-capture ()
  "捕获一张经验卡片，走 org-capture 模板。
`org-capture nil \"k\"' 进入 k 前缀子菜单（note/mistake/ascended，
对齐 agenote-base entry-types 语义），由 `org-capture-templates' 的
kn/km/ka 三条模板负责生成结构化 PROPERTIES + body 章节，落到
experiences/<category>/<timestamp>.org。模板定义见 org-mode.el。"
  (interactive)
  (if (bound-and-true-p org-capture-templates)
      (org-capture nil "k")
    (message "org-capture-templates 未配置，无法捕获经验卡")))

(defun literal/knowledge-rename-card ()
  "将当前经验卡片重命名为 <标题>-<时间戳>.org。
从文件第一行标题提取名称，保留 :ID: 中的原始时间戳。
仅在 experiences/ 目录下的文件有效。
若标题为空或文件已符合命名格式则跳过。"
  (interactive)
  (let* ((file (buffer-file-name))
         (dir (expand-file-name "experiences" literal:org-directory)))
    ;; 检查是否在 experiences/ 下
    (unless (and file (string-prefix-p dir (expand-file-name file)))
      (message "当前文件不在 experiences/ 目录中")
      (cl-return-from literal/knowledge-rename-card nil))
    ;; 获取标题
    (save-excursion
      (goto-char (point-min))
      (let ((heading (org-get-heading t t t t)))
        (unless (and heading (not (string-empty-p (string-trim heading))))
          (message "请先填写卡片标题再重命名")
          (cl-return-from literal/knowledge-rename-card nil))
        ;; 清洗标题为文件名安全格式
        (let* ((slug (literal/knowledge--heading-to-slug heading))
               (ts (literal/knowledge--extract-timestamp file))
               (new-name (format "%s-%s.org" slug ts))
               (new-file (expand-file-name new-name (file-name-directory file))))
          (when (string-empty-p slug)
            (message "标题清洗后为空，无法生成文件名")
            (cl-return-from literal/knowledge-rename-card nil))
          (when (string= (file-name-nondirectory file) new-name)
            (message "文件名已符合格式: %s" new-name)
            (cl-return-from literal/knowledge-rename-card nil))
          (when (and (not (string= file new-file)) (file-exists-p new-file))
            (message "目标文件已存在: %s" new-name)
            (cl-return-from literal/knowledge-rename-card nil))
          ;; 保存并重命名
          (when (and (buffer-modified-p) (y-or-n-p "文件尚未保存，是否先保存？"))
            (save-buffer))
          (rename-file file new-file 1)
          (set-visited-file-name new-file t t)
          (message "已重命名为: %s" new-name)
          ;; 同步索引
          (when literal:executable-agenote
            (call-process literal:executable-agenote nil 0 nil "reindex")))))))

(defun literal/knowledge-rename-all-cards ()
  "批量重命名 experiences/ 下所有不符合 <标题>-<时间戳>.org 格式的卡片。
扫描 experiences/ 递归子目录，跳过已有标题前缀的文件，
对纯时间戳文件名的卡片提取标题并重命名。
完成后输出汇总报告并重建索引。"
  (interactive)
  (let* ((exp-dir (expand-file-name "experiences" literal:org-directory))
         (files (literal/knowledge--collect-org-files exp-dir))
         (renamed 0) (skipped-no-title 0) (skipped-named 0) (skipped-conflict 0) (errors 0))
    (unless files
      (message "experiences/ 下没有 .org 文件")
      (cl-return-from literal/knowledge-rename-all-cards nil))
    (unless (y-or-n-p (format "将对 %d 个文件执行批量重命名，继续？" (length files)))
      (message "已取消")
      (cl-return-from literal/knowledge-rename-all-cards nil))
    (dolist (file files)
      (condition-case err
          (let* ((name (file-name-nondirectory file))
                 (base (file-name-base file)))
            ;; 跳过已有标题前缀的文件（含 - 在时间戳之前的）
            (if (literal/knowledge--has-title-prefix base)
                (cl-incf skipped-named)
              (let ((heading (literal/knowledge--heading-from-file file)))
                (if (or (not heading) (string-empty-p (string-trim heading)))
                    (cl-incf skipped-no-title)
                  (let* ((slug (literal/knowledge--heading-to-slug heading))
                         (ts (literal/knowledge--extract-timestamp file))
                         (new-name (format "%s-%s.org" slug ts))
                         (new-file (expand-file-name new-name (file-name-directory file))))
                    (cond
                     ((string-empty-p slug) (cl-incf skipped-no-title))
                     ((string= name new-name) (cl-incf skipped-named))
                     ((file-exists-p new-file) (cl-incf skipped-conflict))
                     (t
                      (rename-file file new-file 1)
                      (cl-incf renamed))))))))
        (error
         (message "处理 %s 时出错: %S" (file-name-nondirectory file) err)
         (cl-incf errors))))
    ;; 汇总
    (message (concat "批量重命名完成：%d 已重命名, "
                     "%d 跳过(无标题), %d 跳过(已有前缀), "
                     "%d 跳过(冲突), %d 错误")
             renamed skipped-no-title skipped-named skipped-conflict errors)
    ;; 统一重建索引
    (when (and literal:executable-agenote (> renamed 0))
      (call-process literal:executable-agenote nil 0 nil "reindex")
      (message "索引已同步"))))

(defun literal/knowledge--has-title-prefix (base-name)
  "判断文件名 BASE-NAME 是否已有标题前缀。
纯时间戳格式 YYYYMMDD-HHMMSS 返回 nil；
标题-时间戳格式（如 修复-Emacs-20260621-172421）返回 t。"
  (not (string-match "\\`[0-9]\\{8\\}-[0-9]\\{6\\}\\'" base-name)))

(defun literal/knowledge--heading-from-file (file)
  "从磁盘 FILE 中提取第一个 Org 标题文本，不访问 buffer。"
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward "^\\*+\\s-+\\(.*\\)" nil t)
        (string-trim (match-string 1))))))

(defun literal/knowledge--heading-to-slug (heading)
  "将 Org 标题 HEADING 转换为文件名安全的 slug。
保留中文字符，替换空白/分隔符为连字符。"
  (let* ((s heading)
         ;; 移除 Org link 语法
         (s (replace-regexp-in-string "\\[\\[.*?\\]\\[\\(.*?\\)\\]\\]" "\\1" s))
         ;; 移除 file: 前缀
         (s (replace-regexp-in-string "file:[^]]*" "" s))
         ;; 替换连续非字母数字/中文/连字符为单个 -
         (s (replace-regexp-in-string "[^[:alnum:]\u4e00-\u9fff-]+" "-" s))
         ;; 合并连续连字符
         (s (replace-regexp-in-string "-+" "-" s))
         ;; 去头尾连字符
         (s (replace-regexp-in-string "^-\\|-\\'" "" s)))
    s))

(defun literal/knowledge--extract-timestamp (file)
  "从 FILE 的 :ID: 属性或文件名中提取时间戳。
优先使用 :ID: 属性值（创建时间），回退到文件名字中的时间戳。"
  (or (literal/knowledge--id-from-properties file)
      (literal/knowledge--ts-from-filename file)
      (format-time-string "%Y%m%d-%H%M%S")))

(defun literal/knowledge--id-from-properties (file)
  "从 FILE 的 PROPERTIES 中读取 :ID: 值。"
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward ":ID:\\s-+\\([0-9]\\{8\\}-[0-9]\\{6\\}\\)" nil t)
        (match-string 1)))))

(defun literal/knowledge--ts-from-filename (file)
  "从 FILE 文件名中提取 YYYYMMDD-HHMMSS 格式的时间戳。"
  (let ((name (file-name-base file)))
    (when (string-match "\\([0-9]\\{8\\}-[0-9]\\{6\\}\\)" name)
      (match-string 1 name))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 检索函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/knowledge-search (query)
  "在知识库中全文检索经验。
使用 consult-ripgrep 递归搜索 experiences/。"
  (interactive "s检索关键词: ")
  (let ((dir (expand-file-name "experiences" literal:org-directory)))
    (cond
     ((fboundp 'consult-ripgrep)
      (consult-ripgrep (list dir) query))
     ((fboundp 'rgrep)
      (rgrep query "*.org" (list dir)))
     (t
      (message "未找到可用的搜索工具")))))

(defun literal/knowledge-search-by-tag (tag)
  "在知识库中按标签检索经验。
优先使用 agenote tags 命令，回退到 ripgrep 搜索 :TAG: 模式。"
  (interactive "s标签: ")
  (if literal:executable-agenote
      (let ((buf (get-buffer-create "*agenote-tags*")))
        (with-current-buffer buf
          (erase-buffer)
          (insert (cdr (literal/knowledge--call-process literal:executable-agenote "tags" tag))))
        (display-buffer buf))
    (literal/knowledge-search (format ":%s:" tag))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Inbox 归档
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/knowledge-archive-inbox-entry (category)
  "将 inbox.org 中光标所在的条目归档到 experiences/<CATEGORY>/ 目录。
提取标题作为文件名，移动整个 subtree 到新文件，并从 inbox.org 中删除原条目。
归档完成后调用 `agenote reindex` 重建索引。"
  (interactive
   (list (completing-read "归档分类: "
                           (or (condition-case nil
                                   (process-lines literal:executable-agenote "fields" "--category")
                                 (error nil))
                               '("emacs" "guix" "general" "gamedev" "devops" "research" "tooling"))
                           nil t)))
  (let* ((inbox-file literal:org-inbox-file)
         (exp-dir (expand-file-name (concat "experiences/" category) literal:org-directory))
         (heading (org-get-heading t t t t))
         (title (if (or (not heading) (string-empty-p heading))
                    (format-time-string "entry-%Y%m%d-%H%M%S")
                  (let* ((s (replace-regexp-in-string "\\[\\[.*?\\]\\[\\(.*?\\)\\]\\]" "\\1" heading))
                         (s (replace-regexp-in-string "[^[:alnum:]_-]+" "-" s))
                         (s (replace-regexp-in-string "-+" "-" s))
                         (s (replace-regexp-in-string "^-\\|-\\'" "" s)))
                    (format "%s-%s" (format-time-string "%Y%m%d-%H%M%S") s))))
         (target-file (expand-file-name (concat title ".org") exp-dir)))
    (unless (file-directory-p exp-dir)
      (make-directory exp-dir t))
    (org-copy-subtree)
    (with-temp-buffer
      (insert (car kill-ring))
      (write-region (point-min) (point-max) target-file))
    (org-cut-subtree)
    (message "已归档到 %s" (file-relative-name target-file literal:org-directory))
    ;; 同步重建索引
    (when literal:executable-agenote
      (message "正在重建知识库索引...")
      (call-process literal:executable-agenote nil 0 nil "reindex")
      (message "索引已同步"))))

;; ═════════════════════════════════════════════════════════════════════════════
;; agenote CLI 集成
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/knowledge-stats ()
  "显示知识库统计信息（调用 agenote stats）。"
  (interactive)
  (if literal:executable-agenote
      (let ((buf (get-buffer-create "*agenote-stats*")))
        (with-current-buffer buf
          (erase-buffer)
          (insert (cdr (literal/knowledge--call-process literal:executable-agenote "stats")))
          (goto-char (point-min)))
        (display-buffer buf))
    (message "未找到 agenote 命令")))

(defun literal/knowledge-open-file (file)
  "打开知识库 FILE。"
  (interactive "f知识库文件: ")
  (let ((target-file (expand-file-name file)))
    (find-file target-file)))

(defun literal/knowledge-open-inbox ()
  "打开知识库收件箱。"
  (interactive)
  (literal/knowledge-open-file literal:org-inbox-file))

;; ═════════════════════════════════════════════════════════════════════════════
;; 卡片生命周期（agenote touch/archive/restore/review）
;; ═══════════════════════════════════════════════════════ agenote CLI 不跨域 ──
;;
;; 这些命令作用于人类域（experiences/）卡片，ID 从当前 buffer 的 :ID: 属性取。
;; 在非经验卡片 buffer 调用会提示并 abort。

(defun literal/knowledge--current-id ()
  "从当前 buffer 的 PROPERTIES 取 :ID: 值。
返回 ID 字符串或 nil（当前 buffer 非经验卡片 / 无 :ID:）。"
  (when (and (eq major-mode 'org-mode)
             (buffer-file-name))
    (org-with-wide-buffer
     (goto-char (point-min))
     (when (re-search-forward "^:ID:\\s-+\\([0-9]\\{8\\}-[0-9]\\{6\\}\\)" nil t)
       (match-string 1)))))

(defun literal/knowledge--ensure-experience-buffer ()
  "确保当前 buffer 是人类域经验卡片，返回其 :ID:。
否则 message 报错并返回 nil。人类域 = buffer 文件位于
`literal:org-knowledge-directory' 之下（不含 agenote 子域）。"
  (let ((id (literal/knowledge--current-id))
        (file (buffer-file-name))
        (exp-dir (expand-file-name literal:org-knowledge-directory))
        (agenote-dir (expand-file-name "agenote" literal:org-directory)))
    (cond
     ((null file)
      (message "当前 buffer 无关联文件") nil)
     ((string-prefix-p agenote-dir (expand-file-name file))
      (message "当前卡片在 agenote 子域，agenote CLI 不跨域，请在人类域操作") nil)
     ((not (string-prefix-p exp-dir (expand-file-name file)))
      (message "当前文件不在 experiences/ 下") nil)
     ((null id)
      (message "当前卡片无 :ID: 属性") nil)
     (t id))))

(defun literal/knowledge-touch (&optional used-only)
  "更新当前经验卡片的 LAST_USED + LAST_VERIFIED（调 `agenote touch <ID>'）。
带前缀参数 USED-ONLY 时只更新 LAST_USED。"
  (interactive "P")
  (let ((id (literal/knowledge--ensure-experience-buffer)))
    (when id
      (if literal:executable-agenote
          (let ((result (apply #'literal/knowledge--call-process
                               literal:executable-agenote "touch" id
                               (when used-only '("--used-only")))))
            (if (zerop (car result))
                (message "已 touch: %s%s" id (if used-only " (仅 USED)" ""))
              (message "touch 失败: %s" (cdr result))))
        (message "未找到 agenote 命令")))))

(defun literal/knowledge-archive (reason)
  "归档当前经验卡片（调 `agenote archive <ID> --reason REASON'）。
卡片被移到 archived/，可通过 `literal/knowledge-restore' 恢复。"
  (interactive "s归档原因: ")
  (let ((id (literal/knowledge--ensure-experience-buffer)))
    (when id
      (if literal:executable-agenote
          (let* ((result (literal/knowledge--call-process literal:executable-agenote
                                              "archive" id "--reason" reason)))
            (if (zerop (car result))
                (message "已归档: %s (%s)" id reason)
              (message "归档失败: %s" (cdr result))))
        (message "未找到 agenote 命令")))))

(defun literal/knowledge-restore (id)
  "恢复已归档的经验卡片（调 `agenote restore <ID>'）。
ID 通过 completing-read 从归档列表选取（若可获取），否则手动输入。"
  (interactive
   (list (read-string "恢复的卡片 ID: "
                      (when-let* ((cur (literal/knowledge--current-id)))
                        cur))))
  (if literal:executable-agenote
      (let ((result (literal/knowledge--call-process literal:executable-agenote "restore" id)))
        (if (zerop (car result))
            (message "已恢复: %s" id)
          (message "恢复失败: %s" (cdr result))))
    (message "未找到 agenote 命令")))

(defun literal/knowledge-review ()
  "审查当前经验卡片（调 `agenote review <ID>'），输出显示在临时 buffer。"
  (interactive)
  (let ((id (literal/knowledge--ensure-experience-buffer)))
    (when id
      (if literal:executable-agenote
          (let ((buf (get-buffer-create "*agenote-review*"))
                (result (literal/knowledge--call-process literal:executable-agenote "review" id)))
            (with-current-buffer buf
              (erase-buffer)
              (insert (cdr result))
              (goto-char (point-min)))
            (display-buffer buf))
        (message "未找到 agenote 命令")))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 其余 CLI 能力（memory / connect / merge / deduplicate / lint / commit）
;; ═════════════════════════════════════════════════════════════════════════════
;;
;; 这些命令大多带子选项或作用于多 ID，封装时让 minibuffer 收集参数后一次性
;; 同步调用，结果展示在对应 buffer 或 message。`agenote profile' 不存在，
;; 已从设计删除（plan §3.6 实测核对）。

(defun literal/knowledge-memory (arg)
  "记忆系统概览或操作。
无前缀：调 `agenote memory' 显示概览到 buffer。
前缀 ARG 非 nil：提示操作（--stale / --type X）。"
  (interactive "P")
  (if literal:executable-agenote
      (let* ((extra-args (if arg
                             (let ((op (completing-read
                                        "memory 操作: "
                                        '("--stale" "--type feedback"
                                          "--type project" "--type reference")
                                        nil t)))
                               (split-string-and-unquote op))
                           nil))
             (result (apply #'literal/knowledge--call-process
                            literal:executable-agenote "memory" extra-args))
             (buf (get-buffer-create "*agenote-memory*")))
        (with-current-buffer buf
          (erase-buffer)
          (insert (cdr result))
          (goto-char (point-min)))
        (display-buffer buf))
    (message "未找到 agenote 命令")))

(defun literal/knowledge-connect (id-a id-b &optional desc)
  "双向链接两张卡片（调 `agenote connect ID_A ID_B --desc DESC'）。
ID-A 默认取当前 buffer 的 :ID:，ID-B 与 DESC 在 minibuffer 收集。
打通 agenote 卡片与 org-roam 的关系靠 agenote 自身的双链。"
  (interactive
   (let* ((a (or (literal/knowledge--current-id)
                 (read-string "主卡片 ID: ")))
          (b (read-string "链接到卡片 ID: "))
          (d (read-string "描述 (可选): ")))
     (list a b d)))
  (if literal:executable-agenote
      (let* ((args (delq nil (list "connect" id-a id-b
                                   (unless (string-empty-p desc) "--desc")
                                   (unless (string-empty-p desc) desc))))
             (result (apply #'literal/knowledge--call-process
                            literal:executable-agenote args)))
        (if (zerop (car result))
            (message "已链接: %s ↔ %s" id-a id-b)
          (message "链接失败: %s" (cdr result))))
    (message "未找到 agenote 命令")))

(defun literal/knowledge-merge (primary-id secondary-ids reason)
  "合并卡片：把 SECONDARY-IDS 并入 PRIMARY-ID（调 `agenote merge'）。
SECONDARY-IDS 为空格分隔的多个 ID，REASON 记录合并原因。"
  (interactive
   (let* ((p (or (literal/knowledge--current-id)
                 (read-string "主卡片 ID（保留）: ")))
          (s (read-string "次卡片 ID（合并后删除，多个用空格）: "))
          (r (read-string "合并原因: ")))
     (list p (split-string s) r)))
  (if literal:executable-agenote
      (let* ((args (append (list "merge" primary-id) secondary-ids
                           (unless (string-empty-p reason)
                             (list "--reason" reason))))
             (result (apply #'literal/knowledge--call-process literal:executable-agenote args)))
        (if (zerop (car result))
            (message "已合并 %d 张到 %s" (length secondary-ids) primary-id)
          (message "合并失败: %s" (cdr result))))
    (message "未找到 agenote 命令")))

(defun literal/knowledge-deduplicate ()
  "检测重复卡片（调 `agenote deduplicate'），结果显示在 buffer。"
  (interactive)
  (if literal:executable-agenote
      (let ((buf (get-buffer-create "*agenote-deduplicate*"))
            (result (literal/knowledge--call-process literal:executable-agenote
                                         "deduplicate")))
        (with-current-buffer buf
          (erase-buffer)
          (insert (cdr result))
          (goto-char (point-min)))
        (display-buffer buf))
    (message "未找到 agenote 命令")))

(defun literal/knowledge-lint (arg)
  "格式校验所有经验卡片（调 `agenote lint'）。
无前缀：仅检查并显示报告。
前缀 ARG 非 nil：调 `agenote lint --fix' 自动修复。"
  (interactive "P")
  (if literal:executable-agenote
      (let* ((args (if arg (list "lint" "--fix") (list "lint" "--check")))
             (result (apply #'literal/knowledge--call-process literal:executable-agenote args))
             (buf (get-buffer-create "*agenote-lint*")))
        (with-current-buffer buf
          (erase-buffer)
          (insert (cdr result))
          (goto-char (point-min)))
        (display-buffer buf)
        (when (and arg (zerop (car result)))
          (message "已自动修复格式问题")))
    (message "未找到 agenote 命令")))

(defun literal/knowledge-commit (summary)
  "提交知识库变更到 git（调 `agenote commit -m SUMMARY'）。
index.json 由 .gitignore 排除，仅提交卡片与 MEMORY 变更。"
  (interactive "s提交总结: ")
  (if literal:executable-agenote
      (let ((result (literal/knowledge--call-process literal:executable-agenote
                                         "commit" "-m" summary)))
        (if (zerop (car result))
            (message "已提交: %s" summary)
          (message "提交失败: %s" (cdr result))))
    (message "未找到 agenote 命令")))

;; ═════════════════════════════════════════════════════════════════════════════
;; Agenda 集成
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/knowledge--setup-agenda ()
  "将经验目录加入 agenda 自定义命令。"
  (add-to-list
   'org-agenda-custom-commands
   '("K" "知识库回顾"
     ((tags "difficulties|lessons"
            ((org-agenda-files (list (expand-file-name "experiences" literal:org-directory)))
             (org-agenda-sorting-strategy '(timestamp-down))))))
   t))

;; ═════════════════════════════════════════════════════════════════════════════
;; 初始化
;; ═════════════════════════════════════════════════════════════════════════════

(with-eval-after-load 'org-agenda
  (literal/knowledge--setup-agenda))

(provide 'literal-org-knowledge)
;;; org-knowledge.el ends here
;;; org-knowledge-viz.el --- 知识库可视化（类别树 / 时间线） -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 知识库可视化：在 Emacs 内提供 *kb-viz* 双 tab 视图，
;; 将人类域 index.json（~/Documents/Org/index.json）以两个维度呈现。
;; 浏览器版（C-c o k V）调用 `agenote viz --open`，默认合并双域
;; （--domain all：人类域 + agenote 子域），与 Emacs 内嵌视图数据源不同。
;;
;; 两个 Tab：
;; - Tab 1 类别树：按 category 分组的折叠表格
;; - Tab 2 时间线：按陈旧度排序的表格
;;
;; 快捷键：C-c o k v（Emacs 内嵌）、C-c o k V（浏览器版）
;;
;; 命名约定：literal/knowledge-viz--*（函数）、literal--knowledge-viz-*（私有变量）

;;; Code:

;; =============================================================================
;; 常量
;; =============================================================================

(defconst custom:knowledge-viz-index-file
  (expand-file-name "index.json" literal:org-directory)
  "index.json 路径。")

(defconst custom:knowledge-viz-experiences-dir
  (expand-file-name "experiences" literal:org-directory)
  "经验卡片目录。")

;; =============================================================================
;; 数据层（纯函数）
;; =============================================================================

(defun literal/knowledge-viz--load-index ()
  "读取 index.json，返回卡片 plist 列表。"
  (when (file-readable-p custom:knowledge-viz-index-file)
    (let ((json-object-type 'plist)
          (json-array-type 'list)
          (json-key-type 'keyword))
      (with-temp-buffer
        (insert-file-contents custom:knowledge-viz-index-file)
        (goto-char (point-min))
        (plist-get (json-read) :cards)))))

(defun literal/knowledge-viz--parse-org-timestamp (ts)
  "解析 Org 时间戳 TS 为内部时间。支持 [YYYY-MM-DD ...] 和 YYYY-MM-DD。"
  (when (and ts (not (string= ts "")))
    (when (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" ts)
      (let ((d (match-string 1 ts)))
        (encode-time 0 0 0
                     (string-to-number (substring d 8 10))
                     (string-to-number (substring d 5 7))
                     (string-to-number (substring d 0 4)))))))

(defun literal/knowledge-viz--days-since (timestamp)
  "TIMESTAMP 到现在的天数。nil 返回 most-positive-fixnum。"
  (if timestamp
      (floor (/ (float-time (time-subtract nil timestamp)) 86400.0))
    most-positive-fixnum))

(defun literal/knowledge-viz--compute-staleness (card)
  "返回 (DAYS . BUCKET)。BUCKET 为 fresh/recent/aging/stale/critical。"
  (let* ((v (or (literal/knowledge-viz--parse-org-timestamp (plist-get card :last_verified))
                (literal/knowledge-viz--parse-org-timestamp (plist-get card :created))))
         (days (literal/knowledge-viz--days-since v))
         (bucket (cond ((< days 7) 'fresh) ((< days 30) 'recent)
                       ((< days 60) 'aging) ((< days 180) 'stale) (t 'critical))))
    (cons days bucket)))

(defun literal/knowledge-viz--compute-stats (cards)
  "聚合统计。返回 plist。"
  (let ((total (length cards))
        (done 0) (stable 0) (inprog 0) (cancel 0)
        (stale-60 0) (stale-180 0)
        (by-cat (make-hash-table :test 'equal))
        (by-type (make-hash-table :test 'equal))
        (by-owner (make-hash-table :test 'equal))
        (by-tech (make-hash-table :test 'equal)))
    (dolist (c cards)
      (let* ((days (car (literal/knowledge-viz--compute-staleness c)))
             (s (plist-get c :status))
             (tech-str (plist-get c :tech)))
        (pcase s ("done" (cl-incf done)) ("stable" (cl-incf stable))
          ("inprogress" (cl-incf inprog)) ("cancelled" (cl-incf cancel)))
        (when (>= days 60) (cl-incf stale-60))
        (when (>= days 180) (cl-incf stale-180))
        (puthash (or (plist-get c :category) "?")
                 (1+ (gethash (or (plist-get c :category) "?") by-cat 0)) by-cat)
        (puthash (or (plist-get c :type) "?")
                 (1+ (gethash (or (plist-get c :type) "?") by-type 0)) by-type)
        (puthash (or (plist-get c :owner) "?")
                 (1+ (gethash (or (plist-get c :owner) "?") by-owner 0)) by-owner)
        (when tech-str
          (dolist (t_ (split-string tech-str "," t "[ \t]+"))
            (puthash t_ (1+ (gethash t_ by-tech 0)) by-tech)))))
    (list :total total :done done :stable stable :inprogress inprog :cancelled cancel
          :stale-60 stale-60 :stale-180 stale-180
          :by-category by-cat :by-type by-type :by-owner by-owner :by-tech by-tech)))

;; =============================================================================
;; Buffer 缓存
;; =============================================================================

(defvar-local literal--knowledge-viz-cards nil)
(defvar-local literal--knowledge-viz-stats nil)
(defvar-local literal--knowledge-viz-index-mtime nil)
(defvar-local literal--knowledge-viz-current-tab 1)
(defvar-local literal--knowledge-viz-tree-expanded nil)

(defun literal/knowledge-viz--refresh ()
  "刷新缓存（mtime 变化时才重新解析）。"
  (let ((mt (nth 5 (file-attributes custom:knowledge-viz-index-file))))
    (unless (and literal--knowledge-viz-cards literal--knowledge-viz-index-mtime
                 (time-equal-p mt literal--knowledge-viz-index-mtime))
      (setq literal--knowledge-viz-cards (literal/knowledge-viz--load-index))
      (setq literal--knowledge-viz-stats (literal/knowledge-viz--compute-stats literal--knowledge-viz-cards))
      (setq literal--knowledge-viz-index-mtime mt))))

;; =============================================================================
;; Faces
;; =============================================================================

(defface literal/knowledge-viz--status-done '((t (:inherit success :weight bold))) "")
(defface literal/knowledge-viz--status-stable '((t (:inherit font-lock-type-face :weight bold))) "")
(defface literal/knowledge-viz--status-inprogress '((t (:inherit warning :weight bold))) "")
(defface literal/knowledge-viz--status-cancelled '((t (:inherit error :weight bold))) "")
(defface literal/knowledge-viz--stale-fresh '((t (:inherit success))) "")
(defface literal/knowledge-viz--stale-recent '((t (:inherit font-lock-type-face))) "")
(defface literal/knowledge-viz--stale-aging '((t (:inherit warning))) "")
(defface literal/knowledge-viz--stale-stale '((t (:inherit font-lock-variable-name-face))) "")
(defface literal/knowledge-viz--stale-critical '((t (:inherit error :weight bold))) "")
(defface literal/knowledge-viz--tab-active '((t (:weight bold :underline t :inherit mode-line-highlight))) "")
(defface literal/knowledge-viz--tab-inactive '((t (:inherit shadow))) "")

(defun literal/knowledge-viz--status-face (s)
  (pcase s ("done" 'literal/knowledge-viz--status-done)
    ("stable" 'literal/knowledge-viz--status-stable)
    ("inprogress" 'literal/knowledge-viz--status-inprogress)
    ("cancelled" 'literal/knowledge-viz--status-cancelled) (_ nil)))

(defun literal/knowledge-viz--stale-face (b)
  (pcase b ('fresh 'literal/knowledge-viz--stale-fresh)
    ('recent 'literal/knowledge-viz--stale-recent)
    ('aging 'literal/knowledge-viz--stale-aging)
    ('stale 'literal/knowledge-viz--stale-stale)
    ('critical 'literal/knowledge-viz--stale-critical) (_ nil)))

;; =============================================================================
;; 共享 keymap
;; =============================================================================

(defvar literal--knowledge-viz-card-keymap
  (let ((m (make-sparse-keymap)))
    (define-key m "RET" #'literal/knowledge-viz--open-card-at-point)
    (define-key m [mouse-1] #'literal/knowledge-viz--open-card-at-point) m)
  "卡片行键映射。")

(defun literal/knowledge-viz--open-card-at-point ()
  "打开光标处的卡片文件。"
  (interactive)
  (let ((f (get-text-property (line-beginning-position) 'kb-file)))
    (when f (literal/knowledge-open-file (expand-file-name f literal:org-directory)))))

;; =============================================================================
;; Tab 1：类别树
;; =============================================================================

(defvar literal--knowledge-viz-tree-header-keymap
  (let ((m (make-sparse-keymap)))
    (define-key m "RET" #'literal/knowledge-viz--tree-toggle-at-point)
    (define-key m [mouse-1] #'literal/knowledge-viz--tree-toggle-at-point) m))

(defun literal/knowledge-viz--tree-toggle-at-point ()
  "切换光标处类别的展开/折叠状态。"
  (interactive)
  (let ((cat (get-text-property (line-beginning-position) 'category)))
    (when cat
      (unless literal--knowledge-viz-tree-expanded
        (setq literal--knowledge-viz-tree-expanded (make-hash-table :test 'equal)))
      (if (gethash cat literal--knowledge-viz-tree-expanded)
          (remhash cat literal--knowledge-viz-tree-expanded)
        (puthash cat t literal--knowledge-viz-tree-expanded))
      (literal/knowledge-viz--render-current-tab))))

(defun literal/knowledge-viz--insert-card-row (c)
  "插入一张卡片的行到当前 buffer。"
  (let* ((id (plist-get c :id))
         (title (or (plist-get c :title) "(无标题)"))
         (type (or (plist-get c :type) "?"))
         (owner (or (plist-get c :owner) "?"))
         (status (or (plist-get c :status) "?"))
         (days (car (literal/knowledge-viz--compute-staleness c)))
         (file (plist-get c :file))
         (sface (literal/knowledge-viz--status-face status))
         (line-start (point)))
    (insert
     (format "      %s %s %s %s %4dd  %s\n"
             (propertize (format "%-16s" id) 'face 'font-lock-constant-face)
             (propertize (truncate-string-to-width title 45 nil ?\s) 'face 'default)
             (propertize (format "%-10s" type) 'face 'font-lock-keyword-face)
             (propertize (truncate-string-to-width owner 6 nil ?\s) 'face 'font-lock-builtin-face)
             days
             (if sface (propertize status 'face sface) status)))
    (add-text-properties line-start (point)
                          (list 'keymap literal--knowledge-viz-card-keymap
                                'mouse-face 'highlight
                                'kb-file file 'kb-id id
                                'help-echo "RET 或鼠标点击打开卡片"))))

(defun literal/knowledge-viz--sort-by-staleness (cards)
  "按陈旧度升序排列 CARDS。"
  (sort (copy-sequence cards)
        (lambda (a b)
          (< (car (literal/knowledge-viz--compute-staleness a))
             (car (literal/knowledge-viz--compute-staleness b))))))

(defun literal/knowledge-viz--render-tree ()
  "渲染类别树。"
  (let* ((cards literal--knowledge-viz-cards)
         (stats literal--knowledge-viz-stats)
         (by-cat (plist-get stats :by-category))
         (cats nil)
         (inhibit-read-only t))
    (maphash (lambda (k _v) (push k cats)) by-cat)
    (setq cats (sort cats #'string<))
    (erase-buffer)
    (insert (format "知识库类别树（共 %d 张卡片，%d 个类别）\n\n"
                    (length cards) (length cats)))
    (dolist (cat cats)
      (literal/knowledge-viz--render-tree-category cat cards))))

(defun literal/knowledge-viz--render-tree-category (cat all-cards)
  "渲染单个 category 的树区域。"
  (let* ((cc (seq-filter
             (lambda (c) (equal (plist-get c :category) cat))
             all-cards))
         (dn 0) (st 0) (ip 0) (ca 0)
         (inhibit-read-only t))
    (dolist (c cc)
      (pcase (plist-get c :status)
        ("done" (cl-incf dn)) ("stable" (cl-incf st))
        ("inprogress" (cl-incf ip)) ("cancelled" (cl-incf ca))))
    ;; header
    (let* ((exp (and literal--knowledge-viz-tree-expanded
                   (gethash cat literal--knowledge-viz-tree-expanded)))
           (hdr (format "  %-20s %3d 张  [done:%d stable:%d inprog:%d cancel:%d]"
                        (propertize cat 'face 'bold) (length cc) dn st ip ca)))
      (insert (propertize (format "%s %s\n" (if exp "\u25bc" "\u25b6") hdr)
                          'category cat 'mouse-face 'highlight
                          'keymap literal--knowledge-viz-tree-header-keymap
                          'help-echo "RET 或鼠标点击展开/折叠")))
    ;; 子行
    (when (and literal--knowledge-viz-tree-expanded
               (gethash cat literal--knowledge-viz-tree-expanded))
      (dolist (c (literal/knowledge-viz--sort-by-staleness cc))
        (literal/knowledge-viz--insert-card-row c)))
    (insert "\n")))

;; =============================================================================
;; Tab 2：时间线
;; =============================================================================

(defun literal/knowledge-viz--render-timeline ()
  (let* ((cards literal--knowledge-viz-cards)
         (stats literal--knowledge-viz-stats)
         (inhibit-read-only t)
         (ws (mapcar (lambda (c) (cons c (literal/knowledge-viz--compute-staleness c))) cards))
         (sorted (sort ws (lambda (a b) (> (cadr a) (cadr b))))))
    (erase-buffer)
    (insert (format "共 %d 张卡片，陈旧(>60d)：%d，严重陈旧(>180d)：%d\n\n"
                    (plist-get stats :total) (plist-get stats :stale-60) (plist-get stats :stale-180)))
    (insert (format "状态分布：done:%d stable:%d inprogress:%d cancelled:%d\n\n"
                    (plist-get stats :done) (plist-get stats :stable)
                    (plist-get stats :inprogress) (plist-get stats :cancelled)))
    (insert (format "  %-16s %-40s %-12s %-10s %-6s %6s %s\n"
                    "ID" "标题" "类别" "类型" "Owner" "天数" "状态"))
    (insert (make-string 100 ?-) "\n")
    (dolist (entry sorted)
      (let* ((card (car entry))
             (st (cdr entry))
             (days (car st)) (bucket (cdr st))
             (id (plist-get card :id))
             (title (or (plist-get card :title) "(无标题)"))
             (cat (or (plist-get card :category) "?"))
             (type (or (plist-get card :type) "?"))
             (owner (or (plist-get card :owner) "?"))
             (status (or (plist-get card :status) "?"))
             (file (plist-get card :file))
             (ls (point)))
        (insert (format "  %s %s %s %s %s %s  %s\n"
                        (propertize (format "%-16s" id) 'face 'font-lock-constant-face)
                        (propertize (truncate-string-to-width title 40 nil ?\s) 'face 'default)
                        (propertize (format "%-12s" cat) 'face 'font-lock-keyword-face)
                        (propertize (format "%-10s" type) 'face 'font-lock-builtin-face)
                        (propertize (truncate-string-to-width owner 6 nil ?\s) 'face 'font-lock-builtin-face)
                        (propertize (format "%4dd" days) 'face (literal/knowledge-viz--stale-face bucket))
                        (propertize status 'face (literal/knowledge-viz--status-face status))))
        (add-text-properties ls (point)
                              (list 'keymap literal--knowledge-viz-card-keymap
                                    'mouse-face 'highlight
                                    'kb-file file 'kb-id id
                                    'help-echo "RET 或鼠标点击打开卡片"))))))

;; =============================================================================
;; 主模式
;; =============================================================================

(defvar literal/knowledge-viz-mode-map
  (let ((m (make-sparse-keymap)))
    (dolist (b (list (cons "1" #'literal/knowledge-viz-switch-tab-1)
                     (cons "2" #'literal/knowledge-viz-switch-tab-2)
                     (cons "M-1" #'literal/knowledge-viz-switch-tab-1)
                     (cons "M-2" #'literal/knowledge-viz-switch-tab-2)
                     (cons "g" #'literal/knowledge-viz--force-refresh)
                     (cons "q" #'bury-buffer)
                     (cons "o" #'literal/knowledge-viz-open-browser)))
      (define-key m (kbd (car b)) (cdr b)))
    m))

(define-derived-mode literal/knowledge-viz-mode special-mode "KB-Viz"
  "知识库可视化。\\{literal/knowledge-viz-mode-map}"
  (setq buffer-read-only t)
  (setq-local revert-buffer-function #'literal/knowledge-viz--force-refresh))

(defun literal/knowledge-viz--header-line ()
  (let ((tabs '((1 . "1 类别树") (2 . "2 时间线"))))
    (concat
     (string-join
      (mapcar (lambda (p)
                (propertize (format "[%s]" (cdr p))
                            'face (if (= (car p) literal--knowledge-viz-current-tab)
                                      'literal/knowledge-viz--tab-active
                                    'literal/knowledge-viz--tab-inactive)))
              tabs)
      "  ")
     "   "
     (propertize "g 刷新  q 关闭  o 浏览器" 'face 'shadow))))

(defun literal/knowledge-viz--render-current-tab ()
  (let ((inhibit-read-only t))
    (pcase literal--knowledge-viz-current-tab
      (1 (literal/knowledge-viz--render-tree))
      (2 (literal/knowledge-viz--render-timeline)))
    (setq header-line-format (literal/knowledge-viz--header-line))))

(defmacro literal/knowledge-viz--defswitch (n)
  `(defun ,(intern (format "literal/knowledge-viz-switch-tab-%d" n)) ()
     ,(format "切换到 Tab %d。" n) (interactive)
     (setq literal--knowledge-viz-current-tab ,n)
     (literal/knowledge-viz--render-current-tab)))

(literal/knowledge-viz--defswitch 1)
(literal/knowledge-viz--defswitch 2)

(defun literal/knowledge-viz--force-refresh (&rest _)
  (interactive)
  (setq literal--knowledge-viz-index-mtime nil)
  (literal/knowledge-viz--refresh)
  (literal/knowledge-viz--render-current-tab))

;; =============================================================================
;; 交互入口
;; =============================================================================

;;;###autoload
(defun literal/knowledge-viz ()
  "打开知识库可视化视图 *kb-viz*。"
  (interactive)
  (let ((buf (get-buffer-create "*kb-viz*")))
    (with-current-buffer buf
      (unless (eq major-mode 'literal/knowledge-viz-mode)
        (literal/knowledge-viz-mode))
      (literal/knowledge-viz--refresh)
      (literal/knowledge-viz--render-current-tab))
    (switch-to-buffer buf)))

(defun literal/knowledge-viz-open-browser ()
  "在浏览器中打开知识库可视化。
调用 `agenote viz --open'，默认合并双域（--domain all），
页面输出到 ~/Documents/Org/kb-viz.html 并用 xdg-open 打开。"
  (interactive)
  (if literal:executable-agenote
      (call-process literal:executable-agenote nil 0 nil "viz" "--open")
    (message "未找到 agenote 命令")))


;;; org-knowledge-viz.el ends here
