#!/usr/bin/env guile
!#

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; sidebar-render.scm — tmux 侧边栏长驻渲染进程
;;
;; 外部接口只有两个：
;;   daemon  长驻侧栏 pane，通过 FIFO 接收 refresh/click/toggle-group 事件
;;   render  单次渲染到 stdout，供检查与基准测试使用
;;
;; daemon 每次刷新只执行一次 tmux list-panes。当前上下文、侧栏宽度、
;; 折叠状态和全部 pane 数据都从这份快照取得，避免跨进程缓存和重复查询。

(use-modules (ice-9 match)
             (ice-9 popen)
             (ice-9 rdelim)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-34))

;; === tmux snapshot ===

(define sidebar-title "tmux-sidebar")
(define sidebar-command "sidebar-render.scm daemon")

(define (tmux-cmd . args)
  "执行 tmux 命令，返回 (exit-code . output)。"
  (let* ((port (apply open-pipe* OPEN_READ "tmux" args))
         (output (read-string port))
         (status (close-pipe port)))
    (cons status (string-trim-right output))))

(define (tmux-sidebar-pane? title start-command)
  (or (string=? title sidebar-title)
      (and start-command (string-contains start-command sidebar-command))))

;; 普通 pane 字段：session, window index/id/name, path, command, active,
;; title, pid, pane index, AI/custom title, custom description, locked title.
(define (collect-state)
  "用一次 list-panes 返回 (context pane-fields...)。
CONTEXT 为 session/window/折叠状态/宽度/当前 Git branch。"
  (let* ((current-pane (or (getenv "TMUX_PANE") ""))
         (format-string
          (string-append
           "#{pane_id}\t#{session_name}\t#{window_index}\t#{window_id}\t"
           "#{window_name}\t#{pane_current_path}\t#{pane_current_command}\t"
           "#{pane_active}\t#{pane_title}\t#{pane_pid}\t#{pane_index}\t"
           "#{pane_start_command}\t#{@tabby_ai_title}\t"
           "#{@sidebar_window_title}\t#{@sidebar_window_desc}\t"
           "#{@tabby_pane_title}\t#{@sidebar_collapsed_sessions}\t"
           "#{@sidebar_collapsed_groups}\t#{pane_width}\t#{@sidebar_width}\t"
           "#{@status_git_branch}\t__END__"))
         (result (tmux-cmd "list-panes" "-a" "-F" format-string)))
    (if (not (zero? (car result)))
        #f
        (let loop ((raw-lines (string-split (cdr result) #\newline))
                   (context #f)
                   (panes '()))
          (if (null? raw-lines)
              (list context (reverse panes))
              (match (string-split (car raw-lines) #\tab)
                ((pane-id session idx win-id name path command active title pid pane-idx
                          start ai-title custom-title custom-desc locked-title
                          collapsed-sessions collapsed-groups pane-width option-width
                          status-branch _end)
                 (cond
                  ((string=? pane-id current-pane)
                   (let ((context* (list session idx collapsed-sessions collapsed-groups
                                         pane-width option-width status-branch)))
                     (if (tmux-sidebar-pane? title start)
                         (loop (cdr raw-lines) context* panes)
                         (loop (cdr raw-lines)
                               context*
                               (cons (list session idx win-id name path command active
                                           title pid pane-idx ai-title custom-title
                                           custom-desc locked-title)
                                     panes)))))
                  ((tmux-sidebar-pane? title start)
                   (loop (cdr raw-lines) context panes))
                  (else
                   (loop (cdr raw-lines)
                         context
                         (cons (list session idx win-id name path command active
                                     title pid pane-idx ai-title custom-title
                                     custom-desc locked-title)
                               panes)))))
                (_ (loop (cdr raw-lines) context panes))))))))

;; === ANSI ===

(define ansi-erase-line "\x1b[K")
(define ansi-reset "\x1b[0m")
(define ansi-bold "\x1b[1m")
(define ansi-dim "\x1b[2m")
(define ansi-session "\x1b[97m")
(define ansi-group "\x1b[96m")
(define ansi-active "\x1b[94m")
(define ansi-desc "\x1b[37m")
(define ansi-session-active "\x1b[92m")

;; === Width ===

(define (string->positive-integer s fallback)
  (let ((n (and s (string->number s))))
    (if (and n (> n 0)) n fallback)))

;; 宽度缓存：每个 Guile 进程（即每次渲染/点击处理）内只计算一次，
;; 避免每行输出都重复调用 tmux 命令（单次渲染节省 60+ 次 tmux 调用）。
(define %sidebar-width-value 31)

(define (set-sidebar-width! pane-width option-width)
  (let* ((pane (string->positive-integer pane-width 0))
         (option (string->positive-integer option-width 32))
         (width (if (> pane 0) pane option)))
    (set! %sidebar-width-value (max 18 (- width 1)))))

(define (sidebar-width) %sidebar-width-value)

;; === Text ===

(define (field fields index fallback)
  (if (> (length fields) index)
      (list-ref fields index)
      fallback))

(define (row-session fields) (field fields 0 ""))
(define (row-index fields) (field fields 1 ""))
(define (row-window-id fields) (field fields 2 ""))
(define (row-window-name fields) (field fields 3 ""))
(define (row-path fields) (field fields 4 ""))
(define (row-command fields) (field fields 5 ""))
(define (row-pane-active? fields) (string=? (field fields 6 "") "1"))
(define (row-pane-title fields) (field fields 7 ""))
(define (row-pane-pid fields) (field fields 8 ""))
(define (row-pane-index fields) (field fields 9 ""))
(define (row-ai-title fields) (field fields 10 ""))
(define (row-custom-title fields) (field fields 11 ""))
(define (row-custom-desc fields) (field fields 12 ""))
(define (row-locked-pane-title fields) (field fields 13 ""))

(define (nonempty s)
  (and s (not (string=? s "")) s))

(define (shell-command? command)
  (member command '("fish" "bash" "zsh" "sh" "nu" "xonsh")))

(define (generic-title? title command window-name)
  (or (not (nonempty title))
      (string=? title "tmux-sidebar")
      (string=? title command)
      (string=? title window-name)
      (string-prefix? "~" title)))

(define (set-option-list! name values)
  (tmux-cmd "set" "-g" name (string-join values ",")))

(define (toggle-list-value! option current-value key)
  (let ((values (if (string-null? current-value)
                    '()
                    (string-split current-value #\,))))
    (set-option-list! option
                      (if (member key values)
                          (delete key values)
                          (cons key values)))))

(define (session-key session)
  (string-append "s:" (number->string (string-hash session) 16)))

(define (group-collapse-key session group-key)
  (string-append "g:" (number->string (string-hash (string-append session ":" group-key)) 16)))

(define (basename-of-path path)
  (let ((idx (string-rindex path #\/)))
    (if idx (substring path (+ idx 1)) path)))

(define (char-width c)
  (let ((n (char->integer c))
        (category (char-general-category c)))
    (cond
     ((memq category '(Mn Me Cf)) 0)
     ((or (and (>= n #x3400) (<= n #x4DBF))
          (and (>= n #x4E00) (<= n #x9FFF))
          (and (>= n #xF900) (<= n #xFAFF))
          (and (>= n #xAC00) (<= n #xD7AF))
          (and (>= n #xFF01) (<= n #xFF60))
          (and (>= n #xFFE0) (<= n #xFFE6))
          (and (>= n #x20000) (<= n #x2FFFD))
          (and (>= n #x30000) (<= n #x3FFFD)))
      2)
     (else 1))))

(define (string-width text)
  (fold (lambda (c width) (+ width (char-width c)))
        0
        (string->list text)))

(define (truncate-string text max-width)
  (let ((ellipsis "…"))
    (cond
     ((<= max-width 0) "")
     ((<= (string-width text) max-width) text)
     ((= max-width 1) ellipsis)
     (else
      (let loop ((chars (string->list text))
                 (width 0)
                 (result '()))
        (if (or (null? chars)
                (> (+ width (char-width (car chars))) (- max-width 1)))
            (string-append (list->string (reverse result)) ellipsis)
            (loop (cdr chars)
                  (+ width (char-width (car chars)))
                  (cons (car chars) result))))))))

(define (pad-string text width)
  (let ((padding (- width (string-width text))))
    (if (positive? padding)
        (string-append text (make-string padding #\space))
        text)))

(define (directory-path? path)
  (false-if-exception (eq? (stat:type (stat path)) 'directory)))

(define (hex-char? c)
  (or (char-numeric? c)
      (and (char>=? c #\a) (char<=? c #\f))
      (and (char>=? c #\A) (char<=? c #\F))))

(define %git-head-paths (make-hash-table))
(define %git-branches (make-hash-table))
(define git-path-cache-ticks (* 30 internal-time-units-per-second))

(define (absolute-path? path)
  (and (positive? (string-length path))
       (char=? (string-ref path 0) #\/)))

(define (gitdir-from-marker directory marker)
  (cond
   ((directory-path? marker) marker)
   ((file-exists? marker)
    (let ((content (string-trim-both (call-with-input-file marker read-string))))
      (and (string-prefix? "gitdir: " content)
           (let* ((value (string-drop content 8))
                  (path (if (absolute-path? value)
                            value
                            (string-append directory "/" value))))
             (false-if-exception (canonicalize-path path))))))
   (else #f)))

(define (find-git-head path)
  (let* ((now (get-internal-real-time))
         (cached (hash-ref %git-head-paths path #f)))
    (if (and cached (< now (car cached)))
        (cdr cached)
        (let* ((start (false-if-exception (canonicalize-path path)))
               (head
                (and start
                     (let loop ((directory start))
                       (let* ((marker (string-append directory "/.git"))
                              (gitdir (gitdir-from-marker directory marker)))
                         (cond
                          (gitdir
                          (let ((candidate (string-append gitdir "/HEAD")))
                             (and (file-exists? candidate) candidate)))
                          ((string=? directory "/") #f)
                          (else
                           (let ((parent (parent-path directory)))
                             (if (string=? parent directory)
                                 #f
                                 (loop parent))))))))))
          (hash-set! %git-head-paths path
                     (cons (+ now git-path-cache-ticks) head))
          head))))

(define (head-content->branch content)
  (cond
   ((string-prefix? "ref: refs/heads/" content)
    (let ((branch (string-drop content (string-length "ref: refs/heads/"))))
      (and (not (string-null? branch)) branch)))
   ((and (>= (string-length content) 7)
         (string-every hex-char? content))
    (substring content 0 7))
   (else #f)))

(define (read-git-head path)
  (let ((head (find-git-head path)))
    (and head
         (false-if-exception
          (let* ((info (stat head))
                 (stamp (list (stat:mtime info)
                              (stat:mtimensec info)
                              (stat:size info)))
                 (cached (hash-ref %git-branches head #f)))
            (if (and cached (equal? (car cached) stamp))
                (cdr cached)
                (let* ((content (string-trim-both
                                 (call-with-input-file head read-string)))
                       (branch (head-content->branch content)))
                  (hash-set! %git-branches head (cons stamp branch))
                  branch)))))))

(define %cmdline-cache (make-hash-table))
(define cmdline-cache-ticks (* 2 internal-time-units-per-second))

(define (process-argv pid)
  (let ((file (string-append "/proc/" pid "/cmdline")))
    (and (file-exists? file)
         (let ((args (filter (lambda (arg) (not (string-null? arg)))
                             (string-split (call-with-input-file file read-string)
                                           #\nul))))
           (and (pair? args) args)))))

(define (child-pids pid)
  (let ((file (string-append "/proc/" pid "/task/" pid "/children")))
    (if (file-exists? file)
        (let ((raw (string-trim-both (call-with-input-file file read-string))))
          (if (string-null? raw)
              '()
              (string-split raw #\space)))
        '())))

(define (foreground-argv/uncached pid)
  (let loop ((queue (if (nonempty pid) (list pid) '()))
             (last #f)
             (seen '()))
    (if (null? queue)
        last
        (let* ((pid* (car queue))
               (rest (cdr queue)))
          (if (member pid* seen)
              (loop rest last seen)
              (let ((argv (process-argv pid*))
                    (children (child-pids pid*)))
                (loop (append children rest)
                      (or argv last)
                      (cons pid* seen))))))))

(define (foreground-argv pid)
  (let* ((now (get-internal-real-time))
         (cached (and (nonempty pid) (hash-ref %cmdline-cache pid #f))))
    (if (and cached (< now (car cached)))
        (cdr cached)
        (let ((argv (foreground-argv/uncached pid)))
          (when (nonempty pid)
            (hash-set! %cmdline-cache pid
                       (cons (+ now cmdline-cache-ticks) argv)))
          argv))))

(define (shorten-argv argv command)
  (if (not (pair? argv))
      ""
      (let* ((raw-program (basename-of-path (car argv)))
             (program (if (string-prefix? "-" raw-program)
                          (string-drop raw-program 1)
                          raw-program))
             (args (cdr argv))
             (trimmed-args (filter (lambda (arg)
                                     (not (member arg '("--login" "-l" "-i"))))
                                   args))
             (short (string-join (cons program (take trimmed-args (min 3 (length trimmed-args)))) " ")))
        short)))

(define (display-title fields)
  (let* ((name (row-window-name fields))
         (command (row-command fields))
         (pane-title (row-pane-title fields)))
    (or (nonempty (row-custom-title fields))
        (nonempty (row-ai-title fields))
        (nonempty (row-locked-pane-title fields))
        (and (not (generic-title? pane-title command name)) pane-title)
        (and (not (shell-command? command)) (nonempty command))
        (nonempty name)
        command)))

(define (display-desc fields)
  (or (nonempty (row-custom-desc fields))
      (let* ((path (row-path fields))
             (command (row-command fields))
             (cmdline (shorten-argv (foreground-argv (row-pane-pid fields)) command))
             (path-label (basename-display path)))
        (cond
         ((and (nonempty cmdline) (not (string=? cmdline command)))
          (format #f "~a · ~a" path-label cmdline))
         ((nonempty path-label) path-label)
         (else "")))))

(define (format-pane-title* fields available-width)
  (let* ((idx (row-index fields))
         (title-text (display-title fields))
         (pane-idx (row-pane-index fields))
         (number (if (nonempty pane-idx) pane-idx idx))
         (number-part (format #f "~a " number))
         (label-width (max 1 (- available-width (string-width number-part))))
         (base (truncate-string title-text label-width)))
    (truncate-string (format #f "~a~a" number-part base)
                     available-width)))

(define (format-tab-title* window available-width)
  (match window
    ((_key session idx name _rep-fields panes)
     (let* ((count (length panes))
            (suffix (format #f " [~a]" count))
            (available (max 4 (- available-width
                                 (string-width idx)
                                 1
                                 (string-width suffix))))
            (base (truncate-string name available)))
       (truncate-string (format #f "~a ~a~a" idx base suffix)
                        available-width)))))

(define (emit-line text)
  "输出一行文本，填充到侧栏宽度、清除行尾残留、换行。"
  (let* ((w (sidebar-width))
         (text* (if (> (string-width text) w)
                    (truncate-string text w)
                    text)))
    (display (pad-string text* w))
    (display ansi-erase-line))   ;; 清除窗口缩窄时右侧的旧字符
  (newline))

(define (emit-styled-line row)
  (match row
    ((text _action color bold?)
     (when color (display color))
     (when bold? (display ansi-bold))
     (emit-line text)
     (when (or color bold?) (display ansi-reset)))
    ((text _action color)
     (when color (display color))
     (emit-line text)
     (when color (display ansi-reset)))
    ((text _action)
     (emit-line text))))

(define (center-text text width)
  (let* ((text* (truncate-string text width))
         (tw (string-width text*))
         (left (max 0 (quotient (- width tw) 2)))
         (right (max 0 (- width tw left))))
    (string-append (make-string left #\space) text* (make-string right #\space))))

;; === Grouping ===

(define (trim-trailing-slashes path)
  (let loop ((end (string-length path)))
    (cond
     ((<= end 1) (substring path 0 end))
     ((char=? (string-ref path (- end 1)) #\/) (loop (- end 1)))
     (else (substring path 0 end)))))

(define (parent-path path)
  (let* ((clean (trim-trailing-slashes path))
         (home (or (getenv "HOME") "")))
    (cond
     ((or (string=? clean "") (string=? clean "/")) "/")
     ((string=? clean home) home)
     (else
      (let ((idx (string-rindex clean #\/)))
        (cond
         ((not idx) ".")
         ((zero? idx) "/")
         (else (substring clean 0 idx))))))))

(define (basename-display path)
  (let* ((clean (trim-trailing-slashes path))
         (home (or (getenv "HOME") "")))
    (cond
     ((string=? clean "/") "/")
     ((string=? clean home) "~")
     (else
      (let ((idx (string-rindex clean #\/)))
        (if idx (substring clean (+ idx 1)) clean))))))

(define (path-group-key path)
  (let ((group-path (parent-path path)))
    (list (number->string (string-hash group-path) 16)
          (basename-display group-path)
          group-path)))

(define (window-key fields)
  (or (nonempty (row-window-id fields))
      (string-append (row-session fields) ":" (row-index fields))))

(define (window-objects panes)
  "Return ((window-key session index name representative-fields pane-fields) ...)."
  (let ((windows (make-hash-table))
        (order '()))
    (for-each
     (lambda (fields)
       (let ((key (window-key fields)))
         (unless (hash-ref windows key #f)
           (set! order (cons key order))
           (hash-set! windows key
                      (list (row-session fields)
                            (row-index fields)
                            (row-window-name fields)
                            fields
                            '())))
         (let* ((window (hash-ref windows key))
                (session (list-ref window 0))
                (idx (list-ref window 1))
                (name (list-ref window 2))
                (rep-fields (list-ref window 3))
                (window-panes (list-ref window 4))
                (rep* (if (row-pane-active? fields) fields rep-fields)))
           (hash-set! windows key
                      (list session idx name rep* (cons fields window-panes))))))
     panes)
    (map (lambda (key)
           (let ((window (hash-ref windows key)))
             (list key
                   (list-ref window 0)
                   (list-ref window 1)
                   (list-ref window 2)
                   (list-ref window 3)
                   (reverse (list-ref window 4)))))
         (reverse order))))

(define (group-windows panes)
  "Return ((group-key group-name (window-objects ...)) ...), preserving order."
  (let ((groups (make-hash-table))
        (order '()))
    (for-each
     (lambda (window)
       (match window
         ((_key _session _idx _name rep-fields _panes)
          (match (path-group-key (row-path rep-fields))
            ((group-key display _group-path)
             (unless (hash-ref groups group-key #f)
               (set! order (cons group-key order))
               (hash-set! groups group-key (list display '())))
             (let* ((group (hash-ref groups group-key))
                    (windows (cadr group)))
               (hash-set! groups group-key
                          (list display (cons window windows)))))))))
     (window-objects panes))
    (map (lambda (key)
           (let ((group (hash-ref groups key)))
             (list key (car group) (reverse (cadr group)))))
         (reverse order))))

(define (session-blocks panes)
  "Return ((session-name session-key (group ...)) ...), preserving order."
  (let ((sessions (make-hash-table))
        (order '()))
    (for-each
     (lambda (fields)
       (let ((session (row-session fields)))
         (unless (hash-ref sessions session #f)
           (set! order (cons session order))
           (hash-set! sessions session '()))
         (hash-set! sessions session (cons fields (hash-ref sessions session)))))
     panes)
    (map (lambda (session)
           (list session
                 (session-key session)
                 (group-windows (reverse (hash-ref sessions session)))))
         (reverse order))))

(define (active-session-first blocks current-session)
  "将当前会话块排到最前。CURRENT-SESSION 由调用方传入，避免重复查询 tmux。"
  (append (filter (lambda (block) (string=? (car block) current-session)) blocks)
          (filter (lambda (block) (not (string=? (car block) current-session))) blocks)))

;; === Layout ===

(define (make-row text action . style)
  (let ((color (if (null? style) #f (car style)))
        (bold? (if (or (null? style) (null? (cdr style))) #f (cadr style))))
    (list text action color bold?)))

(define (session-box-rows session skey collapsed? current?)
  (let* ((w (sidebar-width))
         (inner (max 4 (- w 2)))
         (color (if current? ansi-session-active ansi-session))
         (top (string-append "┌" (make-string inner #\─) "┐"))
         (middle (string-append "│" (center-text session inner) "│"))
         (bottom-icon (if collapsed? "▸" "▾"))
         (bottom (string-append "└─" bottom-icon
                                (make-string (max 0 (- w 4)) #\─)
                                "┘"))
         (action (list 'session skey)))
    (list (make-row top action color #t)
          (make-row middle action color #t)
          (make-row bottom action color #t))))

(define (group-row session group-key group-name count last? collapsed?)
  (let* ((w (sidebar-width))
         (prefix (if last? "  └─ " "  ├─ "))
         (icon (if collapsed? "▸ " "▾ "))
         (suffix (format #f " [~a]" count))
         (available (max 4 (- w
                              (string-width prefix)
                              (string-width icon)
                              (string-width suffix))))
         (label (truncate-string group-name available)))
    (make-row (string-append prefix icon label suffix)
              (list 'group (group-collapse-key session group-key))
              ansi-group
              #f)))

(define (tab-prefix group-last? last-window?)
  (string-append (if group-last? "     " "  │  ")
                 (if last-window? "└─ " "├─ ")))

(define (pane-prefix group-last? window-last? pane-last?)
  (string-append (if group-last? "     " "  │  ")
                 (if window-last? "   " "│  ")
                 (if pane-last? "└─ " "├─ ")))

(define (pane-desc-prefix group-last? window-last? pane-last?)
  (string-append (if group-last? "     " "  │  ")
                 (if window-last? "   " "│  ")
                 (if pane-last? "   " "│  ")))

(define (tab-row window current-session current-window group-last? last-window?)
  (match window
    ((_key session idx _name _rep-fields panes)
     (let* ((current? (and (string=? session current-session)
                           (string=? idx current-window)))
            (prefix (tab-prefix group-last? last-window?))
            (marker (if current? "● " "  "))
            (title-width (max 1 (- (sidebar-width)
                                   (string-width prefix)
                                   (string-width marker))))
            (title (format-tab-title* window title-width))
            (action (list 'window session idx))
            (style (if current? ansi-active #f)))
       (make-row (string-append prefix marker title)
                 action
                 style
                 current?)))))

(define (pane-row fields current-session current-window group-last? window-last? last-pane?)
  (let* ((session (row-session fields))
         (idx (row-index fields))
         (pane-idx (row-pane-index fields))
         (current? (and (string=? session current-session)
                        (string=? idx current-window)
                        (row-pane-active? fields)))
         (prefix (pane-prefix group-last? window-last? last-pane?))
         (desc-prefix (pane-desc-prefix group-last? window-last? last-pane?))
         (sw (sidebar-width))
         (marker (if current? "● " "  "))
         (title-width (max 1 (- sw
                                (string-width prefix)
                                (string-width marker))))
         (title (format-pane-title* fields title-width))
         (desc (truncate-string (display-desc fields) (max 4 (- sw (string-width desc-prefix)))))
         (action (list 'pane session idx pane-idx))
         (style (if current? ansi-active #f))
         (title-row (make-row (string-append prefix marker title) action style current?)))
    (if (nonempty desc)
        (list title-row
              (make-row (string-append desc-prefix desc) action ansi-desc #f))
        (list title-row))))

(define (window-rows window current-session current-window group-last? last-window?)
  (match window
    ((_key _session _idx _name _rep-fields panes)
     (let pane-loop ((ps panes)
                     (rows (list (tab-row window current-session current-window
                                          group-last? last-window?))))
       (if (null? ps)
           (reverse rows)
           (pane-loop (cdr ps)
                      (append (reverse
                               (pane-row (car ps)
                                         current-session
                                         current-window
                                         group-last?
                                         last-window?
                                         (null? (cdr ps))))
                              rows)))))))

(define (split-option-value str)
  "将逗号分隔的选项值拆分为列表，空值返回空列表。"
  (if (or (not str) (string-null? str))
      '()
      (string-split str #\,)))

(define (layout-rows-with-context blocks context-parts)
  (let* ((current-session (if (> (length context-parts) 0) (list-ref context-parts 0) ""))
         (current-window (if (> (length context-parts) 1) (list-ref context-parts 1) ""))
         (collapsed-sessions (split-option-value (if (> (length context-parts) 2) (list-ref context-parts 2) "")))
         (collapsed-groups (split-option-value (if (> (length context-parts) 3) (list-ref context-parts 3) ""))))
    (layout-rows* blocks current-session current-window collapsed-sessions collapsed-groups)))

(define (layout-rows* blocks current-session current-window collapsed-sessions collapsed-groups)
  "核心布局逻辑，接收预计算上下文参数。"
  (let block-loop ((bs blocks)
                   (rows '()))
    (if (null? bs)
        (reverse rows)
        (match (car bs)
          ((session skey groups)
           (let* ((session-collapsed? (member skey collapsed-sessions))
                  (current? (string=? session current-session))
                  (box-rows (session-box-rows session skey session-collapsed? current?))
                  (rows* (append (reverse box-rows) rows)))
             (if session-collapsed?
                 (block-loop (cdr bs)
                             (if (null? (cdr bs))
                                 rows*
                                 (cons (make-row "" #f) rows*)))
                 (let group-loop ((gs groups)
                                  (g-rows rows*))
                     (if (null? gs)
                         (block-loop (cdr bs)
                                     (if (null? (cdr bs))
                                         g-rows
                                         (cons (make-row "" #f) g-rows)))
                         (match (car gs)
                           ((group-key group-name windows)
                            (let* ((last-group? (null? (cdr gs)))
                                   (collapse-key (group-collapse-key session group-key))
                                   (group-collapsed? (member collapse-key collapsed-groups))
                                   (g-rows* (cons (group-row session group-key group-name
                                                             (length windows)
                                                             last-group?
                                                             group-collapsed?)
                                                  g-rows)))
                              (if group-collapsed?
                                  (group-loop (cdr gs) g-rows*)
                                  (let window-loop ((ws windows)
                                                    (w-rows g-rows*))
                                    (if (null? ws)
                                        (group-loop (cdr gs) w-rows)
                                        (window-loop (cdr ws)
                                                     (append (reverse (window-rows (car ws)
                                                                                  current-session
                                                                                  current-window
                                                                                  last-group?
                                                                                  (null? (cdr ws))))
                                                             w-rows)))))))))))))))))

(define (rows-actions rows)
  (let loop ((rs rows)
             (row 0)
             (actions '()))
    (if (null? rs)
        (reverse actions)
        (let ((action (cadar rs)))
          (loop (cdr rs)
                (+ row 1)
                (if action (cons (list row action) actions) actions))))))

;; === Render and Click ===

(define %current-context #f)
(define %current-panes '())
(define %current-actions '())
(define %last-screen #f)

(define (context-value index fallback)
  (if (and %current-context (> (length %current-context) index))
      (list-ref %current-context index)
      fallback))

(define (current-git-branch)
  (let ((session (context-value 0 ""))
        (window (context-value 1 "")))
    (let loop ((panes %current-panes)
               (fallback #f))
      (if (null? panes)
          (if fallback (or (read-git-head fallback) "") "")
          (let ((fields (car panes)))
            (if (and (string=? (row-session fields) session)
                     (string=? (row-index fields) window))
                (if (row-pane-active? fields)
                    (or (read-git-head (row-path fields)) "")
                    (loop (cdr panes) (or fallback (row-path fields))))
                (loop (cdr panes) fallback)))))))

(define (update-statusbar-branch!)
  (let ((branch (current-git-branch))
        (previous (context-value 6 "")))
    (unless (string=? branch previous)
      (tmux-cmd "set-option" "-w" "@status_git_branch" branch))))

(define (rows->screen rows)
  (call-with-output-string
   (lambda (port)
     (parameterize ((current-output-port port))
       (for-each emit-styled-line rows)))))

(define (refresh-state!)
  (let ((state (collect-state)))
    (when state
      (set! %current-context (car state))
      (set! %current-panes (cadr state)))
    (when %current-context
      (set-sidebar-width! (context-value 4 "0") (context-value 5 "32")))
    (update-statusbar-branch!)))

(define (current-rows)
  (if (or (not %current-context) (null? %current-panes))
      (list (make-row " [no tmux data]" #f ansi-dim #f))
      (let* ((session (context-value 0 ""))
             (blocks (active-session-first (session-blocks %current-panes) session)))
        (layout-rows-with-context blocks %current-context))))

(define (render-current! cursor-control?)
  (refresh-state!)
  (let* ((rows (current-rows))
         (screen (rows->screen rows)))
    (set! %current-actions (rows-actions rows))
    (when (or (not cursor-control?)
              (not %last-screen)
              (not (string=? screen %last-screen)))
      (when cursor-control? (display "\x1b[H"))
      (display screen)
      (when cursor-control? (display "\x1b[J"))
      (force-output)
      (set! %last-screen screen))))

(define (row-action row actions)
  (let ((found (find (lambda (entry) (= (car entry) row)) actions)))
    (and found (cadr found))))

(define (nearby-action row actions)
  (let loop ((candidates (list row (- row 1) (+ row 1))))
    (if (null? candidates)
        #f
        (or (row-action (car candidates) actions)
            (loop (cdr candidates))))))

(define (screen-row-candidates mouse-y pane-top)
  (let* ((local (- mouse-y pane-top))
         (local-prev (- local 1)))
    (delete-duplicates
     (filter (lambda (n) (>= n 0))
             (list local local-prev mouse-y (- mouse-y 1))))))

(define (switch-client-to client target)
  (if (nonempty client)
      (tmux-cmd "switch-client" "-c" client "-t" target)
      (tmux-cmd "switch-client" "-t" target)))

(define (handle-action action client)
  (when action
    (match action
      (('session skey)
       (toggle-list-value! "@sidebar_collapsed_sessions"
                           (context-value 2 "") skey))
      (('group gkey)
       (toggle-list-value! "@sidebar_collapsed_groups"
                           (context-value 3 "") gkey))
      (('window session idx)
       (switch-client-to client (string-append session ":" idx)))
      (('pane session idx pane-idx)
       (switch-client-to client (string-append session ":" idx))
       (when (nonempty pane-idx)
         (tmux-cmd "select-pane" "-t"
                   (string-append session ":" idx "." pane-idx))))
      (_ #f))))

(define (handle-click mouse-y pane-top client)
  (let ((action (let loop ((candidates (screen-row-candidates mouse-y pane-top)))
                   (if (null? candidates)
                       #f
                       (or (nearby-action (car candidates) %current-actions)
                           (loop (cdr candidates)))))))
    (handle-action action client)))

(define (toggle-current-group)
  (let ((current-session (context-value 0 ""))
        (current-window (context-value 1 "")))
    (let loop ((panes %current-panes))
      (unless (null? panes)
        (let* ((fields (car panes))
               (session (row-session fields))
               (idx (row-index fields))
               (path (row-path fields)))
          (if (and (string=? session current-session)
                   (string=? idx current-window))
              (match (path-group-key path)
                ((group-key _display _group-path)
                 (toggle-list-value! "@sidebar_collapsed_groups"
                                     (context-value 3 "")
                                     (group-collapse-key session group-key))))
              (loop (cdr panes))))))))

;; === FIFO daemon ===

(define (fifo-path)
  (let* ((pane (or (getenv "TMUX_PANE") "unknown"))
         (id (if (and (positive? (string-length pane))
                      (char=? (string-ref pane 0) #\%))
                 (substring pane 1)
                 pane)))
    (format #f "/tmp/tmux-sidebar-~a-~a.fifo" (getuid) id)))

(define (open-event-fifo)
  (let ((path (fifo-path)))
    (when (file-exists? path) (delete-file path))
    (mknod path 'fifo #o600 0)
    (cons path (open-file path "r+"))))

(define (handle-event line)
  (match (string-split line #\tab)
    (("refresh") #t)
    (("toggle-group") (toggle-current-group))
    (("click" mouse-y pane-top client)
     (let ((y (string->number mouse-y))
           (top (string->number pane-top)))
       (when (and y top) (handle-click y top client))))
    (_ #f)))

(define (drain-events port)
  (let loop ()
    (when (char-ready? port)
      (let ((line (read-line port)))
        (unless (eof-object? line)
          (handle-event line)
          (loop))))))

(define (run-daemon)
  (let* ((fifo (open-event-fifo))
         (path (car fifo))
         (port (cdr fifo))
         (cleaned? #f))
    (define (cleanup)
      (unless cleaned?
        (set! cleaned? #t)
        (false-if-exception (close port))
        (false-if-exception (delete-file path))
        (display "\x1b[?25h")
        (force-output)))
    (for-each
     (lambda (signal)
       (sigaction signal
                  (lambda (_)
                    (cleanup)
                    (primitive-exit 0))))
     (list SIGHUP SIGINT SIGTERM))
    (dynamic-wind
      (lambda ()
        (display "\x1b[?25l\x1b[2J\x1b[H")
        (force-output))
      (lambda ()
        (let loop ()
          (render-current! #t)
          (let ((readable (car (select (list port) '() '() 30))))
            (when (pair? readable) (drain-events port)))
          (loop)))
      cleanup)))

;; === Entry ===

(guard (ex (#t
            (format (current-error-port) "sidebar-render error: ~a~%" ex)
            (exit 1)))
  (let ((args (command-line)))
    (cond
     ((and (> (length args) 1) (string=? (cadr args) "daemon"))
      (run-daemon))
     ((and (> (length args) 1) (string=? (cadr args) "render"))
      (render-current! #f))
     ((and (> (length args) 1) (string=? (cadr args) "--as-library"))
      #t)
     (else
      (format (current-error-port) "usage: sidebar-render.scm daemon|render~%")
      (exit 2)))))
