;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

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

;;; Org 文件导出逻辑
(define (generate-config-from-org org-file)
  "使用 Emacs 的 org-babel-tangle 导出 Org 文件"
  (let ((org-path (string-append configs-dir "/" org-file)))
    ($ (list "mkdir" "-p" tmp-dir))
    ;; 调用 Emacs 导出 Org 文件
    ($ (list "emacs" "--batch"
             "-l" "org"
             "--eval" "(require 'ob-tangle)"
             "--eval" (format #f "(org-babel-tangle-file \"~a\")" org-path)))))

;;; Stow 相关逻辑
(define (stow)
  "使用stow管理dotfiles"
  ($ (list "bash" "-c" "stow -d ./dotfiles -t ~ default")))

;;; Maak任务定义
(define (generate-system-config)
  ;; TODO: 等待 system-config.org 配置完成
  (generate-config-from-org "system-config.org"))

(define (generate-home-config)
  (generate-config-from-org "home-config.org"))

(define (tmprm)
  "清理临时文件"
  ($ (list "rm" "-rf" tmp-dir)))

;; 安装系统
(define (init)
  "安装系统"
  (generate-system-config)
  (log-info "正在安装系统")
  ($guix `("system" "init"
           ,(string-append tmp-dir "/system-config.scm") "/mnt"))
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
  (stow)
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
