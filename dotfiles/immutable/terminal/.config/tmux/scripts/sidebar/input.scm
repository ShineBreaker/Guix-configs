;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; sidebar/input.scm — 键盘光标导航、按键解析（cbreak）与 FIFO 事件
;; 循环。依赖主文件的渲染状态机（handle-action/render-current! 等），
;; 均为运行期调用，load 顺序无要求。

(use-modules (ice-9 match) (ice-9 ftw) (srfi srfi-1))

;; === Keyboard navigation ===

;; 光标只在侧栏 pane 聚焦（pane_active=1）时显示；失焦时位置保留，
;; 再次聚焦回到原条目。侧栏 pane 自身的 active 存于 context 第 8 项。
(define (cursor-focused?)
  (string=? (context-value 7 "0") "1"))

(define (find-current-row actions)
  "当前 window/pane 对应的行号，作为光标初始化落点。"
  (let ([session (context-value 0 "")]
        [idx (context-value 1 "")])
    (let loop ([entries actions])
      (if (null? entries)
          #f
          (match (cadar entries)
            [('window s i)
             (if (and (string=? s session) (string=? i idx))
                 (caar entries) (loop (cdr entries)))]
            [('pane s i _pane-idx)
             (if (and (string=? s session) (string=? i idx))
                 (caar entries) (loop (cdr entries)))]
            [_ (loop (cdr entries))])))))

(define (resolve-cursor actions)
  (cond
   [(not (cursor-focused?)) #f]
   [(and %cursor-row (row-action %cursor-row actions)) %cursor-row]
   [else (or (find-current-row actions)
             (and (pair? actions) (caar actions)))]))

(define (cursor-move delta)
  "在有 action 的行之间移动（跳过空行与纯装饰行），DELTA 为 ±1。"
  (let ([rows (map car %current-actions)])
    (when (pair? rows)
      (let* ([current (or %cursor-row (car rows))]
             [next (if (positive? delta)
                       (find (lambda (r) (> r current)) rows)
                       (find (lambda (r) (< r current)) (reverse rows)))])
        (when next (set! %cursor-row next))))))

(define (cursor-action)
  (and %cursor-row (row-action %cursor-row %current-actions)))

(define (action-row-number action)
  (let ([found (find (lambda (e) (equal? (cadr e) action)) %current-actions)])
    (and found (car found))))

(define (focused-client)
  "正在观看本 session 的 client 名（供 switch-client -c），无则空串。"
  (let* ([result (tmux-cmd "list-clients" "-F" "#{client_name}"
                           "-t" (context-value 0 ""))]
         [names (if (zero? (car result))
                    (filter nonempty (string-split (cdr result) #\newline))
                    '())])
    (if (pair? names) (car names) "")))

(define (activate-cursor!)
  (let ([action (cursor-action)])
    (when action (handle-action action (focused-client)))))

(define (toggle-and-track action)
  "折叠/展开后光标跟随该节点移动到新行号。"
  (handle-action action "")
  (render-current! #t)
  (set! %cursor-row (or (action-row-number action)
                        (and (pair? %current-actions) (caar %current-actions)))))

(define (cursor-fold mode)
  "MODE 为 'fold / 'unfold：作用于光标处 session/group 节点；状态已符合
则 no-op。window/pane 行上 fold 跳到上方最近节点、unfold 等同 Enter。"
  (match (cursor-action)
    [('session skey)
     (let ([collapsed? (member skey (split-option-value (context-value 2 "")))])
       (when (if (eq? mode 'fold) (not collapsed?) collapsed?)
         (toggle-and-track (cursor-action))))]
    [('group gkey)
     (let ([collapsed? (member gkey (split-option-value (context-value 3 "")))])
       (when (if (eq? mode 'fold) (not collapsed?) collapsed?)
         (toggle-and-track (cursor-action))))]
    [_
     (if (eq? mode 'fold)
         (let ([node (find (lambda (e)
                             (and (< (car e) (or %cursor-row 0))
                                  (match (cadr e)
                                    [('session _) #t]
                                    [('group _) #t]
                                    [_ #f])))
                           (reverse %current-actions))])
           (when node (set! %cursor-row (car node))))
         (activate-cursor!))]))

(define (handle-key key)
  (case key
    [(down) (cursor-move 1)]
    [(up) (cursor-move -1)]
    [(enter) (activate-cursor!)]
    [(left) (cursor-fold 'fold)]
    [(right) (cursor-fold 'unfold)]
    [(esc quit) (tmux-cmd "last-pane")]
    [else #f]))

;; cbreak 模式：按键即时到达且不回显。只动输入端标志（-icanon -echo），
;; 不用 raw（raw 会同时清 OPOST，破坏 emit-line 的换行输出）。
(define (stty-cbreak!)
  (false-if-exception (system* "stty" "-icanon" "-echo")))

(define (read-key port)
  "读一个按键并解析为符号；EOF 为 #f，无法识别为 'ignore。
方向键为 ESC [ A/B/C/D 序列（tmux 转发时整键一次写入，无需等待）。"
  (define (dispatch c)
    (case c
      [(#\j) 'down] [(#\k) 'up] [(#\h) 'left] [(#\l) 'right]
      [(#\q) 'quit]
      [(#\newline #\return) 'enter]
      [else 'ignore]))
  (let ([c (read-char port)])
    (cond
     [(eof-object? c) #f]
     [(char=? c #\escape)
      (if (and (char-ready? port)
               (let ([leader (peek-char port)])
                 (or (char=? leader #\[) (char=? leader #\O))))
          (begin (read-char port)
                 (if (char-ready? port)
                     (case (read-char port)
                       [(#\A) 'up] [(#\B) 'down] [(#\C) 'right] [(#\D) 'left]
                       [else 'ignore])
                     'ignore))
          'esc)]
     [else (dispatch c)])))

(define (drain-keys port)
  (let loop ()
    (when (char-ready? port)
      ;; read-key 的 #f 是 EOF：EOF 处 char-ready? 恒 #t，必须停止 loop
      ;; 防止原地自旋；'ignore（无法识别键）为真值，不受影响继续消费。
      (let ([key (read-key port)])
        (when key
          (handle-key key)
          (loop))))))

;; === FIFO daemon ===

(define (fifo-path)
  ;; FIFO 位于 XDG_RUNTIME_DIR（per-user 运行时目录，替代世界可读写的
  ;; /tmp）；变量缺省时回退 /tmp 保持旧路径行为。文件名模式不变，
  ;; sidebar-toggle 的 fifo_path 与本函数必须保持同一约定。
  (let* ([pane (or (getenv "TMUX_PANE") "unknown")]
         [id (if (and (positive? (string-length pane))
                      (char=? (string-ref pane 0) #\%))
                 (substring pane 1)
                 pane)]
         [dir (or (getenv "XDG_RUNTIME_DIR") "/tmp")])
    (format #f "~a/tmux-sidebar-~a-~a.fifo" dir (getuid) id)))

(define (open-event-fifo)
  (let ([path (fifo-path)])
    (when (file-exists? path) (delete-file path))
    (mknod path 'fifo #o600 0)
    (cons path (open-file path "r+"))))

;; 返回值即"是否变更型事件"：toggle-group 与 click 会改变折叠/聚焦状态，
;; refresh 行与无法识别的行不会。drain-events 据此决定是否批内刷新快照。
(define (handle-event line)
  (match (string-split line #\tab)
    [("refresh") #f]
    [("toggle-group") (toggle-current-group) #t]
    [("click" mouse-y pane-top client)
     (let ([y (string->number mouse-y)]
           [top (string->number pane-top)])
       (when (and y top) (handle-click y top client))
       #t)]
    [_ #f]))

(define (drain-events port)
  (let loop ()
    (when (char-ready? port)
      (let ([line (read-line port)])
        (unless (eof-object? line)
          ;; 变更型事件后只 refresh-state!（刷新 %current-context/
          ;; %current-panes，批内后续 toggle/click 基于新快照），绝不能调
          ;; render-current!——click 命中检测依赖 %current-actions，而它
          ;; 只在真正重绘时更新，须与用户当前所见屏幕保持一致。
          (when (handle-event line)
            (refresh-state!))
          (loop))))))

(define (run-daemon)
    (define (sweep-legacy-fifos)
    "一次性迁移清理：删除 /tmp 下本 UID 命名模式的旧侧栏 FIFO。
双重安全阀：pane 在本 server 存活则保留；pane 不可见时（可能是跨
server 的存活旧 daemon）再探测 FIFO 读端是否仍被持有——O_WRONLY|
O_NONBLOCK 打开成功即有存活读端，无读端才删除。"
    (let ([prefix (format #f "tmux-sidebar-~a-" (getuid))])
      (for-each
       (lambda (name)
         (let* ([pane-id (substring name
                                    (string-length prefix)
                                    (- (string-length name) 5))]
                [result (tmux-cmd "display-message" "-p"
                                  "-t" (string-append "%" pane-id)
                                  "#{pane_id}")]
                [pane-alive? (and (zero? (car result))
                                  (not (string-null? (cdr result))))]
                [probe (false-if-exception
                        (open (string-append "/tmp/" name)
                              (logior O_WRONLY O_NONBLOCK)))]
                [reader-alive?
                 (and probe
                      (false-if-exception (close-port probe))
                      #t)])
           (when (and (not pane-alive?) (not reader-alive?))
             (false-if-exception
              (delete-file (string-append "/tmp/" name))))))
       (filter
        (lambda (name)
          (and (string-prefix? prefix name)
               (string-suffix? ".fifo" name)
               (> (string-length name)
                  (+ (string-length prefix) 5))))
        (false-if-exception (scandir "/tmp"))))))
  (sweep-legacy-fifos)
(let* ([fifo (open-event-fifo)]
         [path (car fifo)]
         [port (cdr fifo)]
         [stdin (current-input-port)]
         [cleaned? #f])
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
        (stty-cbreak!)
        (display "\x1b[?25l\x1b[2J\x1b[H")
        (force-output))
      (lambda ()
        (let loop ()
          ;; daemon 韧性：单帧异常记到 stderr 后继续循环（降级为丢一帧），
          ;; 而非进程死亡。用 boot-9 内建 catch 而非 srfi-34 的 guard：
          ;; 本文件不加 use-modules，不依赖主文件的 import，保持「仅运行期
          ;; 依赖、load 顺序无要求」的性质。
          (catch #t
            (lambda ()
              (render-current! #t)
              ;; FIFO 与 stdin 一起等；drain 内部用 char-ready? 兜底区分来源
              ;; （select 对 buffered port 的返回形式不保证，双 drain 无害）。
              (let ([readable (car (select (list port stdin) '() '() 30))])
                (when (pair? readable)
                  (drain-events port)
                  (drain-keys stdin))))
            (lambda (key . args)
              (format (current-error-port)
                      "sidebar: frame error ~a ~s; keep running\n" key args)))
          (loop)))
      cleanup)))
