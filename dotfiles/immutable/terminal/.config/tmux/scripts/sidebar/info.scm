;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; sidebar/info.scm — 外部状态采集：git HEAD/分支探测（带时间戳缓存）
;; 与 /proc 子进程 argv 解析（带缓存）。依赖 text.scm 的路径/文本工具。

;; read-string 位于 (ice-9 rdelim)。主文件先 import 后 load 本文件，daemon
;; 场景下此声明冗余；单文件加载/语法检查（不经主文件）时必需。
(use-modules (ice-9 textual-ports) (ice-9 rdelim) (srfi srfi-1))

(define %git-head-paths (make-hash-table))
(define %git-branches (make-hash-table))
(define git-path-cache-ticks (* 30 internal-time-units-per-second))

(define (absolute-path? path)
  (and (positive? (string-length path))
       (char=? (string-ref path 0) #\/)))

(define (gitdir-from-marker directory marker)
  (cond
   [(directory-path? marker) marker]
   [(file-exists? marker)
    ;; file-exists? 与读取之间存在竞态（marker 被删/权限变化 → ENOENT）：
    ;; 读失败按非 gitdir 文件处理返回 #f，不让单次探测击穿 daemon。
    (let ([content (false-if-exception
                    (string-trim-both (call-with-input-file marker read-string)))])
      (and content
           (string-prefix? "gitdir: " content)
           (let* ([value (string-drop content 8)]
                  [path (if (absolute-path? value)
                            value
                            (string-append directory "/" value))])
             (false-if-exception (canonicalize-path path)))))]
   [else #f]))

(define (find-git-head path)
  (let* ([now (get-internal-real-time)]
         [cached (hash-ref %git-head-paths path #f)])
    (if (and cached (< now (car cached)))
        (cdr cached)
        (let* ([start (false-if-exception (canonicalize-path path))]
               [head
                (and start
                     (let loop ([directory start])
                       (let* ([marker (string-append directory "/.git")]
                              [gitdir (gitdir-from-marker directory marker)])
                         (cond
                          [gitdir
                          (let ([candidate (string-append gitdir "/HEAD")])
                             (and (file-exists? candidate) candidate))]
                          [(string=? directory "/") #f]
                          [else
                           (let ([parent (parent-path directory)])
                             (if (string=? parent directory)
                                 #f
                                 (loop parent)))]))))])
          (hash-set! %git-head-paths path
                     (cons (+ now git-path-cache-ticks) head))
          head))))

(define (head-content->branch content)
  (cond
   [(string-prefix? "ref: refs/heads/" content)
    (let ([branch (string-drop content (string-length "ref: refs/heads/"))])
      (and (not (string-null? branch)) branch))]
   [(and (>= (string-length content) 7)
         (string-every hex-char? content))
    (substring content 0 7)]
   [else #f]))

(define (read-git-head path)
  (let ([head (find-git-head path)])
    (and head
         (false-if-exception
          (let* ([info (stat head)]
                 [stamp (list (stat:mtime info)
                              (stat:mtimensec info)
                              (stat:size info))]
                 [cached (hash-ref %git-branches head #f)])
            (if (and cached (equal? (car cached) stamp))
                (cdr cached)
                (let* ([content (string-trim-both
                                 (call-with-input-file head read-string))]
                       [branch (head-content->branch content)])
                  (hash-set! %git-branches head (cons stamp branch))
                  branch)))))))

(define %cmdline-cache (make-hash-table))
(define cmdline-cache-ticks (* 2 internal-time-units-per-second))

(define (process-argv pid)
  (let ([file (string-append "/proc/" pid "/cmdline")])
    (and (file-exists? file)
         ;; file-exists? 与读取间同样存在竞态；读失败（#f）令整个 and
         ;; 链返回 #f，与文件消失分支语义一致。
         (let ([args (false-if-exception
                      (filter (lambda (arg) (not (string-null? arg)))
                              (string-split (call-with-input-file file read-string)
                                            #\nul)))])
           (and (pair? args) args)))))

(define (child-pids pid)
  (let ([file (string-append "/proc/" pid "/task/" pid "/children")])
    (if (file-exists? file)
        (let ([raw (false-if-exception
                    (string-trim-both (call-with-input-file file read-string)))])
          ;; 读失败（#f）与空文件同样返回 '()，保持列表类型一致。
          (if (and raw (not (string-null? raw)))
              (string-split raw #\space)
              '()))
        '())))

(define (foreground-argv/uncached pid)
  (let loop ([queue (if (nonempty pid) (list pid) '())]
             [last #f]
             [seen '()])
    (if (null? queue)
        last
        (let* ([pid* (car queue)]
               [rest (cdr queue)])
          (if (member pid* seen)
              (loop rest last seen)
              (let ([argv (process-argv pid*)]
                    [children (child-pids pid*)])
                (loop (append children rest)
                      (or argv last)
                      (cons pid* seen))))))))

(define (foreground-argv pid)
  (let* ([now (get-internal-real-time)]
         [cached (and (nonempty pid) (hash-ref %cmdline-cache pid #f))])
    (if (and cached (< now (car cached)))
        (cdr cached)
        (let ([argv (foreground-argv/uncached pid)])
          (when (nonempty pid)
            (hash-set! %cmdline-cache pid
                       (cons (+ now cmdline-cache-ticks) argv)))
          argv))))

(define (shorten-argv argv command)
  (if (not (pair? argv))
      ""
      (let* ([raw-program (basename-of-path (car argv))]
             [program (if (string-prefix? "-" raw-program)
                          (string-drop raw-program 1)
                          raw-program)]
             [args (cdr argv)]
             [trimmed-args (filter (lambda (arg)
                                     (not (member arg '("--login" "-l" "-i"))))
                                   args)]
             [short (string-join (cons program (take trimmed-args (min 3 (length trimmed-args)))) " ")])
        short)))
