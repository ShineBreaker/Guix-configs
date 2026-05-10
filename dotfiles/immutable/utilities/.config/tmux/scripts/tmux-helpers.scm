#!/usr/bin/env guile
!#

;;; tmux-helpers.scm - tmux 脚本共享工具模块
;;;
;;; 本模块是 Guile 侧的共享基础设施，为所有 tmux Guile 脚本提供：
;;;   - tmux 命令封装（带错误码的返回值，避免 shell 解析）
;;;   - 侧边栏 pane 检测（按 title/start_command 过滤，避免自我采集）
;;;   - 窗口数据采集器 collect-window-data（跨 session 整合，每 pane 一条制表符分隔行）
;;;   - Socket 路径哈希到临时文件隔离（/tmp/tmux-<hash>-<name>）
;;;   - 文件锁（flock -n 非阻塞，脚本间互斥）
;;;   - 缓存读写（带时间戳，json/文本混合缓存）
;;;   - 防抖调用（Debounce，连续 3 次跳过后强制执行）
;;;   - CJK 字符宽度感知的截断/填充（用于侧栏渲染中的中英文混排）
;;;
;;; 注意：本模块通过 (load ...) 加载，而非 (use-modules ...)。
;;; 这样设计是为了让 tmux 脚本可以直接使用其中定义的绑定，
;;; 而无需复杂的模块路径配置。

(use-modules (ice-9 popen)
             (ice-9 rdelim)
             (ice-9 match)
             (ice-9 regex)
             (ice-9 textual-ports)
             (srfi srfi-1))

;;; ============================================================
;;; tmux 命令交互
;;; ============================================================

(define (tmux-cmd . args)
  "执行 tmux 命令，返回 (exit-code . output) 的 cons 对。
ARGS 是传递给 tmux 的参数列表。使用 open-pipe* 避免 shell 解析。"
  (let* ((port (apply open-pipe* OPEN_READ "tmux" args))
         (output (read-string port))
         (exit-code (close-pipe port)))
    (cons exit-code (string-trim-both output))))

(define (tmux-display format-string)
  "执行 tmux display -p FORMAT-STRING，返回格式化后的输出字符串。"
  (cdr (tmux-cmd "display-message" "-p" format-string)))

(define (tmux-set-option name value)
  "设置 tmux 全局选项 NAME 为 VALUE。"
  (tmux-cmd "set-option" "-g" name value))

(define (tmux-get-option name)
  "获取 tmux 全局选项 NAME 的值，返回字符串。"
  (cdr (tmux-cmd "show-option" "-gqv" name)))

(define (tmux-get-window-option name)
  "获取当前窗口选项 NAME 的值，返回字符串。"
  (cdr (tmux-cmd "show-option" "-wqv" name)))

(define (tmux-list-windows format-string)
  "列出所有会话中的所有窗口，使用 FORMAT-STRING 格式化。"
  (cdr (tmux-cmd "list-windows" "-a" "-F" format-string)))

(define (tmux-list-sessions format-string)
  "列出所有会话，使用 FORMAT-STRING 格式化。"
  (cdr (tmux-cmd "list-sessions" "-F" format-string)))

(define (tmux-list-panes format-string)
  "列出所有会话中的所有面板，使用 FORMAT-STRING 格式化。"
  (cdr (tmux-cmd "list-panes" "-a" "-F" format-string)))

(define (tmux-sidebar-pane? title start-command command)
  "判断 pane 是否是侧栏自身，避免侧栏被采集为工作窗口。"
  (or (string=? title "tmux-sidebar")
      (and start-command (string-contains start-command "sidebar-toggle pane-loop"))
      (string=? command "sidebar-render")))

(define (collect-window-data)
  "采集所有会话中的普通 pane 数据（每 pane 一条），返回制表符分隔字符串。
字段：会话名、窗口索引、窗口 id、窗口名、代表 pane 路径、代表 pane 命令、活动标志、
会话附着状态、代表 pane 是否活跃、pane title、pane pid、pane index、pane start command、
AI 标题、自定义标题、自定义描述、锁定 pane 标题、窗口 pane 数。"
  (let* ((raw (tmux-list-panes
               (string-append "#{session_name}\t#{window_index}\t#{window_id}\t#{window_name}\t"
                              "#{pane_current_path}\t#{pane_current_command}\t"
                              "#{window_activity_flag}\t#{session_attached}\t"
                              "#{pane_active}\t#{pane_title}\t#{pane_pid}\t#{pane_index}\t"
                              "#{pane_start_command}\t#{@tabby_ai_title}\t"
                              "#{@sidebar_window_title}\t#{@sidebar_window_desc}\t"
                              "#{@tabby_pane_title}\t#{window_panes}\t__END__")))
         (lines (if (string-null? raw) '() (string-split raw #\newline))))
    (string-join
     (filter-map
      (lambda (line)
        (match (string-split line #\tab)
          ((session idx win-id name path cmd activity attached active title pid pane-idx
                    start ai-title custom-title custom-desc locked-pane-title window-panes _end)
           (and (not (tmux-sidebar-pane? title start cmd))
                (string-join
                 (list session idx win-id name path cmd activity attached
                       active title pid pane-idx start ai-title custom-title
                       custom-desc locked-pane-title window-panes)
                 "\t")))
          (_ #f)))
      lines)
     "\n")))

;;; ============================================================
;;; 版本检测
;;; ============================================================

(define (require-tmux-version)
  "检查 tmux 版本是否 >= 3.3a，不满足则输出错误信息并退出。"
  (let* ((result (tmux-cmd "-V"))
         (version-str (cdr result))
         ;; 提取版本号，例如 "tmux 3.3a" -> "3.3a"
         (version (if (string-match "tmux ([0-9]+\\.[0-9]+[a-z]*)" version-str)
                      (match:substring (string-match "tmux ([0-9]+\\.[0-9]+[a-z]*)" version-str) 1)
                      #f)))
    (when version
      (unless (version>=? version "3.3a")
        (display (string-append "错误：tmux 版本 " version " 不满足要求（需要 >= 3.3a）\n")
                 (current-error-port))
        (exit 1)))))

(define (version>=? a b)
  "比较两个 tmux 版本字符串，返回 #t 如果 A >= B。
支持类似 3.3a, 3.4 等版本格式。"
  (let* ((parts-a (parse-version a))
         (parts-b (parse-version b)))
    (and (>= (car parts-a) (car parts-b))
         (or (> (car parts-a) (car parts-b))
             (>= (cdr parts-a) (cdr parts-b))))))

(define (parse-version version-str)
  "解析版本字符串为 (major.minor . patch) 的 cons 对。
例如 \"3.3a\" -> (3 . 3)，\"3.4\" -> (3 . 4)。"
  (let ((m (string-match "([0-9]+)\\.([0-9]+)" version-str)))
    (if m
        (cons (string->number (match:substring m 1))
              (string->number (match:substring m 2)))
        (cons 0 0))))

;;; ============================================================
;;; Socket 路径与临时文件隔离
;;; ============================================================

(define %socket-path-cache #f)

(define (socket-path)
  "获取当前 tmux 的 socket 路径，每次调用结果会被缓存。"
  (or %socket-path-cache
      (let ((path (tmux-display "#{socket_path}")))
        (set! %socket-path-cache path)
        path)))

(define (cache-dir)
  "返回缓存目录，固定为 \"/tmp\"。"
  "/tmp")

(define (cache-file name)
  "返回缓存文件路径：/tmp/tmux-<socket-hash>-<NAME>。"
  (let* ((sock (socket-path))
         (sock-key (number->string (string-hash sock) 16)))
    (string-append (cache-dir) "/tmux-" sock-key "-" name)))

(define (lock-file name)
  "返回锁文件路径，即 (cache-file NAME) 加上 \".lock\" 后缀。"
  (string-append (cache-file name) ".lock"))

(define (basename-of-path path)
  "提取路径中的文件名部分。"
  (let ((idx (string-rindex path #\/)))
    (if idx
        (substring path (+ idx 1))
        path)))

;;; ============================================================
;;; 文件锁
;;; ============================================================

(define (with-lock name thunk)
  "使用 flock -n 非阻塞方式获取锁，执行 THUNK。
返回 THUNK 的结果，如果锁不可用则返回 #f。"
  (let ((lock (lock-file name)))
    (if (zero? (system (string-append "flock -n " lock " true 2>/dev/null")))
        (dynamic-wind
          (lambda () #t)
          thunk
          (lambda ()
            ;; 释放锁：打开并关闭 fd
            (let ((fd (open-file lock "r")))
              (when fd
                (close fd))
              ;; flock 会在进程退出时自动释放
              )))
        #f)))

;;; ============================================================
;;; 缓存读写
;;; ============================================================

(define (read-cache name)
  "读取缓存文件，返回内容字符串；文件不存在则返回 #f。"
  (let ((file (cache-file name)))
    (if (file-exists? file)
        (call-with-input-file file
          (lambda (port)
            (read-string port)))
        #f)))

(define (write-cache name data)
  "将 DATA 字符串写入缓存文件。"
  (let ((file (cache-file name)))
    (call-with-output-file file
      (lambda (port)
        (display data port)))))

;;; ============================================================
;;; 防抖（Debounce）
;;; ============================================================

(define (call-with-debounce name interval-ms thunk)
  "防抖调用：如果在 INTERVAL-MS 毫秒内再次调用则跳过，
连续跳过 3 次后强制执行。使用时间戳和计数文件跟踪状态。"
  (let* ((ts-file (cache-file (string-append name ".ts")))
         (ct-file (cache-file (string-append name ".ct")))
         (now-ms (* (current-time) 1000)))
    (if (file-exists? ts-file)
        (let* ((last-ms (string->number
                          (call-with-input-file ts-file read-string)))
               (count (if (file-exists? ct-file)
                          (string->number
                            (call-with-input-file ct-file read-string))
                          0))
               (elapsed (- now-ms last-ms)))
          (if (< elapsed interval-ms)
              (begin
                (if (>= count 2)
                    ;; 连续跳过达到 3 次，强制执行
                    (begin
                      (write-cache (string-append name ".ts")
                                   (number->string now-ms))
                      (write-cache (string-append name ".ct") "0")
                      (thunk))
                    ;; 跳过，增加计数
                    (begin
                      (write-cache (string-append name ".ct")
                                   (number->string (+ count 1)))
                      #f)))
              ;; 超过间隔，正常执行
              (begin
                (write-cache (string-append name ".ts")
                             (number->string now-ms))
                (write-cache (string-append name ".ct") "0")
                (thunk))))
        ;; 首次调用
        (begin
          (write-cache (string-append name ".ts")
                       (number->string now-ms))
          (write-cache (string-append name ".ct") "0")
          (thunk)))))

;;; ============================================================
;;; CJK 字符宽度支持
;;; ============================================================

(define (char-width c)
  "返回字符 C 的显示宽度：CJK 字符返回 2，其余返回 1。"
  (let ((n (char->integer c)))
    (cond
     ;; CJK 统一表意文字
     ((and (>= n #x4E00) (<= n #x9FFF)) 2)
     ;; CJK 扩展 A
     ((and (>= n #x3400) (<= n #x4DBF)) 2)
     ;; CJK 扩展 B-F
     ((and (>= n #x20000) (<= n #x2CEAF)) 2)
     ;; CJK 兼容表意文字
     ((and (>= n #xF900) (<= n #xFAFF)) 2)
     ;; 全角标点
     ((and (>= n #xFF01) (<= n #xFF60)) 2)
     ;; 全角空格
     ((= n #x3000) 2)
     ;; CJK 符号
     ((and (>= n #x3000) (<= n #x303F)) 2)
     ;; 半角片假名
     ((and (>= n #xFF65) (<= n #xFF9F)) 2)
     ;; 韩文音节
     ((and (>= n #xAC00) (<= n #xD7AF)) 2)
     ;; CJK 扩展 G
     ((and (>= n #x30000) (<= n #x3134F)) 2)
     ;; 其他字符默认宽度 1
     (else 1))))

(define (string-width s)
  "返回字符串 S 的显示宽度（考虑 CJK 字符占两列）。"
  (let loop ((chars (string->list s))
             (width 0))
    (if (null? chars)
        width
        (loop (cdr chars)
              (+ width (char-width (car chars)))))))

(define (truncate-string s max-width)
  "将字符串 S 截断到 MAX-WIDTH 显示宽度，截断时在末尾追加 …。
使用 CJK 感知的宽度计算。"
  (let* ((ellipsis "…")
         (ellipsis-width (string-width ellipsis)))
    (cond
     ((<= max-width 0) "")
     ((<= (string-width s) max-width) s)
     ((<= max-width ellipsis-width) ellipsis)
     (else
      (let ((text-width (- max-width ellipsis-width)))
        (let loop ((chars (string->list s))
                   (width 0)
                   (result '()))
          (cond
           ((null? chars)
            (list->string (reverse result)))
           ((> (+ width (char-width (car chars))) text-width)
            (string-append (list->string (reverse result)) ellipsis))
           (else
            (loop (cdr chars)
                  (+ width (char-width (car chars)))
                  (cons (car chars) result))))))))))

(define (pad-string s width)
  "将字符串 S 左对齐填充到 WIDTH 显示宽度，不足部分用空格补齐。"
  (let ((sw (string-width s)))
    (if (>= sw width)
        s
        (string-append s (make-string (- width sw) #\space)))))

;;; ============================================================
;;; 加载方式
;;; ============================================================

;; 加载方式：在脚本顶部使用
;; (load (string-append (dirname (current-filename)) "/tmux-helpers.scm"))
