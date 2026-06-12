;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

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

;;; ============================================================
;;; 常量
;;; ============================================================

(define repo-root         (getcwd))
(define home-dir          (getenv "HOME"))
(define configs-rawfile   (string-append repo-root "/source/config.org"))
(define nix-dir           (string-append repo-root "/source/nix"))
(define tmp-dir           (string-append repo-root "/tmp"))
(define channel-fresh     (string-append repo-root "/source/channel.scm"))
(define channel-lock      (string-append repo-root "/source/channel.lock"))

(define dry-run?
  (let ((v (getenv "MAAK_DRY_RUN")))
    (and v (not (string-null? v)))))

;;; ============================================================
;;; 内部函数
;;; ============================================================

(define ($ cmd)
  "执行命令列表，非零退出时抛出错误"
  (let ((rc (status:exit-val (apply system* cmd))))
    (or (zero? rc)
        (error (format #f "Command failed (~a): ~a" rc cmd)))))

(define* ($guix args #:key (channels channel-lock) (sudo? #f))
  "guix time-machine 封装，锁定频道版本"
  (let ((cmd `("guix" "time-machine"
               ,(string-append "--channels=" channels) "--"
               ,@args)))
    ($ (if sudo? (cons "sudo" cmd) cmd))))

(define (count-parens port)
  "返回 (open . close) 括号计数，跳过字符串和注释"
  (let loop ((c (read-char port)) (opens 0) (closes 0))
    (cond
     ((eof-object? c) (cons opens closes))
     ((eq? c #\() (loop (read-char port) (+ opens 1) closes))
     ((eq? c #\)) (loop (read-char port) opens (+ closes 1)))
     ((eq? c #\")
      (let sl ((c (read-char port)))
        (cond ((eof-object? c) (cons opens closes))
              ((eq? c #\") (loop (read-char port) opens closes))
              ((eq? c #\\) (read-char port) (sl (read-char port)))
              (else (sl (read-char port))))))
     ((eq? c #\;)
      (let cl ((c (read-char port)))
        (cond ((eof-object? c) (cons opens closes))
              ((eq? c #\newline) (loop (read-char port) opens closes))
              (else (cl (read-char port))))))
     (else (loop (read-char port) opens closes)))))

(define (check-paren-balance file)
  "检查 FILE 括号平衡，平衡返回 #t"
  (call-with-input-file file
    (lambda (port)
      (let* ((r (count-parens port))
             (o (car r)) (c (cdr r)))
        (cond ((= o c) (log-info "括号平衡检查通过: ~a 对括号~%" o) #t)
              ((> o c) (log-error "多 ~a 个左括号 (开=~a 关=~a)" (- o c) o c) #f)
              (else    (log-error "多 ~a 个右括号 (开=~a 关=~a)" (- c o) o c) #f))))))

(define (tangle)
  "用 org-babel-tangle 导出单个 Org 文件到 tmp/"
  ($ (list "mkdir" "-p" tmp-dir))
  ($ (list "emacs" "--batch" "-l" "org" "--eval" "(require 'ob-tangle)"
           "--eval" (format #f "(org-babel-tangle-file \"~a\")" configs-rawfile))))

(define* (tmprm #:optional _)
  "清理 tmp/"
  ($ (list "rm" "-rf" tmp-dir)))

(define (write-file-atomically file thunk)
  "原子写入 FILE，THUNK 接收输出端口"
  (let* ((tmpl (string-append file ".XXXXXX"))
         (port (mkstemp! tmpl)))
    (with-throw-handler #t
                        (lambda () (thunk port) (force-output port) (close-port port)
                                (rename-file tmpl file))
                        (lambda _
                          (false-if-exception (delete-file tmpl))
                          (false-if-exception (close-port port))))))

(define (rebuild)
  "应用配置（自动提权）"
  (tangle)
  (let ((scm (string-append tmp-dir "/config.scm")))
    (unless (check-paren-balance scm)
      (error "配置括号检查失败"))
    (if dry-run?
        (begin
          (log-info "[DRY-RUN] 验证配置")
          ($guix `("system" "build" ,scm "--dry-run")))
        (begin
          (log-info "正在应用配置")
          ($guix `("system" "reconfigure" ,scm "--allow-downgrades" "--fallback")
                 #:sudo? #t)
          (tmprm))))
  ($guix '("locate" "--update")))

;;; ============================================================
;;; 外部函数（maak 任务）
;;; ============================================================

(define (check)
  "括号平衡检查：tangle 并检查配置"
  (tangle)
  (let ((ok (check-paren-balance (string-append tmp-dir "/config.scm"))))
    (tmprm)
    (unless ok (error "括号检查未通过"))))

(define (clean)
  "删除所有旧的 system/home generations（慎用）"
  ($ (list "sh" "-c" "sudo guix system delete-generations > /dev/null"))
  ($ (list "sh" "-c" "guix home delete-generations > /dev/null")))

(define artifact-rules
  '(;; (pattern  type)
    ;; type: directory → find -type d -name <pattern> -exec rm -rf
    ;;       file     → find -type f -name <pattern> -delete
    ("__pycache__"   directory)
    ("*.elc"         file)
    ("*.o"           file)
    ("*.a"           file)
    ("*.so"          file)))

(define (clean-artifacts)
  "递归删除仓库内所有编译产物"
  (for-each
   (lambda (rule)
     (let ((pattern (car rule))
           (type    (cadr rule)))
       (if (eq? type 'directory)
           ($ (list "find" repo-root
                    "-type" "d" "-name" pattern
                    "-not" "-path" "*/.git/*"
                    "-print" "-exec" "rm" "-rf" "{}" "+"))
           ($ (list "find" repo-root
                    "-type" "f" "-name" pattern
                    "-not" "-path" "*/.git/*"
                    "-print" "-delete")))))
   artifact-rules))

(define (gc)
  "clean + guix gc + 清理旧 EFI 文件（慎用，直接操作 /boot）"
  (clean)
  ($ (list "guix" "gc"))
  ($ (list "sudo" "rm" "-rf" "/boot/EFI/Guix/OLD-*.EFI")))

(define (init)
  "安装系统到 /mnt（自动提权）"
  (tangle)
  (log-info "正在安装系统")
  ($guix `("system" "init"
           ,(string-append tmp-dir "/config.scm") "/mnt")
         #:sudo? #t)
  (tmprm))

(define (nix)
  "应用 nix home-manager 配置"
  ($ (list (string-append home-dir "/.nix-profile/bin/home-manager")
           "switch" "-b" "backup"
           "--flake" (string-append nix-dir "/#Guix")
           "--extra-experimental-features" "nix-command"
           "--extra-experimental-features" "flakes")))

(define (nix-init)
  "初始化 nix channel 并安装 home-manager"
  ($ (list "nix-channel" "--update"))
  ($ (list "nix-shell" "<home-manager>" "-A" "install")))

(define (nix-update)
  "更新 nix channel 与 flake"
  ($ (list "nix-channel" "--update"))
  ($ (list "nix" "flake" "update" "--flake" nix-dir)))

(define (pull)
  "拉取频道（guix pull）"
  ($guix '("pull" "--allow-downgrades" "--fallback")))



(define (reuse)
  "为所有文件添加 SPDX 版权头"
  ($ `("reuse" "annotate"
       "--copyright" "BrokenShine <xchai404@gmail.com>"
       "--license" "MIT"
       "--skip-unrecognised" "--recursive"
       "--year" ,(strftime "%Y" (localtime (time-second (current-time))))
       ".")))



(define (update)
  "更新 channel.lock 并签名提交"
  (write-file-atomically
   channel-lock
   (cut with-output-to-port <>
        (lambda ()
          ($guix '("describe" "--format=channels")
                 #:channels channel-fresh))))
  ($ (list "git" "commit" "-S" "-m"
           "UPDATE: (channel.lock) bump version."
           channel-lock)))
