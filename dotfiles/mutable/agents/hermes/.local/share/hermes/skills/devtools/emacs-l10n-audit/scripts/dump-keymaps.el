;;; dump-keymaps.el --- Dump actual keymap bindings from running Emacs -*- lexical-binding: t; -*-
;;
;; 用法（从 emacs 配置根目录运行）:
;;   emacs --batch -Q \
;;     --eval '(progn (setq user-emacs-directory default-directory) \
;;                    (load (expand-file-name "init.el")))' \
;;     -l scripts/dump-keymaps.el
;;
;; 输出格式（stdout，可直接被 Python 解析）:
;;   MODE:org-mode
;;     C-c C-a|org-attach
;;     C-c C-b|org-backward-heading-same-level
;;     <down>|org-shiftdown
;;     M-g|magit-file-dispatch
;;   MODE:markdown-mode
;;     ...
;;
;; 注意: batch 模式下第三方包可能未被 require, 导致 keymap 变量不存在。
;; 只有线程配置 (org-mode 等 core 包) 才能可靠 dump。
;; 对于 lazy-load 的包 (markdown-mode, rust-mode 等), 需在脚本中显式 require。

(require 'cl-lib)
(require 'subr-x)

(defconst my/target-modes
  '(org-mode
    markdown-mode
    python-ts-mode
    rust-mode
    web-mode
    json-mode
    go-ts-mode
    typescript-mode
    kotlin-mode
    gdscript-mode
    zig-mode))

(defun my/key-to-string (key)
  "将 map-keymap 的 KEY（整数或符号）转换为 which-key 格式字符串。"
  (cond
   ((characterp key)
    (cond
     ((= key 9) "TAB")
     ((= key 13) "RET")
     ((= key 27) "ESC")
     ((= key 32) "SPC")
     ((and (>= key 33) (< key 127))
      (char-to-string key))
     (t
      (key-description (vector key)))))
   ((symbolp key)
    (let ((s (symbol-name key)))
      (cond
       ((string= s "return") "RET")
       ((string= s "tab") "TAB")
       ((string= s "escape") "ESC")
       ((string= s "backspace") "DEL")
       ((string-prefix-p "C-" s) s)
       ((string-prefix-p "M-" s) s)
       ((string-prefix-p "S-" s) s)
       (t (format "<%s>" s)))))
   (t (format "%s" key))))

(defun my/dump-keymap (keymap prefix)
  "递归遍历 KEYMAP，返回 ((key-seq . command-name) ...) 列表。"
  (let (results)
    (map-keymap
     (lambda (key binding)
       (let* ((key-str (my/key-to-string key))
              (full-key (if (string-empty-p prefix)
                            key-str
                          (concat prefix " " key-str))))
         (cond
          ((keymapp binding)
           (let ((sub (my/dump-keymap binding full-key)))
             (setq results (append results sub))))
          ((symbolp binding)
           (when (not (string-match-p "\\`menu-" (symbol-name binding)))
             (push (cons full-key (symbol-name binding)) results)))
          ((and (consp binding) (symbolp (cdr binding)))
           (when (not (string-match-p "\\`menu-" (symbol-name (cdr binding))))
             (push (cons full-key (symbol-name (cdr binding))) results))))))
     keymap)
    (nreverse results)))

(defun my/get-mode-keymap (mode)
  (let ((map-sym (intern-soft (format "%s-map" mode))))
    (when (and map-sym (boundp map-sym) (keymapp (symbol-value map-sym)))
      (symbol-value map-sym))))

(defun my/filter-interesting (bindings)
  (cl-remove-if-not
   (lambda (entry)
     (let ((key (car entry)) (cmd (cdr entry)))
       (and (not (string-match-p "mouse" key))
            (not (string-match-p "\\`menu-bar\\|header-line\\|mode-line" key))
            (not (string-match-p "\\`<remap>" key))
            (not (string= cmd "undefined"))
            (not (string= cmd "ignore"))
            (not (string= cmd "digit-argument"))
            (not (string= cmd "negative-argument"))
            ;; 过滤纯数字键码（map-keymap 返回的整数事件）
            (not (string-match-p "\\`[0-9]" key)))))
   bindings))

(with-temp-buffer
  (dolist (mode my/target-modes)
    (let ((map (my/get-mode-keymap mode)))
      (if map
          (let* ((bindings (my/dump-keymap map ""))
                 (filtered (my/filter-interesting bindings)))
            (insert (format "MODE:%s\n" mode))
            (dolist (entry (sort filtered (lambda (a b) (string< (car a) (car b)))))
              (insert (format "  %s|%s\n" (car entry) (cdr entry))))
            (insert "\n"))
        (insert (format "MODE:%s|NOT_FOUND\n\n" mode)))))
  (princ (buffer-string)))
