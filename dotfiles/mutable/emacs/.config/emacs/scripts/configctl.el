;;; configctl.el --- 面向 AI agent 的配置片段操纵工具 -*- lexical-binding: t; -*-

;; 定位：emacs.org 有 5700+ 行，agent 不应一次读整个文件。本工具只做四件事：
;;   map     — 结构总览（CUSTOM_ID / 行号 / 代码量 / noweb ref）
;;   show    — 提取一个功能子树全文
;;   locate  — 精确定位某个 CUSTOM_ID 的块行号区间，或某个 noweb ref 的定义/组装位置
;;   tangle  — 拼合 emacs.org -> main.el
;;   check   — 轻量原则检查（域顺序 / noweb 图 / 单产物 / 括号 / 重复定义）
;;
;; 深度验证（load 是否报错、ERT、包清单审计）不在本工具内，由 agent 直接跑 emacs 命令。

(require 'cl-lib)
(require 'org)
(require 'ob-tangle)
(require 'subr-x)

(defconst custom-configctl-root
  (file-name-directory
   (directory-file-name (file-name-directory (or load-file-name buffer-file-name)))))

(defconst custom-configctl-org-file
  (expand-file-name "emacs.org" custom-configctl-root))

(defconst custom-configctl-main-file
  (expand-file-name "main.el" custom-configctl-root))

(defconst custom-configctl-required-order
  '("startup" "appearance" "editing" "programming" "projects"
    "org-knowledge" "keys-completion" "system-tools"))

(defun custom-configctl--fail (format-string &rest args)
  (error "configctl: %s" (apply #'format format-string args)))

(defun custom-configctl--org-buffer ()
  (let ((buffer (find-file-noselect custom-configctl-org-file)))
    (with-current-buffer buffer
      (org-mode))
    buffer))

(defun custom-configctl--line-at (pos)
  "POS 处的绝对行号（始终在 emacs.org buffer 内计算）。"
  (with-current-buffer (custom-configctl--org-buffer)
    (save-excursion
      (goto-char pos)
      (line-number-at-pos))))

(defun custom-configctl--headlines ()
  (with-current-buffer (custom-configctl--org-buffer)
    (let ((tree (org-element-parse-buffer))
          result)
      (org-element-map tree 'headline
        (lambda (headline)
          (when-let* ((id (org-element-property :CUSTOM_ID headline)))
            (push (list :id id
                        :title (org-element-property :raw-value headline)
                        :level (org-element-property :level headline)
                        :begin (org-element-property :begin headline)
                        :end (org-element-property :end headline))
                  result))))
      (nreverse result))))

(defun custom-configctl--headline-params (headline)
  "HEADLINE 子树 drawer 声明的 header-args（语言专属优先于普通级）。"
  (append
   (org-babel-parse-header-arguments
    (or (org-element-property :HEADER-ARGS:EMACS-LISP headline) ""))
   (org-babel-parse-header-arguments
    (or (org-element-property :HEADER-ARGS headline) ""))))

(defun custom-configctl--block-header (block)
  "返回 BLOCK 生效的 (REF TANGLE OWNER KIND)。
REF/TANGLE 块头参数优先，否则用最近祖先标题 drawer 的 noweb-ref 声明；
OWNER 为最近祖先标题的 CUSTOM_ID。KIND 为 noweb-ref 或 name：
前者要求恰好被组装一次，后者（#+name 数据块）仅作引用解析目标。
TANGLE 默认 main.el。"
  (let* ((params (org-babel-parse-header-arguments
                  (or (org-element-property :parameters block) "")))
         (ref (cdr (assq :noweb-ref params)))
         (kind 'noweb-ref)
         (tangle (cdr (assq :tangle params)))
         (owner nil)
         (node (org-element-property :parent block)))
    (while node
      (when (eq (org-element-type node) 'headline)
        (unless owner
          (when-let* ((id (org-element-property :CUSTOM_ID node)))
            (setq owner id)))
        (unless ref
          (let ((hparams (custom-configctl--headline-params node)))
            (when-let* ((h-ref (cdr (assq :noweb-ref hparams))))
              (setq ref h-ref)
              (unless tangle
                (setq tangle (cdr (assq :tangle hparams))))))))
      (setq node (org-element-property :parent node)))
    (unless ref
      (when-let* ((name (org-element-property :name block)))
        (setq ref name
              kind 'name)))
    (list ref (or tangle "main.el") owner kind)))

(defun custom-configctl--block-p (block)
  "BLOCK 是否纳入索引：emacs-lisp 块或带 #+name 的任意语言数据块。"
  (or (string= (org-element-property :language block) "emacs-lisp")
      (org-element-property :name block)))

(defun custom-configctl--all-blocks ()
  "返回所有 emacs-lisp src block 的 (BEGIN END REF TANGLE BODY)。
BEGIN/END 为 buffer 绝对位置，REF 为生效 noweb-ref（块头或子树 drawer）或 nil，TANGLE 为输出目标。"
  (with-current-buffer (custom-configctl--org-buffer)
    (let ((tree (org-element-parse-buffer))
          result)
      (org-element-map tree 'src-block
        (lambda (block)
          (when (custom-configctl--block-p block)
            (pcase-let ((`(,ref ,tangle _owner _kind)
                         (custom-configctl--block-header block)))
              (push (list (org-element-property :begin block)
                          (org-element-property :end block)
                          ref tangle
                          (org-element-property :value block))
                    result)))))
      (nreverse result))))

(defun custom-configctl--source-info (begin end)
  (save-restriction
    (narrow-to-region begin end)
    (let ((tree (org-element-parse-buffer))
          (blocks 0)
          (code-lines 0)
          refs)
      (org-element-map tree 'src-block
        (lambda (block)
          (when (custom-configctl--block-p block)
            (when (string= (org-element-property :language block) "emacs-lisp")
              (cl-incf blocks)
              (cl-incf code-lines
                       (length (split-string
                                (org-element-property :value block) "\n" t))))
            (when-let* ((ref (car (custom-configctl--block-header block))))
              (push ref refs)))))
      (list blocks code-lines (delete-dups (nreverse refs))))))

;;; map — 结构总览

(defun custom-configctl-map ()
  (with-current-buffer (custom-configctl--org-buffer)
    (princ "ID                       LINE  CODE  TITLE / NOWEB\n")
    (princ "------------------------ ----- -----  ------------------------------\n")
    (dolist (item (custom-configctl--headlines))
      (pcase-let* ((`(,blocks ,code-lines ,refs)
                    (custom-configctl--source-info
                     (plist-get item :begin) (plist-get item :end)))
                   (line (custom-configctl--line-at (plist-get item :begin))))
        (when (> blocks 0)
          (princ (format "%-24s %5d %5d  %s%s\n"
                         (plist-get item :id) line code-lines
                         (plist-get item :title)
                         (if refs
                             (format " [%s]" (string-join refs ", "))
                           ""))))))))

;;; show — 提取功能子树

(defun custom-configctl--find-headline (query)
  (let* ((items (custom-configctl--headlines))
         (exact (cl-find query items :key (lambda (item) (plist-get item :id))
                         :test #'string=)))
    (or exact
        (let ((matches
               (cl-remove-if-not
                (lambda (item)
                  (string-match-p (regexp-quote (downcase query))
                                  (downcase (plist-get item :title))))
                items)))
          (pcase matches
            (`(,only) only)
            ('nil (custom-configctl--fail "unknown feature: %s" query))
            (_ (custom-configctl--fail
                "ambiguous feature %s: %s" query
                (string-join (mapcar (lambda (item) (plist-get item :id)) matches)
                             ", "))))))))

(defun custom-configctl-show (query)
  (let ((item (custom-configctl--find-headline query)))
    (with-current-buffer (custom-configctl--org-buffer)
      (princ (buffer-substring-no-properties
              (plist-get item :begin) (plist-get item :end))))))

;;; locate — 定位块行号区间（配合 Read/Edit 精准操作）

(defun custom-configctl-locate (query)
  (let* ((headlines (custom-configctl--headlines))
         (item (cl-find query headlines :key (lambda (i) (plist-get i :id))
                        :test #'string=))
         (blocks (custom-configctl--all-blocks)))
    (if item
        ;; CUSTOM_ID 模式：列出子树内所有块的行号区间
        (let ((begin (plist-get item :begin))
              (end (plist-get item :end)))
          (princ (format "CUSTOM_ID %s  (%s)  行 %d-%d\n"
                         query (plist-get item :title)
                         (custom-configctl--line-at begin)
                         (custom-configctl--line-at end)))
          (dolist (blk blocks)
            (when (and (>= (car blk) begin) (<= (cadr blk) end))
              (princ (format "  %5d-%d  %-24s -> %s\n"
                             (custom-configctl--line-at (car blk))
                             (custom-configctl--line-at (cadr blk))
                             (or (nth 2 blk) "(inline)")
                             (nth 3 blk))))))
      ;; noweb ref 模式：定位定义块 + 组装（引用）块
      (let ((defs (cl-remove-if-not (lambda (b) (equal (nth 2 b) query)) blocks))
            (refs (cl-remove-if-not
                   (lambda (b)
                     (string-match-p (concat "<<" (regexp-quote query) ">>")
                                     (nth 4 b)))
                   blocks)))
        (if (null defs)
            (custom-configctl--fail "unknown ID or noweb ref: %s" query)
          (dolist (blk defs)
            (princ (format "定义 :noweb-ref %s  行 %d-%d\n"
                           query
                           (custom-configctl--line-at (car blk))
                           (custom-configctl--line-at (cadr blk)))))
          (dolist (blk refs)
            (princ (format "组装引用  行 %d-%d\n"
                           (custom-configctl--line-at (car blk))
                           (custom-configctl--line-at (cadr blk))))))))))

;;; tangle — 拼合 emacs.org -> main.el

(defun custom-configctl-tangle ()
  "拼合 emacs.org 到仓库 main.el（真实产物，gitignore）。"
  (let ((org-confirm-babel-evaluate nil))
    (org-babel-tangle-file custom-configctl-org-file
                           custom-configctl-main-file "emacs-lisp")
    (princ (format "OK: tangled emacs.org -> %s\n" custom-configctl-main-file))))

;;; check — 轻量原则检查

(defun custom-configctl--check-structure ()
  (with-current-buffer (custom-configctl--org-buffer)
    (goto-char (point-min))
    (unless (re-search-forward
             "^#\\+PROPERTY: header-args:emacs-lisp :tangle main\\.el :lexical yes :mkdirp yes :noweb tangle$"
             nil t)
      (custom-configctl--fail "global emacs-lisp header contract changed"))
    (let ((ids (make-hash-table :test #'equal))
          (ordered nil))
      (dolist (item (custom-configctl--headlines))
        (let ((id (plist-get item :id)))
          (when (gethash id ids)
            (custom-configctl--fail "duplicate CUSTOM_ID: %s" id))
          (puthash id t ids)
          (when (member id custom-configctl-required-order)
            (push id ordered))))
      (setq ordered (nreverse ordered))
      (unless (equal ordered custom-configctl-required-order)
        (custom-configctl--fail "domain order changed: %S" ordered)))
    (goto-char (point-min))
    (when (re-search-forward
           "\\(?:require\\|provide\\)[[:space:]]+'custom-\\|add-to-list[[:space:]]+'load-path\\|:tangle[[:space:]]+lisp/"
           nil t)
      (custom-configctl--fail "legacy multi-file architecture reference at line %d"
                               (line-number-at-pos)))
    (let ((definitions (make-hash-table :test #'equal))
          (uses (make-hash-table :test #'equal))
          (tree (org-element-parse-buffer))
          (blocks 0))
      (org-element-map tree 'src-block
        (lambda (block)
          (when (custom-configctl--block-p block)
            (cl-incf blocks)
            (pcase-let* ((body (org-element-property :value block))
                         (`(,ref ,tangle ,owner ,kind)
                          (custom-configctl--block-header block)))
              (when ref
                (let ((prev (gethash ref definitions)))
                  (if prev
                      (unless (equal (nth 0 prev) owner)
                        (custom-configctl--fail
                         "noweb ref %s defined across sections: %s / %s"
                         ref (nth 0 prev) owner))
                    (puthash ref (list owner kind tangle) definitions))))
              (let ((start 0))
                (while (string-match "<<\\([^>\n()]+\\)\\(?:([^>\n()]*)\\)?>>" body start)
                  (puthash (match-string 1 body)
                           (1+ (gethash (match-string 1 body) uses 0)) uses)
                  (setq start (match-end 0))))))))
      (maphash (lambda (ref entry)
                 (pcase-let ((`(,owner ,kind ,tangle) entry))
                   (cond
                    ((eq kind 'noweb-ref)
                     (unless (equal tangle "no")
                       (custom-configctl--fail "%s must use :tangle no" ref))
                     (unless (= (gethash ref uses 0) 1)
                       (custom-configctl--fail
                        "noweb ref %s must be assembled exactly once (found %d)"
                        ref (gethash ref uses 0))))
                    ((and (eq kind 'name) (> (gethash ref uses 0) 0)
                          (not (equal tangle "no")))
                     (custom-configctl--fail
                      "named data block %s is referenced and must use :tangle no"
                      ref)))))
               definitions)
      (maphash (lambda (ref _count)
                 (unless (gethash ref definitions)
                   (custom-configctl--fail "undefined noweb ref: %s" ref)))
               uses)
      (list blocks (hash-table-count definitions)))))

(defun custom-configctl--audit-elisp (file)
  (with-temp-buffer
    (insert-file-contents file)
    (emacs-lisp-mode)
    (check-parens)
    (goto-char (point-min))
    (let ((definitions (make-hash-table :test #'eq))
          (forms 0))
      (condition-case err
          (while (< (point) (point-max))
            (let ((form (read (current-buffer))))
              (cl-incf forms)
              (when (and (consp form)
                         (memq (car form)
                               '(defun defmacro defsubst defvar defvar-local
                                 defconst defcustom defface)))
                (let ((name (cadr form)))
                  (when (gethash name definitions)
                    (custom-configctl--fail "duplicate definition: %s" name))
                  (puthash name t definitions)))))
        (end-of-file nil)
        (error
         (custom-configctl--fail "cannot read tangled elisp: %s"
                                  (error-message-string err))))
      (list forms (hash-table-count definitions)))))

(defun custom-configctl-check ()
  "结构检查 + 隔离 tangle + 括号/重复定义检查，不写真实 main.el。"
  (let ((org-confirm-babel-evaluate nil))
    (pcase-let* ((`(,blocks ,refs) (custom-configctl--check-structure))
                 (runtime (make-temp-file "custom-configctl-check-" t))
                 (org-copy (expand-file-name "emacs.org" runtime))
                 (target (expand-file-name "main.el" runtime)))
      (unwind-protect
          (progn
            (copy-file custom-configctl-org-file org-copy t)
            (org-babel-tangle-file org-copy target "emacs-lisp")
            (pcase-let* ((`(,forms ,definitions)
                          (custom-configctl--audit-elisp target)))
              (princ (format "OK: %d source blocks, %d noweb refs, %d forms, %d definitions\n"
                             blocks refs forms definitions))))
        (delete-directory runtime t)))))

(defun custom-configctl-usage ()
  (princ "Usage: scripts/configctl COMMAND [ARG]\n\n")
  (princ "  map            列出 CUSTOM_ID、行号、代码量与 noweb ref\n")
  (princ "  show ID        提取一个功能子树全文\n")
  (princ "  locate ID|REF  定位块行号区间（CUSTOM_ID）或 noweb ref 定义/组装位置\n")
  (princ "  tangle         拼合 emacs.org -> main.el\n")
  (princ "  check          轻量原则检查（域顺序/noweb/单产物/括号/重复定义）\n"))

(let ((status 0))
  (condition-case err
      (pcase command-line-args-left
        (`("map") (custom-configctl-map))
        (`("show" ,query) (custom-configctl-show query))
        (`("locate" ,query) (custom-configctl-locate query))
        (`("tangle") (custom-configctl-tangle))
        (`("check") (custom-configctl-check))
        ((or 'nil `("help") `("--help") `("-h")) (custom-configctl-usage))
        (_ (custom-configctl-usage)
           (custom-configctl--fail "invalid arguments: %S"
                                    command-line-args-left)))
    (error
     (setq status 1)
     (princ (format "ERROR: %s\n" (error-message-string err))
            'external-debugging-output)))
  (when-let* ((status-file (getenv "LITERAL_CONFIGCTL_STATUS_FILE")))
    (with-temp-file status-file
      (insert (number-to-string status))))
  (kill-emacs status))

;;; configctl.el ends here
