#!/usr/bin/env guile
!#

;; sidebar-render.scm — tmux 侧边栏数据采集与渲染引擎
;;
;; 核心职责：
;;   1. render-if-changed: 采集窗口数据 → 渲染为终端文本 → 输出到侧栏 pane
;;   2. click: 处理鼠标点击事件（选择会话/窗口/折叠组/执行操作）
;;   3. git: 采集所有工作目录的 git branch 信息并写缓存
;;   4. data: 仅采集并写缓存（供 status-left 等引用）
;;   5. toggle-group: 切换窗口组折叠状态
;;
;; 渲染管线（render-if-changed）：
;;   1. 从 tmux 采集所有 pane 数据（collect-window-data）
;;   2. 按 session → group-by-path → window → pane 组织层级树
;;   3. 生成带 ANSI 颜色的文本，输出到侧栏 pane
;;   4. render-if-changed：仅在数据确实发生变化时才输出（防抖动）
;;     通过将当前渲染 hash 写入缓存与上次对比实现
;;
;; 数据采集层：
;;   - 实时优先：对每个 pane 的路径执行 git rev-parse（timeout 2s）
;;   - 缓存 fallback：git-branches.cache 保存上次采集结果
;;   - 采集后写缓存，pane-loop 读取缓存的 git 数据（避免重复 git 调用）
;;
;; 状态管理（tmux 选项）：
;;   - @sidebar_collapsed_groups: 全局逗号分隔列表，记录已折叠的组 key
;;   - session/window 键通过 hash 生成，避免特殊字符转义问题

(load (string-append (getenv "HOME") "/.config/tmux/scripts/tmux-helpers.scm"))

(use-modules (ice-9 match)
             (ice-9 popen)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-34))

;; === ANSI ===

(define ansi-erase-line "\x1b[K")
(define ansi-reset "\x1b[0m")
(define ansi-bold "\x1b[1m")
(define ansi-dim "\x1b[2m")
(define ansi-tree "\x1b[90m")
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
(define %sidebar-width-value #f)
(define %window-title-width-value #f)

(define (%compute-sidebar-width)
  "实际计算侧栏可绘制宽度。优先取 pane 宽度，回退到 @sidebar_width 选项。"
  (let* ((tmux-pane (getenv "TMUX_PANE"))
         (pane-width (if (and tmux-pane (not (string=? tmux-pane "")))
                         (string->positive-integer
                          (cdr (tmux-cmd "display-message" "-p" "-t" tmux-pane "#{pane_width}"))
                          0)
                         0))
         (option-width (string->positive-integer (tmux-get-option "@sidebar_width") 32))
         (width (if (> pane-width 0) pane-width option-width)))
    (max 18 (- width 1))))

(define (sidebar-width)
  "返回侧栏可绘制宽度（进程内缓存）。最后一列不用以避免换行。"
  (or %sidebar-width-value
      (let ((w (%compute-sidebar-width)))
        (set! %sidebar-width-value w)
        w)))

(define (window-title-width)
  "返回窗口标题区域最大宽度（进程内缓存）。"
  (or %window-title-width-value
      (let ((w (max 6 (- (sidebar-width) 8))))
        (set! %window-title-width-value w)
        w)))

;; === Text ===

(define (parse-cache-line line)
  (string-split line #\tab))

(define (valid-data-line? line)
  (let ((len (length (parse-cache-line line))))
    (or (= len 7) (>= len 18))))

(define (field fields index fallback)
  (if (> (length fields) index)
      (list-ref fields index)
      fallback))

(define (row-session fields) (field fields 0 ""))
(define (row-index fields) (field fields 1 ""))
(define (row-window-id fields) (if (>= (length fields) 18) (field fields 2 "") ""))
(define (row-window-name fields) (if (>= (length fields) 18) (field fields 3 "") (field fields 2 "")))
(define (row-path fields) (if (>= (length fields) 18) (field fields 4 "") (field fields 3 "")))
(define (row-command fields) (if (>= (length fields) 18) (field fields 5 "") (field fields 4 "")))
(define (row-activity fields) (if (>= (length fields) 18) (field fields 6 "") (field fields 5 "")))
(define (row-pane-title fields) (if (>= (length fields) 18) (field fields 9 "") ""))
(define (row-pane-pid fields) (if (>= (length fields) 18) (field fields 10 "") ""))
(define (row-pane-index fields) (if (>= (length fields) 18) (field fields 11 "") ""))
(define (row-ai-title fields) (if (>= (length fields) 18) (field fields 13 "") ""))
(define (row-custom-title fields) (if (>= (length fields) 18) (field fields 14 "") ""))
(define (row-custom-desc fields) (if (>= (length fields) 18) (field fields 15 "") ""))
(define (row-locked-pane-title fields) (if (>= (length fields) 18) (field fields 16 "") ""))
(define (row-window-panes fields) (if (>= (length fields) 18) (field fields 17 "1") "1"))
(define (row-pane-active? fields) (string=? (if (>= (length fields) 18) (field fields 8 "") "") "1"))

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

(define (option-list name)
  (let ((value (tmux-get-option name)))
    (if (and value (not (string=? value "")))
        (string-split value #\,)
        '())))

(define (set-option-list! name values)
  (tmux-cmd "set" "-g" name (string-join values ",")))

(define (toggle-list-value! option key)
  (let ((values (option-list option)))
    (if (member key values)
        (set-option-list! option (delete key values))
        (set-option-list! option (cons key values)))))

(define (session-key session)
  (string-append "s:" (number->string (string-hash session) 16)))

(define (group-collapse-key session group-key)
  (string-append "g:" (number->string (string-hash (string-append session ":" group-key)) 16)))

(define (split-data data)
  (if (and data (not (string=? data "")))
      (filter valid-data-line?
              (filter (lambda (line) (not (string=? line "")))
                      (string-split data #\newline)))
      '()))

(define (read-git-branch session window)
  (let ((cache (read-cache "git-branches.cache")))
    (if (and cache (not (string=? cache "")))
        (let loop ((lines (string-split cache #\newline)))
          (if (null? lines)
              #f
              (let* ((line (car lines))
                     (space-idx (string-index line #\space)))
                (if (and space-idx
                         (string=? (string-take line space-idx)
                                   (format #f "~a:~a" session window)))
                    (string-drop line (+ space-idx 1))
                    (loop (cdr lines))))))
        #f)))

(define (run/read . args)
  (let* ((port (apply open-pipe* OPEN_READ args))
         (output (string-trim-both (read-string port)))
         (status (close-pipe port)))
    (and (zero? status) output)))

(define (realpath* path)
  (run/read "timeout" "2" "realpath" "--" path))

(define (path-prefix-or-equal? parent child)
  (or (string=? parent child)
      (string-prefix? (string-append parent "/") child)))

(define (directory-path? path)
  (false-if-exception (eq? (stat:type (stat path)) 'directory)))

(define (hex-char? c)
  (or (char-numeric? c)
      (and (char>=? c #\a) (char<=? c #\f))
      (and (char>=? c #\A) (char<=? c #\F))))

(define (read-git-head path)
  (let ((git-path (string-append path "/.git")))
    (cond
     ((and (file-exists? git-path) (not (directory-path? git-path)))
      (let ((branch (run/read "timeout" "2" "git" "-C" path
                              "rev-parse" "--abbrev-ref" "HEAD")))
        (and branch (not (string-null? branch)) branch)))
     ((and (file-exists? git-path) (directory-path? git-path))
      (let ((head-path (string-append git-path "/HEAD")))
        (and (file-exists? head-path)
             (let ((content (string-trim-both
                             (call-with-input-file head-path read-string))))
               (cond
                ((string-prefix? "ref: refs/heads/" content)
                 (let ((branch (string-drop content (string-length "ref: refs/heads/"))))
                   (and (not (string-null? branch)) branch)))
                ((and (= (string-length content) 40)
                      (string-every hex-char? content))
                 (substring content 0 7))
                (else #f))))))
     (else #f))))

(define (safe-git-path? pane-path)
  (let ((git-path (string-append pane-path "/.git")))
    (and (file-exists? git-path)
         (or (not (directory-path? git-path))
             (let ((real-pane (realpath* pane-path))
                   (real-git (realpath* git-path)))
               (and real-pane real-git
                    (path-prefix-or-equal? real-pane real-git)))))))

(define (process-cmdline pid)
  (let ((file (string-append "/proc/" pid "/cmdline")))
    (and (file-exists? file)
         (let* ((raw (call-with-input-file file read-string))
                (chars (map (lambda (c) (if (char=? c #\nul) #\space c))
                            (string->list raw)))
                (line (string-trim-both (list->string chars))))
           (and (not (string-null? line)) line)))))

(define (child-pids pid)
  (let ((file (string-append "/proc/" pid "/task/" pid "/children")))
    (if (file-exists? file)
        (let ((raw (string-trim-both (call-with-input-file file read-string))))
          (if (string-null? raw)
              '()
              (string-split raw #\space)))
        '())))

(define (foreground-cmdline pid)
  (let loop ((queue (if (nonempty pid) (list pid) '()))
             (last #f)
             (seen '()))
    (if (null? queue)
        last
        (let* ((pid* (car queue))
               (rest (cdr queue)))
          (if (member pid* seen)
              (loop rest last seen)
              (let ((cmd (process-cmdline pid*))
                    (children (child-pids pid*)))
                (loop (append children rest)
                      (or cmd last)
                      (cons pid* seen))))))))

(define (shorten-cmdline cmdline command)
  (if (not (nonempty cmdline))
      ""
      (let* ((parts (string-split cmdline #\space))
             (program (if (null? parts) command (basename-of-path (car parts))))
             (args (if (null? parts) '() (cdr parts)))
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
             (cmdline (shorten-cmdline (foreground-cmdline (row-pane-pid fields)) command))
             (path-label (basename-display path)))
        (cond
         ((and (nonempty cmdline) (not (string=? cmdline command)))
          (format #f "~a · ~a" path-label cmdline))
         ((nonempty path-label) path-label)
         (else "")))))

(define (format-pane-title fields)
  (format-pane-title* fields (window-title-width)))

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

(define (format-tab-title window)
  (format-tab-title* window (window-title-width)))

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

(define (window-objects lines)
  "Return ((window-key session index name representative-fields pane-lines) ...)."
  (let ((windows (make-hash-table))
        (order '()))
    (for-each
     (lambda (line)
       (let* ((fields (parse-cache-line line))
              (key (window-key fields)))
         (unless (hash-ref windows key #f)
           (set! order (append order (list key)))
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
                (panes (list-ref window 4))
                (rep* (if (row-pane-active? fields) fields rep-fields)))
           (hash-set! windows key
                      (list session idx name rep* (append panes (list line)))))))
     lines)
    (map (lambda (key)
           (let ((window (hash-ref windows key)))
             (list key
                   (list-ref window 0)
                   (list-ref window 1)
                   (list-ref window 2)
                   (list-ref window 3)
                   (list-ref window 4))))
         order)))

(define (group-windows lines)
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
               (set! order (append order (list group-key)))
               (hash-set! groups group-key (list display '())))
             (let* ((group (hash-ref groups group-key))
                    (windows (cadr group)))
               (hash-set! groups group-key
                          (list display (append windows (list window))))))))))
     (window-objects lines))
    (map (lambda (key)
           (let ((group (hash-ref groups key)))
             (list key (car group) (cadr group))))
         order)))

(define (session-blocks lines)
  "Return ((session-name session-key (group ...)) ...), preserving order."
  (let ((sessions (make-hash-table))
        (order '()))
    (for-each
     (lambda (line)
       (let ((session (row-session (parse-cache-line line))))
         (unless (hash-ref sessions session #f)
           (set! order (append order (list session)))
           (hash-set! sessions session '()))
         (hash-set! sessions session (append (hash-ref sessions session) (list line)))))
     lines)
    (map (lambda (session)
           (list session (session-key session) (group-windows (hash-ref sessions session))))
         order)))

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

(define (pane-row line current-session current-window group-last? window-last? last-pane?)
  (let* ((fields (parse-cache-line line))
         (session (row-session fields))
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
                     (pane-index 0)
                     (rows (list (tab-row window current-session current-window
                                           group-last? last-window?))))
       (if (null? ps)
           rows
           (pane-loop (cdr ps)
                      (+ pane-index 1)
                      (append rows
                              (pane-row (car ps)
                                        current-session
                                        current-window
                                        group-last?
                                        last-window?
                                        (= pane-index (- (length panes) 1))))))))))

(define (split-option-value str)
  "将逗号分隔的选项值拆分为列表，空值返回空列表。"
  (if (or (not str) (string-null? str))
      '()
      (string-split str #\,)))

(define (layout-rows-with-context blocks context-parts)
  ;; 使用预缓存上下文渲染，零 tmux 调用。
  (let* ((current-session (if (> (length context-parts) 0) (list-ref context-parts 0) ""))
         (current-window (if (> (length context-parts) 1) (list-ref context-parts 1) ""))
         (collapsed-sessions (split-option-value (if (> (length context-parts) 2) (list-ref context-parts 2) "")))
         (collapsed-groups (split-option-value (if (> (length context-parts) 3) (list-ref context-parts 3) ""))))
    (layout-rows* blocks current-session current-window collapsed-sessions collapsed-groups)))

(define (layout-rows blocks)
  ;; 单次 tmux 调用获取渲染所需的 4 项上下文（4 → 1 次 tmux 调用）
  (let* ((raw-info (tmux-display "#{session_name}\t#{window_index}\t#{@sidebar_collapsed_sessions}\t#{@sidebar_collapsed_groups}"))
         (parts (string-split raw-info #\tab))
         (current-session (list-ref parts 0))
         (current-window (list-ref parts 1))
         (collapsed-sessions (split-option-value (if (> (length parts) 2) (list-ref parts 2) "")))
         (collapsed-groups (split-option-value (if (> (length parts) 3) (list-ref parts 3) ""))))
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
                 (let ((group-count (length groups)))
                   (let group-loop ((gs groups)
                                    (index 0)
                                    (g-rows rows*))
                     (if (null? gs)
                         (block-loop (cdr bs)
                                     (if (null? (cdr bs))
                                         g-rows
                                         (cons (make-row "" #f) g-rows)))
                         (match (car gs)
                           ((group-key group-name windows)
                            (let* ((last-group? (= index (- group-count 1)))
                                   (collapse-key (group-collapse-key session group-key))
                                   (group-collapsed? (member collapse-key collapsed-groups))
                                   (g-rows* (cons (group-row session group-key group-name
                                                             (length windows)
                                                             last-group?
                                                             group-collapsed?)
                                                  g-rows)))
                              (if group-collapsed?
                                  (group-loop (cdr gs) (+ index 1) g-rows*)
                                  (let window-loop ((ws windows)
                                                    (w-index 0)
                                                    (w-rows g-rows*))
                                    (if (null? ws)
                                        (group-loop (cdr gs) (+ index 1) w-rows)
                                        (window-loop (cdr ws)
                                                     (+ w-index 1)
                                                     (append (reverse (window-rows (car ws)
                                                                                  current-session
                                                                                  current-window
                                                                                  last-group?
                                                                                  (= w-index (- (length windows) 1))))
                                                             w-rows))))))))))))))))))

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

(define (cache-lines)
  (split-data (read-cache "sidebar-data.cache")))

(define (fresh-lines)
  (split-data (collect-window-data)))

(define (data-lines)
  (let ((fresh (fresh-lines)))
    (if (null? fresh)
        (cache-lines)
        (let ((joined (string-join fresh "\n")))
          (write-cache "sidebar-data.cache" joined)
          (write-cache "sidebar-data.hash"
                       (number->string (modulo (string-hash joined) 1000000000) 16))
          fresh))))

(define (refresh-data!)
  (let ((data (collect-window-data)))
    (write-cache "sidebar-data.cache" data)
    (write-cache "sidebar-data.hash"
                 (number->string (modulo (string-hash data) 1000000000) 16))
    data))

(define (collect-git-info lines)
  (filter-map
   (lambda (line)
     (let* ((fields (parse-cache-line line))
            (session (row-session fields))
            (window (row-index fields))
            (pane-path (row-path fields))
            (branch (and (safe-git-path? pane-path)
                         (read-git-head pane-path))))
       (and branch
            (string-append session ":" window " " branch))))
   lines))

(define (refresh-git!)
  (let* ((lines (cache-lines))
         (info (collect-git-info lines)))
    (write-cache "git-branches.cache" (string-join info "\n"))))

;; 渲染时缓存的行号→动作映射，供点击处理时直接读取，跳过 layout 重计算。
(define (save-actions-cache! actions)
  "将行号→动作映射写入缓存文件。"
  (false-if-exception
   (call-with-output-file (cache-file "sidebar-actions.cache")
     (lambda (port) (write actions port)))))

(define (load-actions-cache)
  "从缓存加载行号→动作映射，缓存不可用时返回 #f。"
  (let ((file (cache-file "sidebar-actions.cache")))
    (and (file-exists? file)
         (false-if-exception
          (call-with-input-file file read)))))

(define (update-statusbar-options! current-session current-window lines)
  "更新状态栏窗口级选项（@status_git_branch）。使用 -w 窗口级选项，
避免多个 session 的 pane-loop 竞争覆盖同一个全局变量。"
  (let loop ((ls lines))
    (unless (null? ls)
      (let* ((fields (parse-cache-line (car ls)))
             (session (row-session fields))
             (idx (row-index fields))
             (path (row-path fields))
             (active? (row-pane-active? fields)))
        (if (and (string=? session current-session)
                 (string=? idx current-window)
                 active?)
            (let ((branch (and (safe-git-path? path) (read-git-head path))))
              (tmux-cmd "set-option" "-w" "@status_git_branch"
                        (if branch branch "")))
            (loop (cdr ls)))))))

(define (render-if-changed)
  "采集数据并渲染输出。单次 Guile 调用完成采集+渲染，避免双重启动开销。
同时写入缓存供其他命令（click、toggle-group 等）使用。"
  (let* ((data (collect-window-data))
         (new-hash (number->string (modulo (string-hash data) 1000000000) 16)))
    (write-cache "sidebar-data.cache" data)
    (write-cache "sidebar-data.hash" new-hash)
    (let ((lines (split-data data)))
      (if (null? lines)
          (emit-styled-line (make-row " [no tmux data]" #f ansi-dim #f))
          (let* ((raw-info (tmux-display "#{session_name}\t#{window_index}"))
                 (ctx (string-split raw-info #\tab))
                 (current-session (list-ref ctx 0))
                 (current-window (if (> (length ctx) 1) (list-ref ctx 1) "0"))
                 (rows (layout-rows-with-context
                        (session-blocks lines)
                        (append ctx
                                (list (or (tmux-get-option "@sidebar_collapsed_sessions") "")
                                      (or (tmux-get-option "@sidebar_collapsed_groups") ""))))))
            (update-statusbar-options! current-session current-window lines)
            (save-actions-cache! (rows-actions rows))
            (for-each emit-styled-line rows))))))

(define (render-to-stdout)
  "从缓存渲染，不重新采集数据。实时获取 context 以避免多窗口竞争。"
  (let ((lines (cache-lines)))
    (if (null? lines)
        (emit-styled-line (make-row " [no tmux data]" #f ansi-dim #f))
        (let* ((rows (layout-rows (session-blocks lines)))
               (actions (rows-actions rows)))
          (save-actions-cache! actions)
          (for-each emit-styled-line rows)))))

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

(define (signal-sidebar-pane pane-id)
  (when (and pane-id (not (string=? pane-id "")))
    (let* ((pid-text (cdr (tmux-cmd "display-message" "-p" "-t" pane-id "#{pane_pid}")))
           (pid (and pid-text (string->number pid-text))))
      (when pid
        (false-if-exception (kill pid SIGUSR1))))))

(define (handle-action action sidebar-pane)
  (when action
    ;; window 和 pane 都需要 current-session，提前获取一次
    (let ((current-session (tmux-display "#{session_name}")))
      (match action
        (('session skey)
         (toggle-list-value! "@sidebar_collapsed_sessions" skey)
         (signal-sidebar-pane sidebar-pane))
        (('group gkey)
         (toggle-list-value! "@sidebar_collapsed_groups" gkey)
         (signal-sidebar-pane sidebar-pane))
        (('window session idx)
         (if (string=? session current-session)
             (tmux-cmd "select-window" "-t" (string-append ":" idx))
             (tmux-cmd "switch-client" "-t" (string-append session ":" idx)))
         (signal-sidebar-pane sidebar-pane))
        (('pane session idx pane-idx)
         (if (string=? session current-session)
             (tmux-cmd "select-window" "-t" (string-append ":" idx))
             (tmux-cmd "switch-client" "-t" (string-append session ":" idx)))
         (when (nonempty pane-idx)
           (tmux-cmd "select-pane" "-t" (string-append session ":" idx "." pane-idx)))
         (signal-sidebar-pane sidebar-pane))
        (_ #f)))))

(define (handle-click mouse-y pane-top sidebar-pane)
  ;; 优先使用渲染时缓存的 actions 映射，避免重新计算 layout
  (let* ((actions (or (load-actions-cache)
                      (rows-actions (layout-rows (session-blocks (cache-lines))))))
         (action (let loop ((candidates (screen-row-candidates mouse-y pane-top)))
                   (if (null? candidates)
                       #f
                       (or (nearby-action (car candidates) actions)
                           (loop (cdr candidates)))))))
    (handle-action action sidebar-pane)))

(define (toggle-current-group)
  ;; 合并 session + window 为单次 tmux 调用
  (let* ((raw-info (tmux-display "#{session_name}\t#{window_index}"))
         (parts (string-split raw-info #\tab))
         (current-session (list-ref parts 0))
         (current-window (if (> (length parts) 1) (list-ref parts 1) "0")))
    (let loop ((lines (cache-lines)))
      (unless (null? lines)
        (let* ((fields (parse-cache-line (car lines)))
               (session (row-session fields))
               (idx (row-index fields))
               (path (row-path fields)))
          (if (and (string=? session current-session)
                   (string=? idx current-window))
              (match (path-group-key path)
                ((group-key _display _group-path)
                 (toggle-list-value! "@sidebar_collapsed_groups"
                                     (group-collapse-key session group-key))))
              (loop (cdr lines))))))))

(define (set-window-text! option args)
  (let ((text (string-trim-both (string-join args " "))))
    (if (string-null? text)
        (tmux-cmd "set-option" "-w" "-u" option)
        (tmux-cmd "set-option" "-w" option text))))

;; === Entry ===

(guard (ex (#t
            (format (current-error-port) "sidebar-render error: ~a~%" ex)
            (exit 1)))
  (require-tmux-version)
  (let ((args (command-line)))
    (cond
     ((and (> (length args) 1) (string=? (cadr args) "data"))
      (refresh-data!))
     ((and (> (length args) 1) (string=? (cadr args) "git"))
      (refresh-data!)
      (refresh-git!))
     ((and (> (length args) 1) (string=? (cadr args) "set-title"))
      (set-window-text! "@sidebar_window_title" (cddr args))
      (system "~/.config/tmux/scripts/sidebar-toggle signal"))
     ((and (> (length args) 1) (string=? (cadr args) "set-desc"))
      (set-window-text! "@sidebar_window_desc" (cddr args))
      (system "~/.config/tmux/scripts/sidebar-toggle signal"))
     ((and (> (length args) 1) (string=? (cadr args) "clear-title"))
      (tmux-cmd "set-option" "-w" "-u" "@sidebar_window_title")
      (tmux-cmd "set-option" "-w" "-u" "@sidebar_window_desc")
      (system "~/.config/tmux/scripts/sidebar-toggle signal"))
     ((and (> (length args) 1) (string=? (cadr args) "toggle-group"))
      (toggle-current-group)
      (system "~/.config/tmux/scripts/sidebar-toggle signal"))
     ((and (> (length args) 3) (string=? (cadr args) "click"))
      (let ((mouse-y (string->number (caddr args)))
            (pane-top (string->number (cadddr args)))
            (sidebar-pane (if (> (length args) 4) (list-ref args 4) #f)))
        (when (and mouse-y pane-top)
          (handle-click mouse-y pane-top sidebar-pane))))
     ((and (> (length args) 1) (string=? (cadr args) "render-if-changed"))
      (render-if-changed))
     ((and (> (length args) 1) (string=? (cadr args) "--as-library"))
      #t)
     (else
      (render-to-stdout)))))
