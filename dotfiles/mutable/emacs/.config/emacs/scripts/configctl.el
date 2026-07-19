;;; configctl.el --- Maintain literal-config without reading it all -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'org)
(require 'ob-tangle)
(require 'subr-x)

(defconst literal-configctl-root
  (file-name-directory
   (directory-file-name (file-name-directory (or load-file-name buffer-file-name)))))

(defconst literal-configctl-org-file
  (expand-file-name "emacs.org" literal-configctl-root))

(defconst literal-configctl-required-order
  '("startup" "appearance" "editing" "programming" "projects"
    "org-knowledge" "keys-completion" "system-tools"))

(defconst literal-configctl-i18n-data-files
  '(("which-key-zh.el"
     literal:which-key-description-spec
     literal:which-key-major-mode-description-spec
     literal:which-key-regexp-replacements)
    ("context-menu-zh.el"
     literal:context-menu-label-translations)
    ("help-zh.el"
     literal:help-introduction))
  "External data files and their required `setq' targets.")

(defun literal-configctl--fail (format-string &rest args)
  (error "configctl: %s" (apply #'format format-string args)))

(defun literal-configctl--org-buffer ()
  (let ((buffer (find-file-noselect literal-configctl-org-file)))
    (with-current-buffer buffer
      (org-mode))
    buffer))

(defun literal-configctl--headlines ()
  (with-current-buffer (literal-configctl--org-buffer)
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

(defun literal-configctl--source-info (begin end)
  (save-restriction
    (narrow-to-region begin end)
    (let ((tree (org-element-parse-buffer))
          (blocks 0)
          (code-lines 0)
          refs)
      (org-element-map tree 'src-block
        (lambda (block)
          (when (string= (org-element-property :language block) "emacs-lisp")
            (cl-incf blocks)
            (cl-incf code-lines
                     (length (split-string
                              (org-element-property :value block) "\n" t)))
            (when-let* ((ref (cdr (assq :noweb-ref
                                         (org-babel-parse-header-arguments
                                          (or (org-element-property :parameters block) ""))))))
              (push ref refs)))))
      (list blocks code-lines (nreverse refs)))))

(defun literal-configctl-map ()
  (with-current-buffer (literal-configctl--org-buffer)
    (princ "ID                       LINE  CODE  TITLE / NOWEB\n")
    (princ "------------------------ ----- -----  ------------------------------\n")
    (dolist (item (literal-configctl--headlines))
      (pcase-let* ((`(,blocks ,code-lines ,refs)
                    (literal-configctl--source-info
                     (plist-get item :begin) (plist-get item :end)))
                   (line (line-number-at-pos (plist-get item :begin))))
        (when (> blocks 0)
          (princ (format "%-24s %5d %5d  %s%s\n"
                         (plist-get item :id) line code-lines
                         (plist-get item :title)
                         (if refs
                             (format " [%s]" (string-join refs ", "))
                           ""))))))))

(defun literal-configctl--find-headline (query)
  (let* ((items (literal-configctl--headlines))
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
            ('nil (literal-configctl--fail "unknown feature: %s" query))
            (_ (literal-configctl--fail
                "ambiguous feature %s: %s" query
                (string-join (mapcar (lambda (item) (plist-get item :id)) matches)
                             ", "))))))))

(defun literal-configctl-show (query)
  (let ((item (literal-configctl--find-headline query)))
    (with-current-buffer (literal-configctl--org-buffer)
      (princ (buffer-substring-no-properties
              (plist-get item :begin) (plist-get item :end))))))

(defun literal-configctl-find (regexp)
  (with-current-buffer (literal-configctl--org-buffer)
    (goto-char (point-min))
    (let ((pattern (string-replace "|" "\\|" regexp))
          (case-fold-search t)
          (count 0)
          (last-line 0))
      (condition-case err
          (while (re-search-forward pattern nil t)
            (let* ((line (line-number-at-pos))
                   (text (string-trim
                          (buffer-substring-no-properties
                           (line-beginning-position) (line-end-position))))
                   (owner
                    (save-excursion
                      (when (org-before-first-heading-p)
                        (goto-char (point-min)))
                      (when (ignore-errors (org-back-to-heading t) t)
                        (let ((title (org-get-heading t t t t))
                              id
                              (continue t))
                          (while continue
                            (setq id (org-entry-get nil "CUSTOM_ID"))
                            (setq continue
                                  (and (not id) (org-up-heading-safe))))
                          (list (or id "-") title))))))
              (unless (= line last-line)
                (setq last-line line)
                (cl-incf count)
                (princ (format "%5d  %-22s  %-28s  %s\n"
                               line (or (car owner) "-")
                               (or (cadr owner) "file header") text)))))
        (invalid-regexp
         (literal-configctl--fail "invalid regexp %s: %s" regexp
                                  (error-message-string err))))
      (when (= count 0)
        (literal-configctl--fail "no match: %s" regexp)))))

(defun literal-configctl--check-structure ()
  (with-current-buffer (literal-configctl--org-buffer)
    (goto-char (point-min))
    (unless (re-search-forward
             "^#\\+PROPERTY: header-args:emacs-lisp :tangle main\\.el :lexical yes :mkdirp yes :noweb tangle$"
             nil t)
      (literal-configctl--fail "global emacs-lisp header contract changed"))
    (let ((ids (make-hash-table :test #'equal))
          (ordered nil))
      (dolist (item (literal-configctl--headlines))
        (let ((id (plist-get item :id)))
          (when (gethash id ids)
            (literal-configctl--fail "duplicate CUSTOM_ID: %s" id))
          (puthash id t ids)
          (when (member id literal-configctl-required-order)
            (push id ordered))))
      (setq ordered (nreverse ordered))
      (unless (equal ordered literal-configctl-required-order)
        (literal-configctl--fail "domain order changed: %S" ordered)))
    (goto-char (point-min))
    (when (re-search-forward
           "\\(?:require\\|provide\\)[[:space:]]+'literal-\\|add-to-list[[:space:]]+'load-path\\|:tangle[[:space:]]+lisp/"
           nil t)
      (literal-configctl--fail "legacy multi-file architecture reference at line %d"
                               (line-number-at-pos)))
    (let ((definitions (make-hash-table :test #'equal))
          (uses (make-hash-table :test #'equal))
          (tree (org-element-parse-buffer))
          (blocks 0))
      (org-element-map tree 'src-block
        (lambda (block)
          (when (string= (org-element-property :language block) "emacs-lisp")
            (cl-incf blocks)
            (let* ((params (org-babel-parse-header-arguments
                            (or (org-element-property :parameters block) "")))
                   (ref (cdr (assq :noweb-ref params)))
                   (tangle (cdr (assq :tangle params)))
                   (body (org-element-property :value block)))
              (when ref
                (unless (equal tangle "no")
                  (literal-configctl--fail "%s must use :tangle no" ref))
                (when (gethash ref definitions)
                  (literal-configctl--fail "duplicate noweb definition: %s" ref))
                (puthash ref (org-element-property :begin block) definitions))
              (let ((start 0))
                (while (string-match "<<\\([^>\n()]+\\)\\(?:([^>\n]*)\\)?>>" body start)
                  (puthash (match-string 1 body)
                           (1+ (gethash (match-string 1 body) uses 0)) uses)
                  (setq start (match-end 0))))))))
      (maphash (lambda (ref _position)
                 (unless (= (gethash ref uses 0) 1)
                   (literal-configctl--fail
                    "noweb ref %s must be assembled exactly once (found %d)"
                    ref (gethash ref uses 0))))
               definitions)
      (maphash (lambda (ref _count)
                 (unless (gethash ref definitions)
                   (literal-configctl--fail "undefined noweb ref: %s" ref)))
               uses)
      (list blocks (hash-table-count definitions)))))

(defun literal-configctl--audit-elisp (file)
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
                    (literal-configctl--fail "duplicate definition: %s" name))
                  (puthash name t definitions)))))
        (end-of-file nil)
        (error
         (literal-configctl--fail "cannot read tangled elisp: %s"
                                  (error-message-string err))))
      (list forms (hash-table-count definitions)))))

(defun literal-configctl--audit-i18n-data ()
  "Validate that external localization files contain only expected literal data."
  (let ((assignments 0)
        (data-directory (expand-file-name "data/" literal-configctl-root)))
    (dolist (specification literal-configctl-i18n-data-files)
      (let* ((name (car specification))
             (symbols (cdr specification))
             (file (expand-file-name name data-directory))
             found)
        (unless (file-readable-p file)
          (literal-configctl--fail "missing or unreadable i18n data file: %s" file))
        (with-temp-buffer
          (insert-file-contents file)
          (emacs-lisp-mode)
          (condition-case err
              (check-parens)
            (error
             (literal-configctl--fail "unbalanced i18n data file %s: %s"
                                      name (error-message-string err))))
          (goto-char (point-min))
          (while (progn
                   (skip-chars-forward " \t\n")
                   (< (point) (point-max)))
            (let ((form (condition-case err
                            (read (current-buffer))
                          (error
                           (literal-configctl--fail
                            "cannot read i18n data file %s: %s"
                            name (error-message-string err))))))
              (unless (and (listp form)
                           (eq (car form) 'setq)
                           (= (length form) 3)
                           (memq (cadr form) symbols)
                           (let ((value (caddr form)))
                             (and (listp value)
                                  (eq (car value) 'quote)
                                  (= (length value) 2)
                                  (listp (cadr value)))))
                (literal-configctl--fail
                 "i18n data file %s must contain only literal setq assignments" name))
              (when (memq (cadr form) found)
                (literal-configctl--fail
                 "duplicate i18n assignment %s in %s" (cadr form) name))
              (push (cadr form) found)
              (cl-incf assignments)))
        (unless (equal (nreverse found) symbols)
          (literal-configctl--fail
           "i18n assignments in %s must be exactly %S (found %S)"
           name symbols found)))))
    assignments))

(defun literal-configctl--assert (condition format-string &rest args)
  (unless condition
    (literal-configctl--fail "smoke assertion failed: %s"
                             (apply #'format format-string args))))

(defun literal-configctl--smoke-test ()
  (literal-configctl--assert (featurep 'main) "main feature missing")
  (dolist (function '(literal/add-frame-created-hook
                      literal/add-server-ready-hook
                      literal/call-process
                      literal/color-scheme-init
                      literal/completion-setup-display
                      literal/dashboard-open-for-client-frame
                      literal/display-or-focus
                      literal/binding-help-sections
                      literal/help--extract-dashboard-bindings
                      ;; Phase 2.3:统一浏览入口替代 knowledge-viz + agenote-browse
                      literal/knowledge-browse-human
                      literal/knowledge-browse-agenote
                      literal/knowledge-viz-open-browser
                      literal/open-terminal
                      literal/tabs-next))
    (literal-configctl--assert (fboundp function) "missing function %s" function))
  (dolist (binding '(("C-S-c" . literal/copy-dwim)
                     ("C-<tab>" . literal/tabs-next)
                     ("C-c o k s" . literal/knowledge-search)
                     ;; Phase 2.3:统一浏览入口的绑定
                     ("C-c o k v" . literal/knowledge-browse-human)
                     ("C-c o k b" . literal/knowledge-browse-agenote)
                     ("C-c o k V" . literal/knowledge-viz-open-browser)
                     ;; Phase 7.2:Agent Shell + 编辑前缀声明式入口
                     ("C-c a a" . agent-shell)
                     ("C-c a A" . agent-shell-toggle)
                     ("C-c e l" . mc/edit-lines)
                     ("C-c e n" . mc/mark-next-like-this)
                     ("C-c e ." . goto-last-change)
                     ("C-c e ," . goto-last-change-reverse)
                     ("C-c l d" . literal/code-goto-definition)))
    (literal-configctl--assert
     (eq (key-binding (kbd (car binding))) (cdr binding))
     "%s is not bound to %s" (car binding) (cdr binding)))
  (with-temp-buffer
    (emacs-lisp-mode)
    (literal-configctl--assert (featurep 'eglot)
                               "prog-mode-hook did not load eglot"))
  (literal-configctl--assert
   (not (memq #'literal--eglot-setup-once prog-mode-hook))
   "one-shot eglot hook was not removed")
  (require 'org-capture)
  ;; Phase 2.2 统一 Capture 入口:四类生命周期
  ;;   ki=inbox / kt=任务 / kd=带日期任务 / ke=日程 / kr=roam
  ;;   kn/km/ka=经验卡片(note/mistake/ascended,对齐 agenote-base entry-types)
  (dolist (key '("ki" "kt" "kd" "ke" "kr" "kn" "km" "ka"))
    (literal-configctl--assert (assoc key org-capture-templates)
                               "missing Org capture template %s" key))
  ;; P0 #2 fix: Flymake chain intact (eglot-stay-out-of does not contain
  ;; flymake; flymake public API reachable; M-g n bound to flymake).
  (require 'flymake)
  (literal-configctl--assert
   (boundp 'flymake-after-diagnostics-hook)
   "flymake-after-diagnostics-hook missing")
  (literal-configctl--assert
   (fboundp 'flymake-goto-next-error)
   "flymake-goto-next-error not bound")
  (literal-configctl--assert
   (eq (key-binding (kbd "M-g n")) 'flymake-goto-next-error)
   "M-g n is not bound to flymake-goto-next-error")
  (require 'which-key)
  (literal-configctl--assert (null literal--pending-wk-descs)
                             "pending Which-key descriptions were not flushed")
  (literal-configctl--assert (consp literal:which-key-description-spec)
                             "Which-key translation data missing")
  (literal-configctl--assert
   (equal (cdr (assoc "Undo" literal:context-menu-label-translations)) "撤销")
   "context-menu translation data missing Undo -> 撤销")
  ;; Phase 6: 帮助/Dashboard 数据已下沉到 binding spec。
  ;; help-zh.el 只保留帮助页引言文字（literal:help-introduction）。
  (literal-configctl--assert (consp literal:binding-spec)
                             "binding spec missing — no literal/bind declarations?")
  (literal-configctl--assert (consp (literal/binding-help-sections))
                             "binding spec yielded no help sections")
  ;; P0 #4 (partial): the C-c a / C-c o / C-x p prefixes themselves must
  ;; resolve to keymaps. Individual leaf bindings are validated by
  ;; `audit-keys' (not load). These prefixes exist today and must keep
  ;; resolving across all later commits.
  (dolist (prefix '("C-c a" "C-c o" "C-x p"))
    (literal-configctl--assert
     (keymapp (key-binding (kbd prefix)))
     "%s prefix does not resolve to a keymap" prefix))
  t)

(defun literal-configctl--tangle-and-audit ()
  (let* ((runtime (make-temp-file "literal-configctl-runtime-" t))
         (org-copy (expand-file-name "emacs.org" runtime))
         (target (expand-file-name "main.el" runtime))
         (user-emacs-directory (file-name-as-directory runtime))
         (org-id-locations-file (expand-file-name "org-id-locations" runtime))
         (org-persist-directory (expand-file-name "org-persist/" runtime))
         (org-confirm-babel-evaluate nil))
    (unwind-protect
        (progn
          (unless (boundp 'byte-compile-root-dir)
            (defvar byte-compile-root-dir nil))
          (with-temp-file org-id-locations-file (prin1 nil (current-buffer)))
          (make-directory org-persist-directory t)
          (copy-file literal-configctl-org-file org-copy t)
          (copy-directory (expand-file-name "data/" literal-configctl-root)
                          (expand-file-name "data/" runtime)
                          nil nil t)
          (org-babel-tangle-file org-copy target "emacs-lisp")
          (list runtime target (literal-configctl--audit-elisp target)))
      ;; The caller removes RUNTIME after an optional load.
      )))

(defun literal-configctl--bootstrap-guix-autoloads ()
  "Load per-package autoloads the way Guix `site-start' would.

`scripts/configctl' starts Emacs with `-Q', which skips `site-start' and
leaves the Guix profile's `*-autoloads.el' files unprocessed: `load-path' is
populated but package autoloads (e.g. `rainbow-delimiters-mode') are never
defined, so any config that relies on them breaks in the isolated runtime.
Mirror `site-start' by delegating to `guix-emacs-autoload-packages' when the
Guix helper is on `load-path', and fall back to loading each
*-autoloads file ourselves so the smoke test sees what a live daemon sees."
  (when (require 'guix-emacs nil t)
    (guix-emacs-autoload-packages 'no-reload))
  (dolist (dir load-path)
    (when (file-directory-p dir)
      (dolist (file (directory-files dir t "-autoloads\\.el\\'" t))
        (load (file-name-sans-extension file) t t)))))

(defun literal-configctl-load ()
  (pcase-let* ((`(,runtime ,target) (literal-configctl-check t))
               (user-emacs-directory (file-name-as-directory runtime))
               (default-directory literal-configctl-root))
    (unwind-protect
        (progn
          ;; Phase 3 迁移自 projectile:project.el 用 project-list-file 存已知项目
          (setq-default project-list-file
                        (expand-file-name "var/project-list.eld" runtime))
          (literal-configctl--bootstrap-guix-autoloads)
          (load target nil t)
          (literal-configctl--smoke-test)
          (setq kill-emacs-hook nil)
          (princ "OK: isolated load and runtime smoke assertions passed\n"))
      (delete-directory runtime t))))

(defun literal-configctl-usage ()
  (princ "Usage: scripts/configctl COMMAND [ARG]\n\n")
  (princ "  map                 list stable feature IDs and their source footprint\n")
  (princ "  show ID             print one feature subtree\n")
  (princ "  find REGEXP         locate matches with owning feature ID\n")
  (princ "  check               audit structure, noweb graph, tangle and definitions\n")
  (princ "  check-strict        also enforce domain/private-api audit rules\n")
  (princ "  load                check and batch-load in an isolated runtime\n")
  (princ "  test                run ERT tests against an isolated tangle\n")
  (princ "  audit-keys          cross-check bindings vs help/dashboard data\n")
  (princ "  audit-private-api   report third-party private symbol calls\n")
  (princ "  audit-agenote-domain  verify agenote CLI calls carry --domain\n")
  (princ "  audit-packages      cross-check Guix manifest vs config entry points\n"))


;;; ---------------------------------------------------------------------------
;;; Audit infrastructure
;; ---------------------------------------------------------------------------
;;
;; The audit subcommands are informational: they print structured reports and
;; return a non-zero status (via `literal-configctl--fail' at the end) when
;; violations exist. They deliberately do NOT run during a default `check` so
;; that the existing baseline stays green; opt in via `check --strict` or by
;; invoking each audit directly. Violations are collected as `(CATEGORY . MSG)`
;; pairs and printed once at the end so a single run surfaces every problem
;; instead of bailing on the first.

(defconst literal-configctl-compatibility-ids '("compatibility")
  "CUSTOM_IDs whose source blocks are allowed to touch third-party private APIs.")

(defconst literal-configctl-agenote-adapter-ids
  '("bootstrap" "process-helper")
  "CUSTOM_IDs that define the agenote executable path constant and the
`literal/agenote-call' adapter. These blocks legitimately reference the
agenote executable without passing --domain at every site (the adapter itself
enforces it), so `audit-agenote-domain' skips them.")

(defvar literal-configctl--audit-violations nil
  "Accumulated audit violations as a list of (CATEGORY . MESSAGE).")

(defun literal-configctl--violation (category message)
  "Record an audit violation under CATEGORY with MESSAGE."
  (setq literal-configctl--audit-violations
        (cons (cons category message)
              literal-configctl--audit-violations)))

(defun literal-configctl--report-audit (title)
  "Print TITLE followed by all accumulated violations, then return count.
Resets the violation list so the next audit starts clean."
  (princ (format "=== %s ===\n" title))
  (let ((count (length literal-configctl--audit-violations)))
    (if (zerop count)
        (princ "OK: no violations\n")
      (princ (format "%d violation(s):\n" count))
      (dolist (violation (nreverse literal-configctl--audit-violations))
        (princ (format "  [%s] %s\n"
                       (car violation) (cdr violation)))))
    (setq literal-configctl--audit-violations nil)
    count))

(defun literal-configctl--src-blocks ()
  "Return all emacs-lisp src blocks under their owning CUSTOM_ID.
Each element is (CUSTOM_ID BEGIN BODY-START BODY-END BODY HEADER-ARGS).
CUSTOM_ID is the nearest enclosing headline's stable id, or nil for blocks
before any CUSTOM_ID headline."
  (with-current-buffer (literal-configctl--org-buffer)
    (save-excursion
      (goto-char (point-min))
      ;; Build (begin . id) entries: whenever a CUSTOM_ID line is found, walk
      ;; backwards to the nearest headline start.
      (let ((id-marker-alist nil)
            (blocks nil)
            (last-headline-pos 1))
        (while (re-search-forward "^\\(:CUSTOM_ID:\\)[[:space:]]+\\([^:\n\r]+\\)[ \t]*$"
                                  nil t)
          (let ((id (string-trim (match-string 2))))
            (save-excursion
              (forward-line 0)
              ;; Walk back to the nearest * headline.
              (re-search-backward "^\\*+ " nil t)
              (push (cons (point) id) id-marker-alist))))
        (setq id-marker-alist (nreverse id-marker-alist))
        (goto-char (point-min))
        (while (re-search-forward
                "^#\\+begin_src\\s-+emacs-lisp\\( .*\\)?$" nil t)
          (let* ((begin (line-beginning-position))
                 (header-args
                  (buffer-substring-no-properties
                   (line-beginning-position) (line-end-position)))
                 (body-start (progn (forward-line 1) (point)))
                 (body-end
                  (progn
                    (if (re-search-forward "^#\\+end_src" nil t)
                        (line-beginning-position)
                      (point-max))))
                 ;; Owner is the last CUSTOM_ID headline that begins before BLOCK.
                 (owner
                  (let ((found nil))
                    (dolist (entry id-marker-alist)
                      (when (< (car entry) begin)
                        (setq found (cdr entry))))
                    found)))
            (push (list owner begin body-start body-end
                        (buffer-substring-no-properties body-start body-end)
                        header-args)
                  blocks)
            ;; Leave point at body-end so the next re-search-forward continues.
            (goto-char body-end)))
        (nreverse blocks)))))

(defun literal-configctl--binding-specs ()
  "Parse `literal/set-key' and `keymap-global-set' / `keymap-set' forms.
Returns a list of plists: (:key :command :desc :owner :begin).
KEY is the raw quoted string; COMMAND is the symbol-name string;
DESC is the which-key description for literal/set-key or nil."
  (let (specs)
    (dolist (block (literal-configctl--src-blocks))
      (pcase-let* ((`(,owner ,_begin ,_body-start ,_body-end ,body ,_hdr)
                    block))
        (with-temp-buffer
          (insert body)
          (goto-char (point-min))
          ;; literal/set-key "KEY" #'CMD "DESC"
          ;; Regex explanation: #?' matches #' or '  — the function quote.
          ;; The trailing \"\\([^\")]*\\)\" was buggy because it excluded all \"
          ;; chars, preventing the description string (which contains \") from
          ;; being matched. Fix: allow \\(\"[^\"]*\"\\)* inside the tail so
          ;; the description string passes through, then require the literal ).
          (while (re-search-forward
                  "(literal/set-key[[:space:]]+\"\\([^\"]+\\)\"[[:space:]]+#?'\\([^ )]+\\)\\(\\(?:[^)\"]*\\|\"[^\"]*\"\\)*\\))"
                  nil t)
            (let ((key (match-string 1))
                  (cmd (match-string 2))
                  (rest (match-string 3)))
              (let ((desc
                     (when (string-match
                            "\"\\([^\"]+\\)\"" rest)
                       (match-string 1 rest))))
                (push (list :key key :command cmd :desc desc
                            :owner owner) specs))))
          ;; keymap-global-set "KEY" #'CMD  (also keymap-set for prefix maps)
          (goto-char (point-min))
          (while (re-search-forward
                  "(keymap-global-set[[:space:]]+\"\\([^\"]+\\)\"[[:space:]]+#?'\\([^ )]+\\))"
                  nil t)
            (let ((key (match-string 1))
                  (cmd (match-string 2)))
              (push (list :key key :command cmd :desc nil
                          :owner owner) specs)))
          (goto-char (point-min))
          (while (re-search-forward
                  "(keymap-set[[:space:]]+\\S-+[[:space:]]+\"\\([^\"]+\\)\"[[:space:]]+#?'\\([^ )]+\\))"
                  nil t)
            (let ((key (match-string 1))
                  (cmd (match-string 2)))
              (push (list :key key :command cmd :desc nil
                          :owner owner) specs)))
          ;; global-set-key (kbd "KEY") #'CMD  — legacy form still used for
          ;; <f1> ? and C-c h ? (literal/show-help). Phase 6: include them so
          ;; audit-keys treats F1 ? / C-c h ? as first-class bindings.
          (goto-char (point-min))
          (while (re-search-forward
                  "(global-set-key[[:space:]]+(kbd[[:space:]]+\"\\([^\"]+\\)\")[[:space:]]+#?'\\([^ )]+\\))"
                  nil t)
            (let ((key (match-string 1))
                  (cmd (match-string 2)))
              (push (list :key key :command cmd :desc nil
                          :owner owner) specs))))))
    specs))

(defun literal-configctl--binding-spec-entries ()
  "Parse `literal/bind' declarations in emacs.org source blocks.
Return a list of plists: (:key :target :desc :group :prefix :dashboard).
Only literal/bind is first-party SoT — literal/bind-local is local-mode
and literal/declare-binding-prefix delegates to literal/bind internally."
  (let (entries)
    (dolist (block (literal-configctl--src-blocks))
      (pcase-let* ((`(,_owner ,_begin ,_body-start ,_body-end ,body ,_hdr) block))
        (with-temp-buffer
          (insert body)
          (goto-char (point-min))
          ;; Form: (literal/bind \"KEY\" [#'CMD | nil] [\"DESC\"] [\"GROUP\"] [:prefix t :dashboard t]...)
          ;; sexp parsing is more robust than regex: read from `(` to matching `)`.
          (while (re-search-forward "(literal/bind[[:space:]]+" nil t)
            (let ((start (match-beginning 0)))
              (save-excursion
                (goto-char start)
                (condition-case nil
                    (let* ((sexp (read (current-buffer)))
                           (key (nth 1 sexp))
                           (target (nth 2 sexp))
                           (desc (nth 3 sexp))
                           (group (nth 4 sexp))
                           (rest (nthcdr 5 sexp)))
                      (when (stringp key)
                        (push (list :key key
                                    :target (when target (format "%S" target))
                                    :desc (when (stringp desc) desc)
                                    :group (when (stringp group) group)
                                    :prefix (and (plist-member rest :prefix)
                                                 (eq (plist-get rest :prefix) t))
                                    :dashboard (and (plist-member rest :dashboard)
                                                    (eq (plist-get rest :dashboard) t)))
                              entries)))
                  (error nil))))))))
    (nreverse entries)))

(defun literal-configctl--binding-help-sections ()
  "Mirror `literal/binding-help-sections' on parsed binding spec entries.
Return a list of (GROUP (key . desc) ...) preserving source order."
  (let (order table)
    (dolist (entry (literal-configctl--binding-spec-entries))
      (let ((group (plist-get entry :group)))
        (when group
          (unless (member group order)
            (setq order (append order (list group))))
          (push (cons (plist-get entry :key) (plist-get entry :desc))
                (alist-get group table nil nil #'equal)))))
    (mapcar
     (lambda (group)
       (cons group (nreverse (alist-get group table nil nil #'equal))))
     order)))

(defun literal-configctl--binding-dashboard-bindings ()
  "Mirror `literal/binding-dashboard-bindings' on parsed entries.
Return an alist of (key . desc) for entries flagged :dashboard t."
  (delq nil
        (mapcar
         (lambda (entry)
           (when (plist-get entry :dashboard)
             (cons (plist-get entry :key) (plist-get entry :desc))))
         (literal-configctl--binding-spec-entries))))

(defun literal-configctl--dashboard-hardcoded-hints ()
  "Extract icon-hint binding strings embedded in dashboard generators.
The card sections use `(TITLE' (ICON . \"C-x Y\") ...) patterns; we capture
the right-hand binding strings so they can be cross-checked against the
actual keymap."
  (let (hints
        (blocks (cl-remove-if-not
                 (lambda (b) (equal (car b) "dashboard"))
                 (literal-configctl--src-blocks))))
    (dolist (block blocks)
      (let ((body (nth 4 block)))
        (with-temp-buffer
          (insert body)
          (goto-char (point-min))
          (while (re-search-forward "\"[^\"]*\"[[:space:]]+'(\"[^\"]*\"[[:space:]]+\\.\"\\([^\"]+\\)\")"
                                    nil t)
            (let ((hint (match-string 1)))
              ;; Filter out obvious non-bindings (icons only).
              (when (string-match-p "\\`C-\\|\\`M-\\|\\`<f[0-9]+\\|\\`S-\\|\\`F1" hint)
                (push hint hints)))))))
    (delete-dups (nreverse hints))))

(defun literal-configctl--prefix-group-p (key-string)
  "Return non-nil if KEY-STRING is a prefix-group placeholder.
Matches forms like \"C-c a g ...\" or \"C-c o b ...\" where the trailing
\"...\" indicates the entry describes a prefix group rather than one
specific binding."
  (string-match-p "\\.\\.\\.?\\'" key-string))

(defun literal-configctl--prefix-of (key-string)
  "Return the prefix portion of KEY-STRING (everything before the last token).
\"C-c a g t\" → \"C-c a g\". \"C-c a g ...\" → \"C-c a g\".
Single-token strings return nil."
  (let* ((trimmed (string-trim (string-trim-right key-string "\\.\\.\\.?"))))
    (if (string-match "\\(.*\\) [^ ]+\\'" trimmed)
        (match-string 1 trimmed)
      nil)))

(defun literal-configctl--has-child-binding-p (prefix bound-keys)
  "Return non-nil if PREFIX has at least one child binding in BOUND-KEYS.
\"C-c a g\" matches any of \"C-c a g t\", \"C-c a g s\", etc."
  (let ((prefix-re (concat "\\`" (regexp-quote prefix) " ")))
    (cl-some (lambda (k) (string-match-p prefix-re k)) bound-keys)))

(defun literal-configctl--audit-keys ()
  "Cross-check binding spec vs actual keymap and dashboard hardcoded hints.
Phase 6: binding spec (`literal/bind') 是键位、Which-key、帮助与 Dashboard
摘要的唯一真相源。本审计确保:
  - binding spec 声明的 curated key 在真实 keymap 中可解析。
  - dashboard generator 中硬编码的绑定串(非 spec 来源)在 keymap 中存在。
  - curated keymap 绑定在 binding spec 中有声明。

Only curated app-prefix bindings (C-c [a-z], C-x p/g/t, M-g, M-s, F1) are
checked — raw single-char bindings like C-j are set by key-helper and not part
of the help/dashboard single-source-of-truth."
  (let* ((specs (literal-configctl--binding-specs))
         (spec-entries (literal-configctl--binding-spec-entries))
         (bound-keys (delete-dups (mapcar (lambda (s) (plist-get s :key)) specs)))
         (spec-keys (delete-dups (mapcar (lambda (e) (plist-get e :key)) spec-entries)))
         (sections (literal-configctl--binding-help-sections))
         (dashboard (literal-configctl--binding-dashboard-bindings))
         (help-keys nil)
         (dashboard-keys (delq nil (mapcar
                                    (lambda (entry)
                                      (when (literal-configctl--curated-key-p (car entry))
                                        (car entry)))
                                    dashboard)))
         (hardcoded-hints (literal-configctl--dashboard-hardcoded-hints)))
    ;; Collect all curated keys mentioned in binding-spec-derived help-sections.
    (dolist (section sections)
      (dolist (binding (cdr section))
        (dolist (token (literal-configctl--help-key-tokens (car binding)))
          (when (literal-configctl--curated-key-p token)
            (push token help-keys)))))
    (setq help-keys (delete-dups (nreverse help-keys)))
    ;; (a) help/dashboard spec keys must resolve to real bindings.
    (dolist (key help-keys)
      (unless (or (member key bound-keys)
                  (member key spec-keys)
                  ;; 前缀组占位符(C-c X y ...):只要有任意子绑定即满足
                  (and (literal-configctl--prefix-group-p key)
                       (let ((prefix (literal-configctl--prefix-of key)))
                         (and prefix
                              (literal-configctl--has-child-binding-p prefix bound-keys))))
                  ;; 第三方包内部绑定(非 C-c [a-z] 开头)非本配置 SoT 范围
                  (not (string-match-p "\\`C-c [a-z]" key)))
        (literal-configctl--violation
         "help-no-binding"
         (format "%s declared in binding spec but no keymap-global-set/keymap-set/literal/bind matches"
                 key))))
    (dolist (key dashboard-keys)
      (unless (or (member key bound-keys)
                  (member key spec-keys)
                  ;; dashboard 单字母前缀(C-c l / C-c a 等):是前缀组名,
                  ;; 只要存在任意 C-c l * 子绑定即视为声明有效。
                  (and (string-match-p "\\`C-c [a-z]\\'" key)
                       (literal-configctl--has-child-binding-p key bound-keys))
                  ;; 多 token 前缀(C-x p / C-x g / C-x t)同理
                  (and (string-match-p "\\`C-x [a-z]\\'" key)
                       (literal-configctl--has-child-binding-p key bound-keys)))
        (literal-configctl--violation
         "dashboard-no-binding"
         (format "%s declared via :dashboard t in binding spec but no binding matches"
                 key))))
    (dolist (hint hardcoded-hints)
      (unless (member hint bound-keys)
        ;; Some hints are compound (e.g. "C-c c i / o"). Tokenize and re-check.
        (dolist (token (literal-configctl--help-key-tokens hint))
          (when (literal-configctl--curated-key-p token)
            (unless (member token bound-keys)
              (literal-configctl--violation
               "dashboard-hardcoded-no-binding"
               (format "%s (from dashboard generator icon-hint) has no matching binding"
                       token)))))))
    ;; (b) curated bindings must be declared in binding spec (informational).
    (dolist (spec specs)
      (let ((key (plist-get spec :key)))
        (when (and (literal-configctl--curated-key-p key)
                   (not (member key help-keys))
                   (not (member key dashboard-keys)))
          (literal-configctl--violation
           "binding-no-help"
           (format "%s bound to %s but no binding spec entry mentions it"
                   key (plist-get spec :command))))))
    (literal-configctl--report-audit "audit-keys")))

(defconst literal-configctl--curated-prefixes
  ;; Help/dashboard entries whose first token starts with one of these are
  ;; "curated" by the config (declared via literal/set-key / keymap-global-set).
  ;; Raw single-char bindings like C-j / C-h (set by key-helper) and editor-style
  ;; C-S-c / C-S-v are NOT curated by the help/dashboard single-source-of-truth,
  ;; so the audit ignores them — they don't appear in bound-keys' app-prefix set.
  '("C-c " "C-x p" "M-g " "M-s " "F1 " "C-x g" "C-x t"))

(defun literal-configctl--curated-key-p (key-string)
  "Return non-nil if KEY-STRING is a curated app-prefix binding.
Phase 6: only single-letter C-c prefixes (C-c [a-z] ...) are first-party
curated bindings. Third-party package internal bindings (C-c C-c, C-c C-t,
C-c digit, etc.) are NOT part of our single-source-of-truth — they are
defined inside package keymaps (agent-shell, telega, magit, ...) and the
audit must ignore them.

注意:`case-fold-search' 默认 t 会让 [a-z] 也匹配大写,导致 C-c C-c 被误判
为 curated。这里显式绑定 nil,确保 [a-z] 只匹配小写。"
  (let ((case-fold-search nil))
    (string-match-p "\\`C-c [a-z]\\|\\`C-x p\\|\\`C-x g\\|\\`C-x t\\|\\`M-g \\|\\`M-s \\|\\`F1 "
                    key-string)))

(defun literal-configctl--help-key-tokens (key-string)
  "Split a help/dashboard key display string into individual key tokens.
\"C-x 2 / 3 / 0 / 1 / o\" → (\"C-x 2\" \"C-x 3\" \"C-x 0\" \"C-x 1\" \"C-x o\").
\"C-c a a a\"            → (\"C-c a a a\").
\"C-c g # / @\"          → (\"C-c g #\" \"C-c g @\").
\"Markdown: C-c p\"      → (\"C-c p\").
Returns only tokens that look like complete bindings (start with C-/M-/S-/F1/<fN
followed by a key spec). Incomplete fragments (e.g. \"<up\" after a / split) are
dropped. Prefix descriptions like \"Markdown:\" are stripped."
  (let* (;; Strip prefix descriptions like "Markdown: " or "Wgrep: " so the
         ;; subsequent token parsing sees only the key spec.
         (cleaned (if (string-match "^[A-Za-z]+: \\(.*\\)" key-string)
                      (match-string 1 key-string)
                    key-string))
         (slash-split (split-string cleaned "[/]+"))
         (tokens nil))
    (dolist (branch slash-split)
      (let ((trimmed (string-trim branch)))
        ;; A branch is either a complete key (starts with a modifier) or a
        ;; suffix of the first branch (e.g. "3" continues "C-x 2" → "C-x 3").
        (cond
         ((string-match-p "\\`C-[a-zA-Z0-9_#@] \\|\\`C-[a-zA-Z0-9_]\\|\\`C-c [a-z A-Z0-9_]\\|\\`C-c [a-z] [#@] \\|\\`C-c [a-z] [a-zA-Z0-9_#@]\\|\\`M-[a-zA-Z0-9_]\\|\\`S-\\|\\`F1 \\|\\`<f[0-9]+" trimmed)
          (push trimmed tokens))
         ((and tokens
               (string-match-p "\\`[0-9a-zA-Z<>.,+_-#@]+\\'" trimmed))
          ;; Continue the previous token's prefix up to its last whitespace.
          (let ((prev (car tokens)))
            (let ((last-space (string-match " [^ ]+\\'" prev)))
              (if last-space
                  (push (concat (substring prev 0 last-space) " " trimmed) tokens)
                (push trimmed tokens))))))))
    (delete-dups (nreverse tokens))))

(defconst literal-configctl--own-namespaces
  ;; Project-internal symbol prefixes. Symbols beginning with any of these
  ;; (followed by `/') are first-party and excluded from the third-party
  ;; private-API audit. The full first-party set is also derived dynamically
  ;; from `defun' / `defvar' forms in emacs.org (see
  ;; `literal-configctl--first-party-definitions').
  '("literal" "custom" "literal-configctl"))

(defun literal-configctl--first-party-definitions ()
  "Return a hash table of all symbols defined in emacs.org source blocks.
Covers `defun', `defmacro', `defsubst', `defvar', `defvar-local',
`defconst', `defcustom', `defface'. A symbol found here is first-party even
when its prefix is not in `literal-configctl--own-namespaces'."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (block (literal-configctl--src-blocks))
      (let ((body (nth 4 block)))
        (with-temp-buffer
          (insert body)
          (goto-char (point-min))
          (while (re-search-forward
                  "(def\\(?:un\\|macro\\|subst\\|var\\(?:-local\\)?\\|const\\|custom\\|face\\)[[:space:]]+\\([a-zA-Z0-9_/:*-]+\\)"
                  nil t)
            (puthash (match-string 1) t table)))))
    table))

(defun literal-configctl--third-party-private-p (symbol first-party-table)
  "Return non-nil if SYMBOL is a third-party private API (sym--name).
First-party (defined in this config) symbols are looked up in
FIRST-PARTY-TABLE. Symbols whose namespace prefix is in
`literal-configctl--own-namespaces' are also considered first-party."
  (if (gethash symbol first-party-table)
      nil
    (let* ((slash (or (string-match "[/:]" symbol)
                      (string-match "--" symbol)))
           (prefix (if slash (substring symbol 0 slash) symbol)))
      (not (member prefix literal-configctl--own-namespaces)))))

(defun literal-configctl--private-api-defensive-p (match-beg)
  "Return non-nil if the symbol at MATCH-BEG is a defensive guard argument.
Matches the common forms (fboundp \\='sym), (boundp \\='sym), (functionp
\\='sym), (commandp \\='sym), #'sym, and quoted \\='sym used as a function
designator."
  (save-excursion
    (save-match-data
      (let ((preceding (buffer-substring-no-properties
                        (max (point-min) (- match-beg 14))
                        match-beg)))
        (or (string-match
             "\\(?:fboundp\\|boundp\\|functionp\\|commandp\\)[[:space:]]*'?$"
             preceding)
            (string-match "#'$" preceding)
            (string-match "[[:space:](]'$" preceding))))))

(defconst literal-configctl--private-api-call-rx
  "\\(?:[a-zA-Z0-9_/:*-]+\\)--[[:alnum:]_]+"
  "Matches a full Lisp symbol of the form prefix--name, where PREFIX may include
/, :, * (for some packages), and hyphens. The caller further filters to
third-party namespaces via `literal-configctl--third-party-private-p'.")

(defun literal-configctl--audit-private-api ()
  "Report direct calls to third-party private (symbol--name) APIs.
Allow list: blocks whose owning CUSTOM_ID is in
`literal-configctl-compatibility-ids', first-party namespaces, and defensive
\(fboundp/boundp) guards."
  (let ((first-party (literal-configctl--first-party-definitions)))
    (dolist (block (literal-configctl--src-blocks))
      (let ((owner (car block))
            (body (nth 4 block)))
          (when (not (member owner literal-configctl-compatibility-ids))
            (with-temp-buffer
              (insert body)
              (delay-mode-hooks (emacs-lisp-mode))
              (goto-char (point-min))
            (while (re-search-forward literal-configctl--private-api-call-rx nil t)
              (let ((symbol (match-string 0))
                    (match-beg (match-beginning 0)))
                (when (literal-configctl--third-party-private-p symbol first-party)
                  (unless (literal-configctl--private-api-defensive-p match-beg)
                    (let ((ssyntax (syntax-ppss)))
                      ;; Skip comments, strings, and character literals.
                      (unless (or (nth 4 ssyntax) (nth 3 ssyntax))
                        (literal-configctl--violation
                         "private-api-call"
                         (format "%s (%s, line %d) — move to compatibility block"
                                 symbol owner (line-number-at-pos))))))))))))))
  (literal-configctl--report-audit "audit-private-api"))

(defun literal-configctl--audit-agenote-domain ()
  "Verify every agenote CLI invocation explicitly passes --domain.
Skips `bootstrap' / `process-helper' (the executable constant and the
`literal/agenote-call' adapter live there; the adapter enforces --domain).
Other blocks must route through `literal/agenote-call' / `literal/agenote-call-async'
(which always pass --domain) and must not reference `literal:executable-agenote'
directly (the dedicated CLI executable constant). Bare `\"agenote\"' string
literals are NOT flagged — too ambiguous (path components, mode display names)."
  (dolist (block (literal-configctl--src-blocks))
    (let ((owner (car block))
          (body (nth 4 block)))
      ;; Skip the adapter itself and the bootstrap definition.
      (when (not (member owner literal-configctl-agenote-adapter-ids))
        (with-temp-buffer
          (insert body)
          (goto-char (point-min))
          (while (re-search-forward
                  "literal:executable-agenote"
                  nil t)
            (let ((line (line-number-at-pos))
                  (mbeg (match-beginning 0)))
              (save-excursion
                (goto-char mbeg)
                (let ((ssyntax (syntax-ppss)))
                  ;; Skip comments and strings — those mention the constant in prose.
                  (unless (or (nth 4 ssyntax) (nth 3 ssyntax))
                    (literal-configctl--violation
                     "agenote-no-domain"
                     (format "%s line %d references literal:executable-agenote directly (route through literal/agenote-call)"
                             owner line)))))))))))
  (literal-configctl--report-audit "audit-agenote-domain"))

(defconst literal-configctl-guix-manifest-file
  (expand-file-name "../../../../../source/config.org" literal-configctl-root)
  "Path to the Guix home manifest in the Guix-configs root repo.
Resolved relative to this emacs config dir (.config/emacs → 5 levels up to the
Guix-configs repo root, then source/config.org).")

(defun literal-configctl--manifest-packages ()
  "Return the list of \"emacs-NAME\" strings from the Guix manifest."
  (let ((file literal-configctl-guix-manifest-file)
        packages)
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "\"\\(emacs-[a-z0-9-]+\\)\"" nil t)
          (push (match-string 1) packages))))
    (delete-dups (nreverse packages))))

(defun literal-configctl--config-required-packages ()
  "Return package-name strings referenced by emacs.org config.
Covers four reference patterns, all returned as Emacs-level symbol names
(no emacs- prefix):
  1. `(use-package NAME)'         — direct declaration
  2. `(require '\\='NAME)'          — explicit feature require
  3. fn-call (manifest-aware)     — `#\\='NAME-foo' or `(NAME ...)' where NAME
                                  matches a manifest entry; resolved by the
                                  caller via `--audit-packages' filter
  4. `with-eval-after-load '\\='NAME' — post-load hook

NAME-mode autoloads in hook registrations are collected separately and
normalized (strip -mode suffix) so they can match the manifest."
  (let ((use-package-names nil)
        (require-names nil)
        (fn-call-names nil)
        (after-load-names nil)
        (mode-names nil))
    (dolist (block (literal-configctl--src-blocks))
      (let ((body (nth 4 block)))
        (with-temp-buffer
          (insert body)
          (goto-char (point-min))
          (while (re-search-forward "(use-package[[:space:]]+\\([a-z0-9-]+\\)" nil t)
            (push (match-string 1) use-package-names))
          (goto-char (point-min))
          (while (re-search-forward "(require[[:space:]]+'\\([a-z0-9-]+\\)" nil t)
            (push (match-string 1) require-names))
          (goto-char (point-min))
          (while (re-search-forward
                  "#?'\\([a-z][a-z0-9-]+\\)\\_>" nil t)
            (push (match-string 1) fn-call-names))
          (goto-char (point-min))
          (while (re-search-forward "(\\([a-z][a-z0-9-]+\\)[[:space:]]" nil t)
            (push (match-string 1) fn-call-names))
          (goto-char (point-min))
          (while (re-search-forward
                  "with-eval-after-load[[:space:]]+'\\([a-z0-9-]+\\)" nil t)
            (push (match-string 1) after-load-names))
          (goto-char (point-min))
          (while (re-search-forward "\\.\\s-*\\(#?'\\([a-z0-9-]+-mode\\)\\)" nil t)
            (push (match-string 2) mode-names)))))
    (let ((modes-as-packages
           (delete-dups
            (delq nil
                  (mapcar (lambda (m)
                            (let ((stripped
                                   (replace-regexp-in-string "-mode\\'" "" m)))
                              (unless (string-empty-p stripped) stripped)))
                          mode-names)))))
      (list (delete-dups (nreverse use-package-names))
            (delete-dups (nreverse require-names))
            (delete-dups (nreverse fn-call-names))
            (delete-dups (nreverse after-load-names))
            modes-as-packages))))

(defun literal-configctl--manifest-prefix-match (name manifest-set)
  "Return the longest prefix of NAME that matches a manifest entry.
Strip NAME at hyphens right-to-left, trying each progressively shorter
prefix. e.g. 'magit-status' tries 'magit-status', 'magit'; 'avy-goto-char'
tries all three prefixes. Returns the manifest name (string) or nil."
  (let ((parts (split-string name "-" t))
        (best nil))
    ;; Try progressively shorter prefixes: [magit status], [magit], []
    (while parts
      (let ((candidate (mapconcat #'identity parts "-")))
        (when (member candidate manifest-set)
          (setq best candidate)))
      (setq parts (nbutlast parts)))
    best))

(defconst literal-configctl--built-in-packages
  ;; Emacs 内置 feature。这些 feature 在本配置中出现 (use-package X)
  ;; 或 (require 'X) 也不需要 manifest 条目 —— 它们由 Emacs 自身提供。
  ;; 列表只覆盖本配置真实引用过的内置包;新增引用时同步扩充。
  '("recentf" "savehist" "saveplace" "winner" "flymake" "project" "eldoc" "xref"
    "compile" "gdb-mi" "dired" "dired-x" "dired-aux" "org-agenda" "org-capture"
    "org-clock" "org-id" "ox" "ox-org" "ox-md" "ox-html" "paren" "hl-line" "whitespace"
    "flyspell" "isearch" "ibuffer" "ibuf-ext" "reveal" "woman" "man")
  "Emacs built-in packages referenced in this config.
(use-package X) or (require 'X) for these names need no manifest entry.")

(defconst literal-configctl--subfeature-map
  ;; 父包名 → 该父包随附提供的子功能 symbol 列表(不需独立 manifest 条目)。
  ;; 由 Guix 的父包 emacs-NAME 内部提供,manifest 只列父包。
  '(("vertico" . ("vertico-multiform" "vertico-directory" "vertico-quick"
                  "vertico-repeat" "vertico-prescient" "vertico-buffer"
                  "vertico-mouse" "vertico-flat" "vertico-grid"
                  "vertico-indexed" "vertico-scroll" "vertico-suspend"))
    ("corfu"   . ("corfu-popupinfo" "corfu-prescient" "corfu-echo"
                  "corfu-history" "corfu-indexed" "corfu-echo"))
    ("embark"  . ("embark-consult"))
    ("org"     . ("org-element" "org-keys" "org-refile" "org-src"
                  "org-table" "org-timer" "org-indent" "org-faces"
                  "org-list" "org-attach" "org-archive" "org-inlinetask"
                  "org-compat" "org-macs" "org-fold" "org-cycle"))
    ("eglot"   . ("eglot-x" "eglot-imenu" "eglot-events"))
    ("consult" . ("consult-xref" "consult-flymake" "consult-org"
                  "consult-isearch" "consult-register" "consult-yank"))
    ("org-roam" . ("org-roam-db" "org-roam-node" "org-roam-buffer"
                   "org-roam-dailies" "org-roam-protocol")))
  "Alist of parent package → list of child subfeatures it provides.
Subfeature names need no independent manifest entry (provided by parent).")

(defconst literal-configctl--runtime-deps
  ;; 显式登记的运行时依赖:manifest 必须存在,但本配置不 (use-package X)
  ;; —— 这些包通过其他包的 require/autoload 隐式加载,或被 Emacs 端
  ;; require 后由 manifest 提供实际代码。
  '(;; Ghostel pre-spawn 需要 with-editor 内部 API
    "with-editor"
    ;; popup backend(kind-icon / corfu-popupinfo / embark 等隐式 require)
    "posframe"
    ;; org-export 后端
    "htmlize" "ox-gfm"
    ;; magit 隐式依赖
    "git-modes" "magit-delta" "magit-todos"
    ;; LSP 扩展(eglot 配置块内 require)
    "eglot-x"
    ;; use-package 宏本身(整个 emacs.org 都依赖,无独立 use-package)
    "use-package")
  "Manifest packages required at runtime but not declared via use-package.")

(defun literal-configctl--subfeature-parent (name)
  "Return parent package name if NAME is a subfeature, else nil."
  (cl-block nil
    (pcase-dolist (`(,parent . ,children) literal-configctl--subfeature-map)
      (when (member name children)
        (cl-return parent)))
    nil))

(defun literal-configctl--classify-package (name manifest-set use-set)
  "Classify a single package NAME into one of four categories.
MANIFEST-SET is the set of manifest names (no emacs- prefix).
USE-SET is the set of names referenced via use-package/require/fn-call.
Returns one of: \\='built-in, \\='sub-feature, \\='runtime-dep, \\='used, \\='candidate."
  (cond
   ((member name literal-configctl--built-in-packages) 'built-in)
   ((literal-configctl--subfeature-parent name) 'sub-feature)
   ((and (member name manifest-set)
         (member name literal-configctl--runtime-deps)) 'runtime-dep)
   ((member name use-set) 'used)
   ((member name manifest-set) 'candidate)
   (t 'unknown)))

(defun literal-configctl--audit-packages ()
  "Cross-check Guix manifest vs config references.
Output a four-class report (PLAN §7.2):
  [used]        — declared via use-package/require/fn-call AND in manifest
  [runtime-dep] — in manifest, used implicitly via require/autoload,
                  listed in `literal-configctl--runtime-deps'
  [built-in]    — Emacs built-in, no manifest entry needed
  [sub-feature] — provided by a parent package in manifest
  [candidate]   — in manifest but no direct use entry (audit informational)
  [unknown]     — referenced in config but missing from manifest and not
                  classified (this is the only class reported as violation).

Reference scanning strategy: (use-package X) and (require 'X) are
authoritative. Function-call references (#'NAME-foo, (NAME ...),
with-eval-after-load 'NAME) are only counted when NAME exactly matches a
manifest entry — this avoids false positives from Emacs built-ins like
add-hook / assoc that share no name with any package."
  (let* ((manifest (literal-configctl--manifest-packages))
         (manifest-names (mapcar (lambda (p) (substring p 6)) manifest))
         (manifest-set (delete-dups manifest-names))
         (required (literal-configctl--config-required-packages))
         (use-packages (nth 0 required))
         (require-names (nth 1 required))
         (fn-call-raw (nth 2 required))
         (after-load-raw (nth 3 required))
         (mode-as-packages (nth 4 required))
         (_debug-start (current-time)))
    (let* ((fn-call-names
            (delq nil
                  (delete-dups
                   (mapcar (lambda (n)
                             (literal-configctl--manifest-prefix-match
                              n manifest-set))
                           fn-call-raw))))
           (after-load-names
            (delq nil
                  (delete-dups
                   (mapcar (lambda (n)
                             (literal-configctl--manifest-prefix-match
                              n manifest-set))
                           after-load-raw))))
           (use-set (delete-dups
                     (append use-packages require-names fn-call-names
                             after-load-names mode-as-packages)))
           (classes (make-hash-table :test 'eq))
           (reports (make-hash-table :test 'eq))
           (unknown-names nil)
           (candidate-names nil)
           (used-counts (make-hash-table :test 'equal)))
      ;; Count references per use-set member for [used] reporting.
      (dolist (n use-set)
        (let ((count 0))
          (when (member n use-packages) (cl-incf count))
          (when (member n require-names) (cl-incf count))
          (when (member n fn-call-names) (cl-incf count))
          (when (member n after-load-names) (cl-incf count))
          (when (member n mode-as-packages) (cl-incf count))
          (puthash n count used-counts)))
      ;; Classify every name that appears in either manifest or config references.
      ;; copy-sequence on inputs: delete-dups is destructive and would corrupt
      ;; manifest-set/use-set otherwise (we observed use-set shrinking from 99
      ;; to 30 elements when sharing cells with the delete-dups target).
      (let ((all-names (delete-dups (append (copy-sequence manifest-set)
                                            (copy-sequence use-set)))))
        (dolist (name all-names)
          (let ((class (literal-configctl--classify-package
                        name manifest-set use-set)))
            (push name (gethash class classes nil))
            (pcase class
              ('used
               (let ((reasons nil))
                 (when (member name use-packages) (push "use-package" reasons))
                 (when (member name require-names) (push "require" reasons))
                 (when (member name fn-call-names) (push "fn-call" reasons))
                 (when (member name after-load-names) (push "after-load" reasons))
                 (when (member name mode-as-packages) (push "mode-ref" reasons))
                 (puthash name
                          (format "[used]              emacs-%s (%d refs: %s)"
                                  name (gethash name used-counts 0)
                                  (mapconcat #'identity (nreverse reasons) "+"))
                          reports)))
              ('runtime-dep
               (puthash name
                        (format "[runtime-dep]       emacs-%s (listed in runtime-deps)" name)
                        reports))
              ('built-in
               (puthash name
                        (format "[built-in]          %s (Emacs built-in, no manifest needed)" name)
                        reports))
              ('sub-feature
               (let ((parent (literal-configctl--subfeature-parent name)))
                 (puthash name
                          (format "[sub-feature]       %s (provided by emacs-%s)" name parent)
                          reports)))
              ('candidate
               (push name candidate-names)
               (puthash name
                        (format "[candidate]         emacs-%s (manifest only, no direct entry)" name)
                        reports))
              ('unknown
               (push name unknown-names)
               (puthash name
                        (format "[unknown]           %s (referenced in config but no manifest entry)" name)
                        reports))))))
      ;; Emit reports (sorted within each class).
      (princ (format "Total manifest: %d, total config refs: %d, classes:\n"
                     (length manifest-set) (length use-set)))
      (dolist (class '(used runtime-dep built-in sub-feature candidate unknown))
        (let ((names (sort (gethash class classes nil) #'string<)))
          (princ (format "  %s: %d\n" class (length names)))
          (dolist (n names)
            (princ (format "    %s\n" (gethash n reports ""))))))
      ;; Only [unknown] is a real violation (config references missing package).
      (dolist (name (sort unknown-names #'string<))
        (literal-configctl--violation
         "package-missing"
         (format "%s referenced in config but no emacs-%s in manifest"
                 name name)))
      (literal-configctl--report-audit "audit-packages"))))


;;; ---------------------------------------------------------------------------
;;; ERT test runner
;;; ---------------------------------------------------------------------------

(defun literal-configctl-test ()
  "Tangle emacs.org into an isolated runtime, load it, and run ERT tests."
  (pcase-let* ((`(,runtime ,target) (literal-configctl-check t))
               (user-emacs-directory (file-name-as-directory runtime))
               (default-directory literal-configctl-root)
               (test-file (expand-file-name "test/literal-config-tests.el"
                                            literal-configctl-root))
               (tests-target (expand-file-name "literal-config-tests.el" runtime)))
    (unless (file-readable-p test-file)
      (literal-configctl--fail "missing test file: %s" test-file))
    (unwind-protect
        (progn
          (copy-file test-file tests-target t)
          (literal-configctl--bootstrap-guix-autoloads)
          (load target nil t)
          ;; Tests may need a few smoke-side effects loaded.
          (let ((kill-emacs-hook nil))
            (load tests-target nil t)
            (ert-run-tests-batch-and-exit t)))
      (delete-directory runtime t))))


;;; ---------------------------------------------------------------------------
;;; check / load / new subcommands
;;; ---------------------------------------------------------------------------

(defun literal-configctl-check (&optional keep-tangle strict)
  "Run structural and tangle audits. With STRICT, also enforce audit rules."
  (let ((data-assignments (literal-configctl--audit-i18n-data)))
    (pcase-let* ((`(,blocks ,refs) (literal-configctl--check-structure))
                 (`(,runtime ,target (,forms ,definitions))
                  (literal-configctl--tangle-and-audit)))
      (when strict
        (let ((agenote-violations 0)
              (private-api-violations 0))
          ;; Collect counts without resetting; the audit functions return the
          ;; number of violations they just reported.
          (setq agenote-violations (literal-configctl--audit-agenote-domain))
          (setq private-api-violations (literal-configctl--audit-private-api))
          (when (or (> agenote-violations 0) (> private-api-violations 0))
            ;; Don't delete runtime if we're about to fail.
            (literal-configctl--fail
             "%d strict audit violation(s): agenote-domain=%d private-api=%d"
             (+ agenote-violations private-api-violations)
             agenote-violations private-api-violations))))
      (unless keep-tangle
        (delete-directory runtime t))
      (princ (format "OK: %d source blocks, %d noweb refs, %d forms, %d definitions, %d external data assignments\n"
                     blocks refs forms definitions data-assignments))
      (when keep-tangle (list runtime target)))))

(let ((status 0))
  (condition-case err
      (pcase command-line-args-left
        (`("map") (literal-configctl-map))
        (`("show" ,query) (literal-configctl-show query))
        (`("find" ,regexp) (literal-configctl-find regexp))
        (`("check") (literal-configctl-check nil nil))
        (`("check-strict") (literal-configctl-check nil t))
        (`("load") (literal-configctl-load))
        (`("test") (literal-configctl-test))
        (`("audit-keys") (literal-configctl--audit-keys))
        (`("audit-private-api") (literal-configctl--audit-private-api))
        (`("audit-agenote-domain") (literal-configctl--audit-agenote-domain))
        (`("audit-packages") (literal-configctl--audit-packages))
        ((or 'nil `("help") `("--help") `("-h")) (literal-configctl-usage))
        (_ (literal-configctl-usage)
           (literal-configctl--fail "invalid arguments: %S"
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
