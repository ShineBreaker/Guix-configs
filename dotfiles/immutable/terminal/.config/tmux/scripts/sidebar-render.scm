#!/usr/bin/env guile
!#

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; sidebar-render.scm — tmux 侧边栏长驻渲染进程
;;
;; 外部接口只有两个：
;;   daemon  长驻侧栏 pane，通过 FIFO 接收 refresh/click/toggle-group 事件；
;;           聚焦本 pane 时还监听 stdin 键盘输入（hjkl/方向键移动光标，
;;           Enter 激活，h/l 折叠展开节点，q/Esc 返回主 pane）
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

;; 模块布局：实现按职责拆分到同目录 sidebar/ 下，load 进同一命名空间，
;; 函数集合与输出格式和单文件版本完全一致。
;;   text.scm   文本/路径/宽度基础工具
;;   info.scm   git 状态与 /proc 进程信息采集
;;   layout.scm 分组聚合与布局行渲染
;;   input.scm  键盘输入解析与 FIFO 事件循环
;; 脚本由 tmux run-shell 调用，工作目录不可靠。current-filename 经软链
;; canonicalize：immutable 部署下本文件是独立 store 单文件项，dirname 落在
;; /gnu/store，同目录没有 sidebar/。因此先试部署位置
;; $HOME/.config/tmux/scripts/sidebar/，仓库源树（current-filename 同目录）
;; 回退；%sidebar-module-dir 统一指模块所在目录，都找不到时保留 %script-dir
;; 让 load 报出可定位的路径。
(define %script-dir (dirname (current-filename)))

(define %sidebar-module-dir
  (or (find (lambda (dir)
              (access? (string-append dir "/text.scm") R_OK))
            (list (string-append (or (getenv "HOME") "")
                                 "/.config/tmux/scripts/sidebar")
                  (string-append %script-dir "/sidebar")))
      %script-dir))

(load (string-append %sidebar-module-dir "/text.scm"))
(load (string-append %sidebar-module-dir "/info.scm"))
(load (string-append %sidebar-module-dir "/layout.scm"))
(load (string-append %sidebar-module-dir "/input.scm"))

;; === tmux snapshot ===

(define sidebar-title "tmux-sidebar")
(define sidebar-command "sidebar-render.scm daemon")

(define (tmux-cmd . args)
  "执行 tmux 命令，返回 (exit-code . output)。"
  (let* ([port (apply open-pipe* OPEN_READ "tmux" args)]
         [output (read-string port)]
         [status (close-pipe port)])
    (cons status (string-trim-right output))))

(define (tmux-sidebar-pane? title start-command)
  (or (string=? title sidebar-title)
      (and start-command (string-contains start-command sidebar-command))))

;; 普通 pane 字段：session, window index/id/name, path, command, active,
;; title, pid, pane index, AI/custom title, custom description, locked title.
(define (collect-state)
  "用一次 list-panes 返回 (context pane-fields...)。
CONTEXT 为 session/window/折叠状态/宽度/当前 Git branch。"
  (let* ([current-pane (or (getenv "TMUX_PANE") "")]
         [format-string
          (string-append
           "#{pane_id}\t#{session_name}\t#{window_index}\t#{window_id}\t"
           "#{window_name}\t#{pane_current_path}\t#{pane_current_command}\t"
           "#{pane_active}\t#{pane_title}\t#{pane_pid}\t#{pane_index}\t"
           "#{pane_start_command}\t#{@tabby_ai_title}\t"
           "#{@sidebar_window_title}\t#{@sidebar_window_desc}\t"
           "#{@tabby_pane_title}\t#{@sidebar_collapsed_sessions}\t"
           "#{@sidebar_collapsed_groups}\t#{pane_width}\t#{@sidebar_width}\t"
           "#{@status_git_branch}\t__END__")]
         [result (tmux-cmd "list-panes" "-a" "-F" format-string)])
    (if (not (zero? (car result)))
        #f
        (let loop ([raw-lines (string-split (cdr result) #\newline)]
                   [context #f]
                   [panes '()])
          (if (null? raw-lines)
              (list context (reverse panes))
              (match (string-split (car raw-lines) #\tab)
                [(pane-id session idx win-id name path command active title pid pane-idx
                          start ai-title custom-title custom-desc locked-title
                          collapsed-sessions collapsed-groups pane-width option-width
                          status-branch _end)
                 (cond
                  [(string=? pane-id current-pane)
                   (let ([context* (list session idx collapsed-sessions collapsed-groups
                                         pane-width option-width status-branch
                                         active)])
                     (if (tmux-sidebar-pane? title start)
                         (loop (cdr raw-lines) context* panes)
                         (loop (cdr raw-lines)
                               context*
                               (cons (list session idx win-id name path command active
                                           title pid pane-idx ai-title custom-title
                                           custom-desc locked-title)
                                     panes))))]
                  [(tmux-sidebar-pane? title start)
                   (loop (cdr raw-lines) context panes)]
                  [else
                   (loop (cdr raw-lines)
                         context
                         (cons (list session idx win-id name path command active
                                     title pid pane-idx ai-title custom-title
                                     custom-desc locked-title)
                               panes))])]
                [_ (loop (cdr raw-lines) context panes)]))))))

(define (set-option-list! name values)
  (tmux-cmd "set" "-g" name (string-join values ",")))

(define (toggle-list-value! option current-value key)
  (let ([values (if (string-null? current-value)
                    '()
                    (string-split current-value #\,))])
    (set-option-list! option
                      (if (member key values)
                          (delete key values)
                          (cons key values)))))

;; === Render and Click ===

(define %current-context #f)
(define %current-panes '())
(define %current-actions '())
(define %cursor-row #f)
(define %last-screen #f)

(define (context-value index fallback)
  (if (and %current-context (> (length %current-context) index))
      (list-ref %current-context index)
      fallback))

(define (current-git-branch)
  (let ([session (context-value 0 "")]
        [window (context-value 1 "")])
    (let loop ([panes %current-panes]
               [fallback #f])
      (if (null? panes)
          (if fallback (or (read-git-head fallback) "") "")
          (let ([fields (car panes)])
            (if (and (string=? (row-session fields) session)
                     (string=? (row-index fields) window))
                (if (row-pane-active? fields)
                    (or (read-git-head (row-path fields)) "")
                    (loop (cdr panes) (or fallback (row-path fields))))
                (loop (cdr panes) fallback)))))))

(define (update-statusbar-branch!)
  (let ([branch (current-git-branch)]
        [previous (context-value 6 "")])
    (unless (string=? branch previous)
      (tmux-cmd "set-option" "-w" "@status_git_branch" branch))))

(define (rows->screen rows cursor-row)
  (call-with-output-string
   (lambda (port)
     (parameterize ((current-output-port port))
       (let loop ([rs rows] [i 0])
         (unless (null? rs)
           (emit-styled-line (car rs) (and cursor-row (= i cursor-row)))
           (loop (cdr rs) (+ i 1))))))))

(define (refresh-state!)
  (let ([state (collect-state)])
    (when state
      (set! %current-context (car state))
      (set! %current-panes (cadr state)))
    (when %current-context
      (set-sidebar-width! (context-value 4 "0") (context-value 5 "32")))
    (update-statusbar-branch!)))

(define (current-rows)
  (if (or (not %current-context) (null? %current-panes))
      (list (make-row " [no tmux data]" #f ansi-dim #f))
      (let* ([session (context-value 0 "")]
             [blocks (active-session-first (session-blocks %current-panes) session)])
        (layout-rows-with-context blocks %current-context))))

(define (render-current! cursor-control?)
  (refresh-state!)
  (let* ([rows (current-rows)]
         [actions (rows-actions rows)]
         ;; 光标只在 daemon 模式且侧栏 pane 聚焦时显示；位置失效时回落到
         ;; 当前 window 行（找不到则首个条目行）。
         [cursor (and cursor-control? (resolve-cursor actions))])
    (set! %current-actions actions)
    ;; 失焦/无条目时 cursor 为 #f，但 %cursor-row 保留旧位置，供再聚焦恢复
    (set! %cursor-row (or cursor %cursor-row))
    (let ([screen (rows->screen rows cursor)])
      (when (or (not cursor-control?)
                (not %last-screen)
                (not (string=? screen %last-screen)))
        (when cursor-control? (display "\x1b[H"))
        (display screen)
        (when cursor-control? (display "\x1b[J"))
        (force-output)
        (set! %last-screen screen)))))

(define (row-action row actions)
  (let ([found (find (lambda (entry) (= (car entry) row)) actions)])
    (and found (cadr found))))

(define (nearby-action row actions)
  (let loop ([candidates (list row (- row 1) (+ row 1))])
    (if (null? candidates)
        #f
        (or (row-action (car candidates) actions)
            (loop (cdr candidates))))))

(define (screen-row-candidates mouse-y pane-top)
  (let* ([local (- mouse-y pane-top)]
         [local-prev (- local 1)])
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
      [('session skey)
       (toggle-list-value! "@sidebar_collapsed_sessions"
                           (context-value 2 "") skey)]
      [('group gkey)
       (toggle-list-value! "@sidebar_collapsed_groups"
                           (context-value 3 "") gkey)]
      [('window session idx)
       (switch-client-to client (string-append session ":" idx))]
      [('pane session idx pane-idx)
       (switch-client-to client (string-append session ":" idx))
       (when (nonempty pane-idx)
         (tmux-cmd "select-pane" "-t"
                   (string-append session ":" idx "." pane-idx)))]
      [_ #f])))

(define (handle-click mouse-y pane-top client)
  (let ([action (let loop ([candidates (screen-row-candidates mouse-y pane-top)])
                   (if (null? candidates)
                       #f
                       (or (nearby-action (car candidates) %current-actions)
                           (loop (cdr candidates)))))])
    (handle-action action client)))

(define (toggle-current-group)
  (let ([current-session (context-value 0 "")]
        [current-window (context-value 1 "")])
    (let loop ([panes %current-panes])
      (unless (null? panes)
        (let* ([fields (car panes)]
               [session (row-session fields)]
               [idx (row-index fields)]
               [path (row-path fields)])
          (if (and (string=? session current-session)
                   (string=? idx current-window))
              (match (path-group-key path)
                [(group-key _display _group-path)
                 (toggle-list-value! "@sidebar_collapsed_groups"
                                     (context-value 3 "")
                                     (group-collapse-key session group-key))])
              (loop (cdr panes))))))))

;; === Entry ===

(guard (ex [#t
            (format (current-error-port) "sidebar-render error: ~a~%" ex)
            (exit 1)])
  (let ([args (command-line)])
    (cond
     [(and (> (length args) 1) (string=? (cadr args) "daemon"))
      (run-daemon)]
     [(and (> (length args) 1) (string=? (cadr args) "render"))
      (render-current! #f)]
     [(and (> (length args) 1) (string=? (cadr args) "--as-library"))
      #t]
     [else
      (format (current-error-port) "usage: sidebar-render.scm daemon|render~%")
      (exit 2)])))
