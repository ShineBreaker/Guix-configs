;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define-module (maak)
  #:declarative? #t
  #:use-module (maak maak)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-19)
  #:use-module (srfi srfi-26)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 rdelim))

;;; 辅助函数：原子性文件写入
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

;;; Dry-run 支持：设置 MAAK_DRY_RUN=1 环境变量启用
;;; 启用后 system/home 仅 tangle org + 构建检查，不实际应用配置
(define dry-run?
  (let ((val (getenv "MAAK_DRY_RUN")))
    (and val (not (string-null? val)))))

;;; 配置路径
(define repo-root (getcwd))
(define home-dir (getenv "HOME"))
(define dotfiles-dir
  (string-append repo-root "/dotfiles"))
(define mutable-dir
  (string-append dotfiles-dir "/mutable"))

(define (stow-dotfiles)
  "重新链接 stow 管理的 dotfiles（扫描 mutable 目录下的子文件夹）"
  (let ((packages (scandir mutable-dir
                           (lambda (name)
                             (and (not (string-prefix? "." name))
                                  (file-is-directory?
                                   (string-append mutable-dir "/" name)))))))
    (log-info "正在删除旧的 dotfiles 链接: ~a" (string-join packages " "))
    (for-each
     (lambda (pkg)
       ($ `("stow" "-d" ,mutable-dir "-t" ,home-dir "-D" ,pkg)))
     packages)
    (log-info "正在重新链接 dotfiles")
    (for-each
     (lambda (pkg)
       ($ `("stow" "-d" ,mutable-dir "-t" ,home-dir ,pkg)))
     packages)))

(define configs-dir
  (string-append repo-root "/source/configs"))
(define nix-dir
  (string-append repo-root "/source/nix"))
(define tmp-dir
  (string-append repo-root "/tmp"))

(define channel-fresh
  (string-append configs-dir "/../channel.scm"))
(define channel-lock
  (string-append configs-dir "/../channel.lock"))

;; 方便调试所添加的相关内容
(define ($ cmd)
  (let ((exit-code (status:exit-val (apply system* cmd))))
    (or (zero? exit-code)
        (error (format #f "
Non-zero exit code when running!
Command: ~a
Exit code: ~a~%" cmd exit-code)))))

;; 手动包装的 guix 命令
;; 主要是要求其使用 time-machine ，用于锁频道的 commit
;; #:sudo? 为 #t 时在命令前添加 sudo（用于 system reconfigure 等需要特权的操作）
(define* ($guix args
                #:key (channels channel-lock) (sudo? #f))
  (let ((base-cmd `("guix" "time-machine"
                    ,(string-append "--channels=" channels) "--"
                    ,@args)))
    ($ (if sudo? (cons "sudo" base-cmd) base-cmd))))

;;; 括号平衡检查
(define (count-parens port)
  "读取 PORT 中的所有字符，返回 (open . close) 括号计数"
  (let loop ((c (read-char port)) (opens 0) (closes 0))
    (cond
     ((eof-object? c) (cons opens closes))
     ((eq? c #\() (loop (read-char port) (+ opens 1) closes))
     ((eq? c #\)) (loop (read-char port) opens (+ closes 1)))
     ((eq? c #\")
      ;; 跳过字符串内容
      (let string-loop ((c (read-char port)))
        (cond
         ((eof-object? c) (cons opens closes))
         ((eq? c #\") (loop (read-char port) opens closes))
         ((eq? c #\\) (read-char port) (string-loop (read-char port)))
         (else (string-loop (read-char port))))))
     ((eq? c #\;)
      ;; 跳过注释到行尾
      (let comment-loop ((c (read-char port)))
        (cond
         ((eof-object? c) (cons opens closes))
         ((eq? c #\newline) (loop (read-char port) opens closes))
         (else (comment-loop (read-char port))))))
     (else (loop (read-char port) opens closes)))))

(define (check-paren-balance file)
  "检查 FILE 的括号平衡，返回 #t 如果平衡，否则返回 #f 并打印错误"
  (call-with-input-file file
    (lambda (port)
      (let* ((result (count-parens port))
             (opens (car result))
             (closes (cdr result)))
        (cond
         ((= opens closes)
          (log-info "括号平衡检查通过: ~a 对括号~%" opens)
          #t)
         ((> opens closes)
          (log-error "括号不平衡: 多 ~a 个左括号 (开=~a, 关=~a)~%"
                     (- opens closes) opens closes)
          #f)
         (else
          (log-error "括号不平衡: 多 ~a 个右括号 (开=~a, 关=~a)~%"
                     (- closes opens) opens closes)
          #f))))))

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

;;; Maak任务定义
(define (generate-system-config)
  (generate-config-from-org "system-config.org"))

(define (generate-home-config)
  (generate-config-from-org "home-config.org"))

(define (tmprm)
  "清理临时文件"
  ($ (list "rm" "-rf" tmp-dir)))

;; 安装系统
(define (init)
  "安装系统（自动提权）"
  (generate-system-config)
  (log-info "正在安装系统")
  ($guix `("system" "init"
           ,(string-append tmp-dir "/system-config.scm") "/mnt")
         #:sudo? #t)
  (tmprm))

(define (system)
  "应用系统配置（自动提权）"
  (generate-system-config)
  (unless (check-paren-balance (string-append tmp-dir "/system-config.scm"))
    (error "系统配置括号检查失败，中止"))
  (if dry-run?
      (begin
        (log-info "[DRY-RUN] 验证系统配置（仅构建检查，不会应用）")
        ($guix `("system" "build"
                 ,(string-append tmp-dir "/system-config.scm")
                 "--dry-run")))
      (begin
        (log-info "正在应用系统配置")
        ($guix `("system" "reconfigure"
                 ,(string-append tmp-dir "/system-config.scm") "--allow-downgrades"
                 "--fallback")
               #:sudo? #t)
        (tmprm))))

(define (home)
  "应用用户配置"
  (generate-home-config)
  (unless (check-paren-balance (string-append tmp-dir "/home-config.scm"))
    (error "用户配置括号检查失败，中止"))
  (if dry-run?
      (begin
        (log-info "[DRY-RUN] 验证用户配置（仅构建检查，不会应用）")
        ($guix `("home" "build"
                 ,(string-append tmp-dir "/home-config.scm")
                 "--dry-run")))
      (begin
        (log-info "正在应用用户配置")
        ($guix `("home" "reconfigure"
                 ,(string-append tmp-dir "/home-config.scm") "--allow-downgrades"
                 "--fallback"))
        (stow-dotfiles)
        (tmprm))))

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
           "UPDATE: (channel.lock) bump version."
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

(define (nix)
  "安装nix包"
  ($ (list (string-append home-dir "/.nix-profile/bin/home-manager") "switch" "-b" "backup" "--flake" (string-append nix-dir "/#Guix") "--extra-experimental-features" "nix-command" "--extra-experimental-features" "flakes")))

(define (nix-init)
  "初始化nix"
  ($ (list "nix-channel" "--add" "https://github.com/nix-community/home-manager/archive/master.tar.gz" "home-manager"))
  ($ (list "nix-channel" "--update"))
  ($ (list "nix-shell" "<home-manager>" "-A" "install")))

(define (nix-update)
  "更新nix包"
  ($ (list "nix-channel" "--update"))
  ($ (list "nix" "flake" "update" "--flake" nix-dir)))

(define (check)
  "括号平衡检查：tangle 并检查 system + home 配置"
  (generate-system-config)
  (generate-home-config)
  (let ((sys-ok (check-paren-balance (string-append tmp-dir "/system-config.scm")))
        (home-ok (check-paren-balance (string-append tmp-dir "/home-config.scm"))))
    (tmprm)
    (unless (and sys-ok home-ok)
      (error "括号检查未通过"))))

(define (check-system)
  "括号平衡检查：仅检查 system 配置"
  (generate-system-config)
  (let ((ok (check-paren-balance (string-append tmp-dir "/system-config.scm"))))
    (tmprm)
    (unless ok
      (error "系统配置括号检查未通过"))))

(define (check-home)
  "括号平衡检查：仅检查 home 配置"
  (generate-home-config)
  (let ((ok (check-paren-balance (string-append tmp-dir "/home-config.scm"))))
    (tmprm)
    (unless ok
      (error "用户配置括号检查未通过"))))

(define (default)
  ($ (list "maak" "--list")))
