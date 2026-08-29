;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; sidebar/text.scm — 侧栏渲染基础工具：ANSI 常量、pane 字段访问、
;; 文本宽度/截断/填充/居中、路径处理。由 sidebar-render.scm load 进
;; 同一命名空间，仅依赖 Guile 核心。加载顺序：text → info → layout → input。

(use-modules (srfi srfi-1))

;; === ANSI ===

(define ansi-erase-line "\x1b[K")
(define ansi-reset "\x1b[0m")
(define ansi-bold "\x1b[1m")
(define ansi-dim "\x1b[2m")
(define ansi-reverse "\x1b[7m")
(define ansi-session "\x1b[97m")
(define ansi-group "\x1b[96m")
(define ansi-active "\x1b[94m")
(define ansi-desc "\x1b[37m")
(define ansi-session-active "\x1b[92m")

;; === Width ===

(define (string->positive-integer s fallback)
  (let ([n (and s (string->number s))])
    (if (and n (> n 0)) n fallback)))

;; 宽度缓存：每个 Guile 进程（即每次渲染/点击处理）内只计算一次，
;; 避免每行输出都重复调用 tmux 命令（单次渲染节省 60+ 次 tmux 调用）。
(define %sidebar-width-value 31)

(define (set-sidebar-width! pane-width option-width)
  (let* ([pane (string->positive-integer pane-width 0)]
         [option (string->positive-integer option-width 32)]
         [width (if (> pane 0) pane option)])
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

(define (basename-of-path path)
  (let ([idx (string-rindex path #\/)])
    (if idx (substring path (+ idx 1)) path)))

(define (char-width c)
  (let ([n (char->integer c)]
        [category (char-general-category c)])
    (cond
     [(memq category '(Mn Me Cf)) 0]
     [(or (and (>= n #x3400) (<= n #x4DBF))
          (and (>= n #x4E00) (<= n #x9FFF))
          (and (>= n #xF900) (<= n #xFAFF))
          (and (>= n #xAC00) (<= n #xD7AF))
          (and (>= n #xFF01) (<= n #xFF60))
          (and (>= n #xFFE0) (<= n #xFFE6))
          (and (>= n #x20000) (<= n #x2FFFD))
          (and (>= n #x30000) (<= n #x3FFFD)))
      2]
     [else 1])))

(define (string-width text)
  (fold (lambda (c width) (+ width (char-width c)))
        0
        (string->list text)))

(define (truncate-string text max-width)
  (let ([ellipsis "…"])
    (cond
     [(<= max-width 0) ""]
     [(<= (string-width text) max-width) text]
     [(= max-width 1) ellipsis]
     [else
      (let loop ([chars (string->list text)]
                 [width 0]
                 [result '()])
        (if (or (null? chars)
                (> (+ width (char-width (car chars))) (- max-width 1)))
            (string-append (list->string (reverse result)) ellipsis)
            (loop (cdr chars)
                  (+ width (char-width (car chars)))
                  (cons (car chars) result))))])))

(define (pad-string text width)
  (let ([padding (- width (string-width text))])
    (if (positive? padding)
        (string-append text (make-string padding #\space))
        text)))

(define (directory-path? path)
  (false-if-exception (eq? (stat:type (stat path)) 'directory)))

(define (hex-char? c)
  (or (char-numeric? c)
      (and (char>=? c #\a) (char<=? c #\f))
      (and (char>=? c #\A) (char<=? c #\F))))

(define (center-text text width)
  (let* ([text* (truncate-string text width)]
         [tw (string-width text*)]
         [left (max 0 (quotient (- width tw) 2))]
         [right (max 0 (- width tw left))])
    (string-append (make-string left #\space) text* (make-string right #\space))))

(define (trim-trailing-slashes path)
  (let loop ([end (string-length path)])
    (cond
     [(<= end 1) (substring path 0 end)]
     [(char=? (string-ref path (- end 1)) #\/) (loop (- end 1))]
     [else (substring path 0 end)])))

(define (parent-path path)
  (let* ([clean (trim-trailing-slashes path)]
         [home (or (getenv "HOME") "")])
    (cond
     [(or (string=? clean "") (string=? clean "/")) "/"]
     [(string=? clean home) home]
     [else
      (let ([idx (string-rindex clean #\/)])
        (cond
         [(not idx) "."]
         [(zero? idx) "/"]
         [else (substring clean 0 idx)]))])))

(define (basename-display path)
  (let* ([clean (trim-trailing-slashes path)]
         [home (or (getenv "HOME") "")])
    (cond
     [(string=? clean "/") "/"]
     [(string=? clean home) "~"]
     [else
      (let ([idx (string-rindex clean #\/)])
        (if idx (substring clean (+ idx 1)) clean))])))
