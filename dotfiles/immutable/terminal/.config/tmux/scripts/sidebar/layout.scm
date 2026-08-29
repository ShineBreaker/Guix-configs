;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; sidebar/layout.scm — 折叠键派生、pane→window→group→session 聚合、
;; 布局行构造与带样式输出。纯计算（仅写 current-output-port），
;; 运行时状态机在主文件，输入处理在 input.scm。

(use-modules (ice-9 match))

;; === Keys ===

(define (session-key session)
  (string-append "s:" (number->string (string-hash session) 16)))

(define (group-collapse-key session group-key)
  (string-append "g:" (number->string (string-hash (string-append session ":" group-key)) 16)))

(define (display-title fields)
  (let* ([name (row-window-name fields)]
         [command (row-command fields)]
         [pane-title (row-pane-title fields)])
    (or (nonempty (row-custom-title fields))
        (nonempty (row-ai-title fields))
        (nonempty (row-locked-pane-title fields))
        (and (not (generic-title? pane-title command name)) pane-title)
        (and (not (shell-command? command)) (nonempty command))
        (nonempty name)
        command)))

(define (display-desc fields)
  (or (nonempty (row-custom-desc fields))
      (let* ([path (row-path fields)]
             [command (row-command fields)]
             [cmdline (shorten-argv (foreground-argv (row-pane-pid fields)) command)]
             [path-label (basename-display path)])
        (cond
         [(and (nonempty cmdline) (not (string=? cmdline command)))
          (format #f "~a · ~a" path-label cmdline)]
         [(nonempty path-label) path-label]
         [else ""]))))

(define (format-pane-title* fields available-width)
  (let* ([idx (row-index fields)]
         [title-text (display-title fields)]
         [pane-idx (row-pane-index fields)]
         [number (if (nonempty pane-idx) pane-idx idx)]
         [number-part (format #f "~a " number)]
         [label-width (max 1 (- available-width (string-width number-part)))]
         [base (truncate-string title-text label-width)])
    (truncate-string (format #f "~a~a" number-part base)
                     available-width)))

(define (format-tab-title* window available-width)
  (match window
    [(_key session idx name _rep-fields panes)
     (let* ([count (length panes)]
            [suffix (format #f " [~a]" count)]
            [available (max 4 (- available-width
                                 (string-width idx)
                                 1
                                 (string-width suffix)))]
            [base (truncate-string name available)])
       (truncate-string (format #f "~a ~a~a" idx base suffix)
                        available-width))]))

(define (emit-line text)
  "输出一行文本，填充到侧栏宽度、清除行尾残留、换行。"
  (let* ([w (sidebar-width)]
         [text* (if (> (string-width text) w)
                    (truncate-string text w)
                    text)])
    (display (pad-string text* w))
    (display ansi-erase-line))   ;; 清除窗口缩窄时右侧的旧字符
  (newline))

(define (emit-styled-line row cursor?)
  (define (emit text color bold?)
    (when cursor? (display ansi-reverse))
    (when color (display color))
    (when bold? (display ansi-bold))
    (emit-line text)
    (when (or cursor? color bold?) (display ansi-reset)))
  (match row
    [(text _action color bold?) (emit text color bold?)]
    [(text _action color) (emit text color #f)]
    [(text _action) (emit text #f #f)]))

(define (path-group-key path)
  (let ([group-path (parent-path path)])
    (list (number->string (string-hash group-path) 16)
          (basename-display group-path)
          group-path)))

(define (window-key fields)
  (or (nonempty (row-window-id fields))
      (string-append (row-session fields) ":" (row-index fields))))

(define (window-objects panes)
  "Return ((window-key session index name representative-fields pane-fields) ...)."
  (let ([windows (make-hash-table)]
        [order '()])
    (for-each
     (lambda (fields)
       (let ([key (window-key fields)])
         (unless (hash-ref windows key #f)
           (set! order (cons key order))
           (hash-set! windows key
                      (list (row-session fields)
                            (row-index fields)
                            (row-window-name fields)
                            fields
                            '())))
         (let* ([window (hash-ref windows key)]
                [session (list-ref window 0)]
                [idx (list-ref window 1)]
                [name (list-ref window 2)]
                [rep-fields (list-ref window 3)]
                [window-panes (list-ref window 4)]
                [rep* (if (row-pane-active? fields) fields rep-fields)])
           (hash-set! windows key
                      (list session idx name rep* (cons fields window-panes))))))
     panes)
    (map (lambda (key)
           (let ([window (hash-ref windows key)])
             (list key
                   (list-ref window 0)
                   (list-ref window 1)
                   (list-ref window 2)
                   (list-ref window 3)
                   (reverse (list-ref window 4)))))
         (reverse order))))

(define (group-windows panes)
  "Return ((group-key group-name (window-objects ...)) ...), preserving order."
  (let ([groups (make-hash-table)]
        [order '()])
    (for-each
     (lambda (window)
       (match window
         [(_key _session _idx _name rep-fields _panes)
          (match (path-group-key (row-path rep-fields))
            [(group-key display _group-path)
             (unless (hash-ref groups group-key #f)
               (set! order (cons group-key order))
               (hash-set! groups group-key (list display '())))
             (let* ([group (hash-ref groups group-key)]
                    [windows (cadr group)])
               (hash-set! groups group-key
                          (list display (cons window windows))))])]))
     (window-objects panes))
    (map (lambda (key)
           (let ([group (hash-ref groups key)])
             (list key (car group) (reverse (cadr group)))))
         (reverse order))))

(define (session-blocks panes)
  "Return ((session-name session-key (group ...)) ...), preserving order."
  (let ([sessions (make-hash-table)]
        [order '()])
    (for-each
     (lambda (fields)
       (let ([session (row-session fields)])
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
  (let ([color (if (null? style) #f (car style))]
        [bold? (if (or (null? style) (null? (cdr style))) #f (cadr style))])
    (list text action color bold?)))

(define (session-box-rows session skey collapsed? current?)
  (let* ([w (sidebar-width)]
         [inner (max 4 (- w 2))]
         [color (if current? ansi-session-active ansi-session)]
         [top (string-append "┌" (make-string inner #\─) "┐")]
         [middle (string-append "│" (center-text session inner) "│")]
         [bottom-icon (if collapsed? "▸" "▾")]
         [bottom (string-append "└─" bottom-icon
                                (make-string (max 0 (- w 4)) #\─)
                                "┘")]
         [action (list 'session skey)])
    (list (make-row top action color #t)
          (make-row middle action color #t)
          (make-row bottom action color #t))))

(define (group-row session group-key group-name count last? collapsed?)
  (let* ([w (sidebar-width)]
         [prefix (if last? "  └─ " "  ├─ ")]
         [icon (if collapsed? "▸ " "▾ ")]
         [suffix (format #f " [~a]" count)]
         [available (max 4 (- w
                              (string-width prefix)
                              (string-width icon)
                              (string-width suffix)))]
         [label (truncate-string group-name available)])
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
    [(_key session idx _name _rep-fields panes)
     (let* ([current? (and (string=? session current-session)
                           (string=? idx current-window))]
            [prefix (tab-prefix group-last? last-window?)]
            [marker (if current? "● " "  ")]
            [title-width (max 1 (- (sidebar-width)
                                   (string-width prefix)
                                   (string-width marker)))]
            [title (format-tab-title* window title-width)]
            [action (list 'window session idx)]
            [style (if current? ansi-active #f)])
       (make-row (string-append prefix marker title)
                 action
                 style
                 current?))]))

(define (pane-row fields current-session current-window group-last? window-last? last-pane?)
  (let* ([session (row-session fields)]
         [idx (row-index fields)]
         [pane-idx (row-pane-index fields)]
         [current? (and (string=? session current-session)
                        (string=? idx current-window)
                        (row-pane-active? fields))]
         [prefix (pane-prefix group-last? window-last? last-pane?)]
         [desc-prefix (pane-desc-prefix group-last? window-last? last-pane?)]
         [sw (sidebar-width)]
         [marker (if current? "● " "  ")]
         [title-width (max 1 (- sw
                                (string-width prefix)
                                (string-width marker)))]
         [title (format-pane-title* fields title-width)]
         [desc (truncate-string (display-desc fields) (max 4 (- sw (string-width desc-prefix))))]
         [action (list 'pane session idx pane-idx)]
         [style (if current? ansi-active #f)]
         [title-row (make-row (string-append prefix marker title) action style current?)])
    (if (nonempty desc)
        (list title-row
              (make-row (string-append desc-prefix desc) action ansi-desc #f))
        (list title-row))))

(define (window-rows window current-session current-window group-last? last-window?)
  (match window
    [(_key _session _idx _name _rep-fields panes)
     (let pane-loop ([ps panes]
                     [rows (list (tab-row window current-session current-window
                                          group-last? last-window?))])
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
                              rows))))]))

(define (split-option-value str)
  "将逗号分隔的选项值拆分为列表，空值返回空列表。"
  (if (or (not str) (string-null? str))
      '()
      (string-split str #\,)))

(define (layout-rows-with-context blocks context-parts)
  (let* ([current-session (if (> (length context-parts) 0) (list-ref context-parts 0) "")]
         [current-window (if (> (length context-parts) 1) (list-ref context-parts 1) "")]
         [collapsed-sessions (split-option-value (if (> (length context-parts) 2) (list-ref context-parts 2) ""))]
         [collapsed-groups (split-option-value (if (> (length context-parts) 3) (list-ref context-parts 3) ""))])
    (layout-rows* blocks current-session current-window collapsed-sessions collapsed-groups)))

(define (layout-rows* blocks current-session current-window collapsed-sessions collapsed-groups)
  "核心布局逻辑，接收预计算上下文参数。"
  (let block-loop ([bs blocks]
                   [rows '()])
    (if (null? bs)
        (reverse rows)
        (match (car bs)
          [(session skey groups)
           (let* ([session-collapsed? (member skey collapsed-sessions)]
                  [current? (string=? session current-session)]
                  [box-rows (session-box-rows session skey session-collapsed? current?)]
                  [rows* (append (reverse box-rows) rows)])
             (if session-collapsed?
                 (block-loop (cdr bs)
                             (if (null? (cdr bs))
                                 rows*
                                 (cons (make-row "" #f) rows*)))
                 (let group-loop ([gs groups]
                                  [g-rows rows*])
                     (if (null? gs)
                         (block-loop (cdr bs)
                                     (if (null? (cdr bs))
                                         g-rows
                                         (cons (make-row "" #f) g-rows)))
                         (match (car gs)
                           [(group-key group-name windows)
                            (let* ([last-group? (null? (cdr gs))]
                                   [collapse-key (group-collapse-key session group-key)]
                                   [group-collapsed? (member collapse-key collapsed-groups)]
                                   [g-rows* (cons (group-row session group-key group-name
                                                             (length windows)
                                                             last-group?
                                                             group-collapsed?)
                                                  g-rows)])
                              (if group-collapsed?
                                  (group-loop (cdr gs) g-rows*)
                                  (let window-loop ([ws windows]
                                                    [w-rows g-rows*])
                                    (if (null? ws)
                                        (group-loop (cdr gs) w-rows)
                                        (window-loop (cdr ws)
                                                     (append (reverse (window-rows (car ws)
                                                                                  current-session
                                                                                  current-window
                                                                                  last-group?
                                                                                  (null? (cdr ws))))
                                                             w-rows))))))])))))]))))

(define (rows-actions rows)
  (let loop ([rs rows]
             [row 0]
             [actions '()])
    (if (null? rs)
        (reverse actions)
        (let ([action (cadar rs)])
          (loop (cdr rs)
                (+ row 1)
                (if action (cons (list row action) actions) actions))))))
