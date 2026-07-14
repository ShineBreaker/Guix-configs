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
     literal:help-dashboard-bindings
     literal:help-sections))
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
  (dolist (function '(literal/add-frame-hook
                      literal/call-process
                      literal/color-scheme-init
                      literal/completion-setup-display
                      literal/dashboard-open-for-client-frame
                      literal/display-or-focus
                      literal/help--extract-dashboard-bindings
                      literal/knowledge-collect-org-files
                      literal/open-terminal
                      literal/tabs-next))
    (literal-configctl--assert (fboundp function) "missing function %s" function))
  (dolist (binding '(("C-S-c" . literal/copy-dwim)
                     ("C-<tab>" . literal/tabs-next)
                     ("C-c o k s" . literal/knowledge-search)
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
  (dolist (key '("kn" "km" "ka"))
    (literal-configctl--assert (assoc key org-capture-templates)
                               "missing Org capture template %s" key))
  (require 'flycheck)
  (literal-configctl--assert
   (eq (lookup-key flycheck-error-list-mode-map (kbd "RET"))
       #'flycheck-error-list-goto-error)
   "Flycheck error-list RET binding missing")
  (require 'which-key)
  (literal-configctl--assert (null literal--pending-wk-descs)
                             "pending Which-key descriptions were not flushed")
  (literal-configctl--assert (consp literal:which-key-description-spec)
                             "Which-key translation data missing")
  (literal-configctl--assert
   (equal (cdr (assoc "Undo" literal:context-menu-label-translations)) "撤销")
   "context-menu translation data missing Undo -> 撤销")
  (literal-configctl--assert (consp literal:help-sections)
                             "shortcut help sections data missing")
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

(defun literal-configctl-check (&optional keep-tangle)
  (let ((data-assignments (literal-configctl--audit-i18n-data)))
    (pcase-let* ((`(,blocks ,refs) (literal-configctl--check-structure))
               (`(,runtime ,target (,forms ,definitions))
                (literal-configctl--tangle-and-audit)))
      (unless keep-tangle
        (delete-directory runtime t))
      (princ (format "OK: %d source blocks, %d noweb refs, %d forms, %d definitions, %d external data assignments\n"
                     blocks refs forms definitions data-assignments))
      (when keep-tangle (list runtime target)))))

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
          (make-directory (expand-file-name "var/projectile/" runtime) t)
          (with-temp-file (expand-file-name "var/projectile/known-projects.el" runtime)
            (prin1 nil (current-buffer)))
          (setq-default projectile-known-projects-file
                        (expand-file-name "var/projectile/known-projects.el" runtime))
          (literal-configctl--bootstrap-guix-autoloads)
          (load target nil t)
          (literal-configctl--smoke-test)
          (setq kill-emacs-hook nil)
          (princ "OK: isolated load and runtime smoke assertions passed\n"))
      (delete-directory runtime t))))

(defun literal-configctl-usage ()
  (princ "Usage: scripts/configctl COMMAND [ARG]\n\n")
  (princ "  map           list stable feature IDs and their source footprint\n")
  (princ "  show ID       print one feature subtree\n")
  (princ "  find REGEXP   locate matches with owning feature ID\n")
  (princ "  check         audit structure, noweb graph, tangle and definitions\n")
  (princ "  load          check and batch-load in an isolated runtime\n"))

(pcase command-line-args-left
  (`("map") (literal-configctl-map))
  (`("show" ,query) (literal-configctl-show query))
  (`("find" ,regexp) (literal-configctl-find regexp))
  (`("check") (literal-configctl-check))
  (`("load") (literal-configctl-load))
  ((or 'nil `("help") `("--help") `("-h")) (literal-configctl-usage))
  (_ (literal-configctl-usage)
     (literal-configctl--fail "invalid arguments: %S" command-line-args-left)))

;;; configctl.el ends here
