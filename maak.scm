;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: GPL-3.0

(define-module (maak)
  #:declarative? #t
  #:use-module (maak maak)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-19)
  #:use-module (srfi srfi-26)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 rdelim))

;;; 辅助函数：原子性文件写入（不依赖 guix utils）
(define (write-file-atomically file thunk)
  "原子性地执行 THUNK 写入 FILE，THUNK 接收一个输出端口作为参数"
  (let* ((template (string-append file ".XXXXXX"))
         (port (mkstemp! template)))
    (with-throw-handler #t
      (lambda ()
        (thunk port)
        (force-output port)
        (close-port port)
        (rename-file template file))
      (lambda (key . args)
        (false-if-exception (delete-file template))
        (false-if-exception (close-port port))))))

;;; 配置路径
(define repo-root
  (getcwd))
(define configs-dir
  (string-append repo-root "/source/configs"))
(define tmp-dir
  (string-append repo-root "/tmp"))
(define channel-fresh
  (string-append configs-dir "/../channel.scm"))
(define channel-lock
  (string-append configs-dir "/../channel.lock"))

(define ($ cmd)
  (let ((exit-code (status:exit-val (apply system* cmd))))
    (or (zero? exit-code)
        (error (format #f "
Non-zero exit code when running!
Command: ~a
Exit code: ~a~%" cmd exit-code)))))

(define* ($guix args
                #:key (channels channel-lock))
  ($ `("guix" "time-machine"
       ,(string-append "--channels=" channels) "--"
       ,@args)))

;;; Markdown 代码块提取逻辑

(define (extract-scheme-blocks-from-markdown file-path)
  "从 Markdown 文件中提取所有 ```scheme ... ``` 代码块的内容"
  (call-with-input-file file-path
    (lambda (port)
      (let loop ((lines '())
                 (in-scheme-block? #f))
        (let ((line (read-line port 'concat)))
          (if (eof-object? line)
              (reverse lines)
              (let ((trimmed (string-trim-both line)))
                (cond
                 ;; 检测到 scheme 代码块开始
                 ((and (not in-scheme-block?)
                       (string-prefix? "```scheme" trimmed))
                  (loop lines #t))
                 ;; 检测到代码块结束
                 ((and in-scheme-block?
                       (string=? "```" trimmed))
                  (loop lines #f))
                 ;; 在代码块内，收集内容
                 (in-scheme-block?
                  (loop (cons line lines) #t))
                 ;; 不在代码块内，跳过
                 (else
                  (loop lines #f))))))))))

(define (generate-config-from-markdown md-file output-name)
  "从 Markdown 文件提取 Scheme 代码块生成配置文件"
  (let ((md-path (string-append configs-dir "/" md-file))
        (output-path (string-append tmp-dir "/" output-name)))
    ($ (list "mkdir" "-p" tmp-dir))
    (let ((scheme-content (extract-scheme-blocks-from-markdown md-path)))
      (with-output-to-file output-path
        (lambda ()
          (for-each display scheme-content))))
    ;; 格式化代码，忽略错误输出
    (system* "guix" "style" "--whole-file" output-path)))

;;; Maak任务定义

(define (generate-init-config)
  (generate-config-from-markdown "init-config.md" "init-config.scm"))

(define (generate-system-config)
  (generate-config-from-markdown "system-config.md" "system-config.scm"))

(define (generate-home-config)
  (generate-config-from-markdown "home-config.md" "home-config.scm"))

(define (tmprm)
  "清理临时文件"
  ($ (list "rm" "-rf" tmp-dir)))

;; 安装系统
(define (init)
  "安装系统"
  (generate-init-config)
  (log-info "正在安装系统")
  ($guix `("system" "init"
           ,(string-append tmp-dir "/init-config.scm") "/mnt"))
  (tmprm))

(define (system)
  "应用系统配置"
  (generate-system-config)
  (log-info "正在应用系统配置")
  ($guix `("system" "reconfigure"
           ,(string-append tmp-dir "/system-config.scm") "--allow-downgrades"
           "--fallback"))
  (tmprm))

(define (home)
  "应用用户配置"
  (generate-home-config)
  (log-info "正在应用用户配置")
  ($guix `("home" "reconfigure"
           ,(string-append tmp-dir "/home-config.scm") "--allow-downgrades"
           "--fallback"))
  (tmprm))

(define (rebuild)
  "应用全局配置"
  (system)
  (home)
  ($guix `("locate" "--update")))

(define* (update-channels)
  "更新 channel lock 文件"
  (write-file-atomically channel-lock
                         (cut with-output-to-port <>
                              (lambda ()
                                ($guix `("describe" "--format=channels")
                                       #:channels channel-fresh)))))



(define (upgrade)
  "更新lock file"
  ($ (list "git" "submodule" "update"))
  (update-channels)
  ($ (list "git"
           "commit"
           "-S"
           "-m"
           "bump version."
           channel-lock)))

(define (pull)
  "拉取channel"
  ($guix `("pull" "--allow-downgrades" "--fallback")))

(define (clean)
  "清除额外的配置(慎用)"
  ($ (list "sh" "-c" "sudo guix system delete-generations > /dev/null"))
  ($ (list "sh" "-c" "guix home delete-generations > /dev/null")))

(define (gc)
  "清除额外的文件(慎用)"
  (clean)
  ($ (list "guix" "gc"))
  ($ (list "sudo" "rm" "-rf" "/boot/EFI/Guix/OLD-*.EFI")))

(define (reuse)
  "生成版权信息头"
  ($ (list "reuse"
           "annotate"
           "--copyright"
           "BrokenShine <xchai404@gmail.com>"
           "--license"
           "GPL-3.0"
           "--skip-unrecognised"
           "--recursive"
           "--year"
           (strftime "%Y"
                     (localtime (time-second (current-time))))
           ".")))

(define (style-all)
  "格式化所有代码"
  (log-info "格式化所有代码")
  ($ (list "find . -maxdepth 8 -name '*.scm'" "-type f -exec guix style -f {} \\;")
     #:verbose? #t))

(define (default)
  ($ (list "maak" "--list")))
