;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: GPL-3.0

(define-module (maak)
  #:declarative? #t
  #:use-module (maak maak)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-19)
  #:use-module (srfi srfi-26)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 textual-ports))

;;; 配置路径
(define repo-root
  (getcwd))
(define configs-dir
  (string-append repo-root "/configs"))
(define configen-dir
  (string-append configs-dir "/main"))
(define tmp-dir
  (string-append repo-root "/tmp"))
(define channel-fresh
  (string-append configs-dir "/channel.scm"))
(define channel-lock
  (string-append configs-dir "/channel.lock"))

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

;;; 配置文件生成逻辑
(define loaded-files
  (make-hash-table))

(define (process-content file-path load-root)
  "递归处理配置文件，展开(load ...)语句"
  (let ((full-path (canonicalize-path file-path)))
    (when (and (file-exists? full-path)
               (not (hash-ref loaded-files full-path)))
      (hash-set! loaded-files full-path #t)
      (let ((base-dir (dirname full-path))
            (load-root* (or load-root
                            (dirname full-path))))
        (call-with-input-file full-path
          (lambda (port)
            (let loop
              ((line (get-line port)))
              (unless (eof-object? line)
                (let ((match (string-match
                              "^[[:space:]]*\\(load[[:space:]]+\"(\\.\\.?/[^\"]+)\"[[:space:]]*\\)[[:space:]]*$"
                              line)))
                  (if match
                      (let* ((relative-path (match:substring match 1))
                             (target-path (if (string-prefix? "./"
                                                              relative-path)
                                              (string-append load-root* "/"
                                                             (substring
                                                              relative-path 2))
                                              (string-append base-dir "/"
                                                             relative-path))))
                        (display "\n;\n")
                        (format #t "; ====== 来自 ~a ======\n" relative-path)
                        (display ";\n")
                        (process-content target-path load-root*))
                      (display line))
                  (newline))
                (loop (get-line port))))))))))

(define (generate-config input-name output-name desc)
  "生成完整的配置文件"
  (let ((input-path (string-append configen-dir "/" input-name))
        (output-path (string-append tmp-dir "/" output-name)))
    (log-info "正在生成完整配置文件: ~a (~a)" output-path desc)
    (set! loaded-files
          (make-hash-table))
    ($ (list "mkdir" "-p" tmp-dir))
    (with-output-to-file output-path
      (lambda ()
        (format #t ";;; 自动生成的完整配置文件\n")
        (format #t ";;; 原始文件: ~a\n" input-path)
        (format #t ";;; 生成时间: ~a\n\n"
                (strftime "%Y-%m-%d %H:%M:%S"
                          (localtime (time-second (current-time)))))
        (process-content input-path configs-dir)))
    ($ (list "sed" "-i" "-E"
             "/^[[:space:]]*\\(load[[:space:]]+\".*\"\\)[[:space:]]*$/d"
             output-path))
    ($ (list "guix" "style" "--whole-file" output-path))
    (log-info "✓ 成功生成: ~a" output-path)))

;;; Maak任务定义

(define (generate-init-config)
  "生成用于安装系统的配置文件"
  (generate-config "init-config.scm" "init-config.scm" "安装配置"))

(define (generate-system-config)
  "只生成系统配置"
  (generate-config "system-config.scm" "system-config.scm" "系统配置"))

(define (generate-home-config)
  "只生成home配置"
  (generate-config "home-config.scm" "home-config.scm" "Home 配置"))

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
  (with-atomic-file-output channel-lock
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
  ($ '("find . -maxdepth 8 -name '*.scm'" "-type f -exec guix style -f {} \\;")
     #:verbose? #t))

(define (default)
  ($ (list "maak" "--list")))
