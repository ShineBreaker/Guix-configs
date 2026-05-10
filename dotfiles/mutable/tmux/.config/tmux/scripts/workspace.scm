#!/usr/bin/env guile
!#

;; workspace.scm - 工作区快照管理
;; 用法：workspace.scm save <name>
;;       workspace.scm load <name> [--dry-run]
;;       workspace.scm list
;;       workspace.scm remove <name>

(load (string-append (getenv "HOME") "/.config/tmux/scripts/tmux-helpers.scm"))

(use-modules (ice-9 ftw)
             (ice-9 match)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-34))

(define workspace-dir
  (string-append (or (getenv "XDG_DATA_HOME")
                     (string-append (getenv "HOME") "/.local/share"))
                 "/tmux/workspaces"))

(define (die fmt . args)
  (apply format (current-error-port) (string-append fmt "~%") args)
  (exit 1))

(define (tmux-run! . args)
  (let ((result (apply tmux-cmd args)))
    (unless (zero? (car result))
      (die "tmux command failed: tmux ~a~%~a" (string-join args " ") (cdr result)))
    (cdr result)))

(define (mkdir-p dir)
  (unless (file-exists? dir)
    (mkdir-p (dirname dir))
    (mkdir dir)))

(define (ensure-workspace-dir)
  (unless (file-exists? workspace-dir)
    (mkdir-p workspace-dir)))

(define (control-char? char)
  (let ((n (char->integer char)))
    (or (< n 32) (= n 127))))

(define (valid-workspace-name? name)
  (and (not (string-null? name))
       (not (member name '("." "..")))
       (not (string-index name #\/))
       (not (any control-char? (string->list name)))))

(define (workspace-path name)
  (unless (valid-workspace-name? name)
    (die "invalid workspace name: ~a" name))
  (string-append workspace-dir "/" name ".json"))

(define (tmux-session-exists? name)
  (let* ((raw (cdr (tmux-cmd "list-sessions" "-F" "#{session_name}")))
         (sessions (if (string-null? raw) '() (string-split raw #\newline))))
    (member name sessions)))

;; === Small JSON codec ===
;; Guix profile used here does not provide guile-json, so keep a small codec for
;; the simple object/array/string/number shape this script owns.

(define (left-pad str width char)
  (if (>= (string-length str) width)
      str
      (string-append (make-string (- width (string-length str)) char) str)))

(define (json-unicode-escape char)
  (string-append "\\u" (left-pad (number->string (char->integer char) 16) 4 #\0)))

(define (json-escape str)
  (call-with-output-string
    (lambda (port)
      (for-each
       (lambda (char)
         (case char
           ((#\") (display "\\\"" port))
           ((#\\) (display "\\\\" port))
           ((#\newline) (display "\\n" port))
           ((#\return) (display "\\r" port))
           ((#\tab) (display "\\t" port))
           (else
            (if (control-char? char)
                (display (json-unicode-escape char) port)
                (display char port)))))
       (string->list str)))))

(define (alist-object? value)
  (and (list? value)
       (every (lambda (item)
                (and (pair? item) (string? (car item))))
              value)))

(define (write-json-value value port)
  (cond
   ((string? value) (format port "\"~a\"" (json-escape value)))
   ((number? value) (display value port))
   ((eq? value #t) (display "true" port))
   ((eq? value #f) (display "false" port))
   ((alist-object? value)
    (display "{" port)
    (let loop ((items value) (first? #t))
      (unless (null? items)
        (unless first? (display "," port))
        (format port "\"~a\":" (json-escape (caar items)))
        (write-json-value (cdar items) port)
        (loop (cdr items) #f)))
    (display "}" port))
   ((list? value)
    (display "[" port)
    (let loop ((items value) (first? #t))
      (unless (null? items)
        (unless first? (display "," port))
        (write-json-value (car items) port)
        (loop (cdr items) #f)))
    (display "]" port))
   (else (die "unsupported JSON value: ~s" value))))

(define (write-json-file path value)
  (call-with-output-file path
    (lambda (port)
      (write-json-value value port)
      (newline port))))

(define (json-error message)
  (die "invalid workspace JSON: ~a" message))

(define (skip-ws text pos)
  (let loop ((i pos))
    (if (and (< i (string-length text))
             (member (string-ref text i) '(#\space #\tab #\newline #\return)))
        (loop (+ i 1))
        i)))

(define (expect-char text pos expected)
  (let ((i (skip-ws text pos)))
    (if (and (< i (string-length text)) (char=? (string-ref text i) expected))
        (+ i 1)
        (json-error (format #f "expected '~a'" expected)))))

(define (hex-digit char)
  (cond
   ((char-numeric? char) (- (char->integer char) (char->integer #\0)))
   ((and (char>=? char #\a) (char<=? char #\f)) (+ 10 (- (char->integer char) (char->integer #\a))))
   ((and (char>=? char #\A) (char<=? char #\F)) (+ 10 (- (char->integer char) (char->integer #\A))))
   (else #f)))

(define (parse-json-string text pos)
  (let ((start (skip-ws text pos)))
    (unless (and (< start (string-length text)) (char=? (string-ref text start) #\"))
      (json-error "expected string"))
    (let loop ((i (+ start 1)) (chars '()))
      (when (>= i (string-length text))
        (json-error "unterminated string"))
      (let ((char (string-ref text i)))
        (cond
         ((char=? char #\") (cons (list->string (reverse chars)) (+ i 1)))
         ((char=? char #\\)
          (when (>= (+ i 1) (string-length text))
            (json-error "unterminated escape"))
          (let ((esc (string-ref text (+ i 1))))
            (case esc
              ((#\" #\\ #\/) (loop (+ i 2) (cons esc chars)))
              ((#\b) (loop (+ i 2) (cons #\backspace chars)))
              ((#\f) (loop (+ i 2) (cons #\page chars)))
              ((#\n) (loop (+ i 2) (cons #\newline chars)))
              ((#\r) (loop (+ i 2) (cons #\return chars)))
              ((#\t) (loop (+ i 2) (cons #\tab chars)))
              ((#\u)
               (when (> (+ i 6) (string-length text))
                 (json-error "short unicode escape"))
               (let ((digits (map hex-digit
                                  (string->list (substring text (+ i 2) (+ i 6))))))
                 (if (every identity digits)
                     (let ((code (+ (* (list-ref digits 0) 4096)
                                    (* (list-ref digits 1) 256)
                                    (* (list-ref digits 2) 16)
                                    (list-ref digits 3))))
                       (loop (+ i 6) (cons (integer->char code) chars)))
                     (json-error "bad unicode escape"))))
              (else (json-error "bad escape")))))
         (else (loop (+ i 1) (cons char chars))))))))

(define parse-json-value #f)

(define (parse-json-array text pos)
  (let loop ((i (expect-char text pos #\[)) (values '()))
    (let ((i* (skip-ws text i)))
      (cond
       ((and (< i* (string-length text)) (char=? (string-ref text i*) #\]))
        (cons (reverse values) (+ i* 1)))
       (else
        (let* ((parsed (parse-json-value text i*))
               (value (car parsed))
               (next (skip-ws text (cdr parsed))))
          (cond
           ((and (< next (string-length text)) (char=? (string-ref text next) #\,))
            (loop (+ next 1) (cons value values)))
           ((and (< next (string-length text)) (char=? (string-ref text next) #\]))
            (cons (reverse (cons value values)) (+ next 1)))
           (else (json-error "expected array separator")))))))))

(define (parse-json-object text pos)
  (let loop ((i (expect-char text pos #\{)) (items '()))
    (let ((i* (skip-ws text i)))
      (cond
       ((and (< i* (string-length text)) (char=? (string-ref text i*) #\}))
        (cons (reverse items) (+ i* 1)))
       (else
        (let* ((key-parsed (parse-json-string text i*))
               (key (car key-parsed))
               (after-key (expect-char text (cdr key-parsed) #\:))
               (value-parsed (parse-json-value text after-key))
               (value (car value-parsed))
               (next (skip-ws text (cdr value-parsed))))
          (cond
           ((and (< next (string-length text)) (char=? (string-ref text next) #\,))
            (loop (+ next 1) (cons (cons key value) items)))
           ((and (< next (string-length text)) (char=? (string-ref text next) #\}))
            (cons (reverse (cons (cons key value) items)) (+ next 1)))
           (else (json-error "expected object separator")))))))))

(define (parse-json-number text pos)
  (let loop ((i pos))
    (if (and (< i (string-length text))
             (or (char-numeric? (string-ref text i))
                 (member (string-ref text i) '(#\- #\+ #\. #\e #\E))))
        (loop (+ i 1))
        (let* ((raw (substring text pos i))
               (num (string->number raw)))
          (if num
              (cons num i)
              (json-error (format #f "bad number: ~a" raw)))))))

(set! parse-json-value
      (lambda (text pos)
        (let ((i (skip-ws text pos)))
          (when (>= i (string-length text))
            (json-error "unexpected end"))
          (let ((char (string-ref text i)))
            (cond
             ((char=? char #\") (parse-json-string text i))
             ((char=? char #\{) (parse-json-object text i))
             ((char=? char #\[) (parse-json-array text i))
             ((or (char-numeric? char) (char=? char #\-)) (parse-json-number text i))
             ((string-prefix? "true" (substring text i)) (cons #t (+ i 4)))
             ((string-prefix? "false" (substring text i)) (cons #f (+ i 5)))
             ((string-prefix? "null" (substring text i)) (cons #f (+ i 4)))
             (else (json-error (format #f "unexpected character: ~a" char))))))))

(define (read-json-file path)
  (let* ((text (call-with-input-file path read-string))
         (parsed (parse-json-value text 0))
         (tail (skip-ws text (cdr parsed))))
    (unless (= tail (string-length text))
      (json-error "trailing data"))
    (car parsed)))

;; === 保存 ===

(define (parse-window line)
  (match (string-split line #\tab)
    ((idx name layout path)
     `(("index" . ,(string->number idx))
       ("name" . ,name)
       ("layout" . ,layout)
       ("cwd" . ,path)))
    (_ (die "unexpected tmux window data: ~a" line))))

(define (save-workspace name)
  (ensure-workspace-dir)
  (let* ((current-session (tmux-display "#{session_name}"))
         (windows-raw (tmux-run! "list-windows" "-t" current-session "-F"
                                 (string-append "#{window_index}\t#{window_name}\t"
                                                "#{window_layout}\t#{pane_current_path}")))
         (window-lines (filter (lambda (line) (not (string=? line "")))
                               (string-split windows-raw #\newline)))
         (windows (map parse-window window-lines))
         (data `(("name" . ,name)
                 ("created" . ,(strftime "%Y-%m-%dT%H:%M:%S" (localtime (current-time))))
                 ("tmux_version" . ,(string-trim-both (tmux-run! "-V")))
                 ("windows" . ,windows))))
    (write-json-file (workspace-path name) data)
    (format #t "已保存工作区: ~a~%" name)))

;; === 加载 ===

(define (load-workspace name dry-run?)
  (let ((path (workspace-path name)))
    (unless (file-exists? path)
      (die "工作区 '~a' 不存在" name))
    (let ((data (read-json-file path)))
      (if dry-run?
          (display-dry-run data)
          (restore-workspace data)))))

(define (display-dry-run data)
  (format #t "工作区: ~a~%" (assoc-ref data "name"))
  (format #t "创建时间: ~a~%" (assoc-ref data "created"))
  (format #t "tmux 版本: ~a~%" (assoc-ref data "tmux_version"))
  (format #t "~%注意：快照只恢复窗口骨架，不恢复进程内部状态~%~%")
  (for-each
   (lambda (w)
     (format #t "  窗口 ~a: ~a (~a)~%"
             (assoc-ref w "index")
             (assoc-ref w "name")
             (assoc-ref w "cwd")))
   (or (assoc-ref data "windows") '())))

(define (restore-workspace data)
  (let* ((name (assoc-ref data "name"))
         (windows (or (assoc-ref data "windows") '()))
         (session-name (string-append "ws-" name)))
    (when (null? windows)
      (die "workspace has no windows: ~a" name))
    (when (tmux-session-exists? session-name)
      (die "tmux session already exists: ~a" session-name))
    (let* ((first-window (car windows))
           (first-name (assoc-ref first-window "name"))
           (first-cwd (assoc-ref first-window "cwd")))
      (tmux-run! "new-session" "-d" "-s" session-name "-n" first-name "-c" first-cwd)
      (for-each
       (lambda (w)
         (tmux-run! "new-window" "-t" (string-append session-name ":")
                    "-n" (assoc-ref w "name")
                    "-c" (assoc-ref w "cwd")))
       (cdr windows))
      (if (string-null? (tmux-display "#{client_tty}"))
          (format #t "已恢复工作区: ~a（当前没有可切换的 tmux client）~%" name)
          (begin
            (tmux-run! "switch-client" "-t" session-name)
            (format #t "已恢复工作区: ~a~%" name))))))

;; === 列表 ===

(define (list-workspaces)
  (ensure-workspace-dir)
  (let ((files (scandir workspace-dir
                       (lambda (file) (string-suffix? ".json" file)))))
    (if (null? files)
        (display "没有已保存的工作区\n")
        (for-each
         (lambda (file)
           (let* ((path (string-append workspace-dir "/" file))
                  (data (read-json-file path)))
             (format #t "~a  (~a)  ~a~%"
                     (assoc-ref data "name")
                     (assoc-ref data "tmux_version")
                     (assoc-ref data "created"))))
         files))))

;; === 删除 ===

(define (remove-workspace name)
  (let ((path (workspace-path name)))
    (if (file-exists? path)
        (begin
          (delete-file path)
          (format #t "已删除工作区: ~a~%" name))
        (die "工作区 '~a' 不存在" name))))

;; === 主入口 ===

(match (command-line)
  ((_ "save" name) (save-workspace name))
  ((_ "load" name "--dry-run") (load-workspace name #t))
  ((_ "load" name) (load-workspace name #f))
  ((_ "list") (list-workspaces))
  ((_ "remove" name) (remove-workspace name))
  (_ (die "用法: workspace.scm <save|load|list|remove> [name] [--dry-run]")))
