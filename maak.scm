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
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 popen))

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
  "执行命令列表，非零退出时抛出错误。
收到 SIGINT(Ctrl+C) 时终止子进程并以 130 退出 —— 用 primitive-fork+waitpid
替代 system*，后者是 C 原语，会在 waitpid 的 EINTR 重试中吞掉信号导致 Ctrl+C 无响应。"
  (let ((pid (primitive-fork)))
    (if (zero? pid)
        ;; 子进程：exec 命令（失败则 127）
        (catch #t
               (lambda () (apply execlp (car cmd) (car cmd) (cdr cmd)))
               (lambda args (primitive-exit 127)))
        ;; 父进程：装 SIGINT handler 再等待
        (let ((old (sigaction SIGINT)))
          (sigaction SIGINT
                     (lambda (sig)
                       (catch #t (lambda () (kill pid SIGTERM)) (lambda _ #f))
                       (primitive-exit 130)))
          (let* ((status (cdr (waitpid pid)))
                 (rc (status:exit-val status)))
            (sigaction SIGINT (car old) (cdr old))
            (cond
             ((not rc) (primitive-exit 130))   ; 子进程被信号杀死（Ctrl+C 连带等）
             ((zero? rc) #t)
             (else (error (format #f "Command failed (~a): ~a" rc cmd)))))))))

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
              ((> o c) (log-error "多 ~a 个左括号 (开=~a 关=~a)~%" (- o c) o c) #f)
              (else    (log-error "多 ~a 个右括号 (开=~a 关=~a)~%" (- c o) o c) #f))))))

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

(define (append-to-file file text)
  "在 FILE 末尾追加 TEXT"
  (let ((port (open-file file "a")))
    (display text port)
    (close-port port)))

(define (prepare-config tail-var)
  "准备配置：tangle → 末尾追加 TAIL-VAR → 括号检查，返回 scm 路径"
  (tangle)
  (let ((scm (string-append tmp-dir "/config.scm")))
    (append-to-file scm (string-append "\n" tail-var "\n"))
    (unless (check-paren-balance scm)
      (error "配置括号检查失败"))
    scm))

(define* (apply-config subsystem tail-var #:key sudo? tail)
  "基于 prepare-config 应用配置：reconfigure（dry-run 时退化为 build --dry-run）。
SUDO? 控制提权；TAIL 为可选后续 thunk（dry-run 也会执行）。"
  (let ((scm (prepare-config tail-var)))
    (if dry-run?
        (begin
          (log-info "[DRY-RUN] 验证 ~a 配置~%" subsystem)
          ($guix `(,subsystem "build" ,scm "--dry-run")))
        (begin
          (log-info "正在应用 ~a 配置~%" subsystem)
          ($guix `(,subsystem "reconfigure" ,scm "--allow-downgrades" "--fallback")
                 #:sudo? sudo?)
          (tmprm))))
  (when tail (tail)))

;;; ============================================================
;;; 外部函数（maak 任务）
;;; ============================================================

(define (check)
  "括号平衡检查：tangle 并检查配置"
  (tangle)
  (let ((ok (check-paren-balance (string-append tmp-dir "/config.scm"))))
    (tmprm)
    (unless ok (error "括号检查未通过"))))

(define (rebuild)
  "应用系统配置（自动提权）"
  (apply-config "system" "%system"
                #:sudo? #t
                #:tail (lambda () ($guix '("locate" "--update")))))

(define (home)
  "应用用户配置"
  (apply-config "home" "%home" #:sudo? #f))

;;; --------------------------------------------------
;;; Org 块精准编辑（block-show / block-replace）
;;; --------------------------------------------------
;; 用途：Agent 修改 config.org 中单个 #+NAME: 块时，不必 read 整个 2000 行文件。
;; 参数通过 MAAK_BLOCK 环境变量传递（maak 框架零参数限制，见仓库 MAAK_DRY_RUN 先例）。
;; block-replace 失败时不自动回滚，依赖 git checkout source/config.org 兜底。
;;
;; elisp 通过临时文件 + emacs --script 执行，避免 format 双层转义地狱。
;; 所有 elisp 操作只认 #+NAME / #+begin_src / #+end_src 三标记，不进 org-mode（避免
;; syntax-table 干扰正则），与既有 tangle 函数（maak.scm:97）的 emacs --batch 模式一致。

(define (emacs-org-run elisp args)
  "把 ELISP 写到 tmp/block.el，调 emacs --batch --script 执行，ARGS 作为 command-line-args-left 传入。"
  (let ((el-tmp (string-append tmp-dir "/block.el")))
    ($ (list "mkdir" "-p" tmp-dir))
    (call-with-output-file el-tmp
      (lambda (port) (display elisp port)))
    ($ (cons* "emacs" "--batch" "--script" el-tmp args))))

;; elisp 提取脚本：定位 NAME 行 → begin_src → end_src，输出 lang / noweb-flag / body
(define block-extract-el
  "(let* ((file (nth 0 command-line-args-left))
         (name (nth 1 command-line-args-left))
         lang body has-noweb)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward
             (concat \"^#[+]NAME:[[:space:]]+\" (regexp-quote name) \"[[:space:]]*$\") nil t)
        (forward-line 1)
        (when (re-search-forward \"^#[+]begin_src[[:space:]]+\\\\([^[:space:]\\n]+\\\\)\" nil t)
          (setq lang (match-string-no-properties 1))
          (forward-line 1)
          (let ((body-start (point)))
            (when (re-search-forward \"^#[+]end_src\" nil t)
              (setq body (buffer-substring-no-properties
                          body-start (line-beginning-position)))
              (setq has-noweb (string-match-p \"<<[^>]+>>\" body))))))
      (princ (format \"%s\\n%s\\n\" (or lang \"\") (if has-noweb \"noweb\" \"plain\")))
      (when body (princ (string-trim body \"\\n\" \"\\n\"))))
    (kill-emacs 0))")

;; elisp 替换脚本：读 body-file 内容，替换块 body，写到 out-file（不覆盖原文件）
(define block-replace-el
  "(let* ((file (nth 0 command-line-args-left))
         (name (nth 1 command-line-args-left))
         (body-file (nth 2 command-line-args-left))
         (out-file (nth 3 command-line-args-left))
         (new-body (with-temp-buffer
                     (insert-file-contents body-file)
                     (buffer-string))))
    (find-file file)
    (goto-char (point-min))
    (let (lang replaced)
      (when (re-search-forward
             (concat \"^#[+]NAME:[[:space:]]+\" (regexp-quote name) \"[[:space:]]*$\") nil t)
        (forward-line 1)
        (when (re-search-forward \"^#[+]begin_src[[:space:]]+\\\\([^[:space:]\\n]+\\\\)\" nil t)
          (setq lang (match-string-no-properties 1))
          (forward-line 1)
          (let ((body-start (point)))
            (when (re-search-forward \"^#[+]end_src\" nil t)
              (let ((body-end (line-beginning-position)))
                (delete-region body-start body-end)
                (goto-char body-start)
                (insert (string-trim-right new-body \"\\n\") \"\\n\")
                (setq replaced t))))))
      (if replaced
          (progn (write-region (point-min) (point-max) out-file)
                 (princ (format \"lang=%s\\n\" (or lang \"\")))
                 (princ (format \"[OK] block %s replaced, written to %s\\n\" name out-file)))
        (progn (princ (format \"[ERROR] block %s not found\\n\" name)) (kill-emacs 1)))))")

(define (block-show)
  "提取 #+NAME: $MAAK_BLOCK 块的 body 到 tmp/block-<name>.scm，stdout 打印文件路径。
   输出文件首两行是 lang= 和 noweb/plain 标记，随后是块 body。
   用法: MAAK_BLOCK=<name> maak block-show → 输出 tmp/block-<name>.scm 路径
   Agent 拿到含 <<ref>> 的 body 后，应自行读取被引用块。"
  (let* ((name (or (getenv "MAAK_BLOCK")
                   (error "MAAK_BLOCK 未设置，用法: MAAK_BLOCK=<name> maak block-show")))
         (el-tmp (string-append tmp-dir "/block-show.el"))
         (out-file (string-append tmp-dir "/block-" name ".scm")))
    ($ (list "mkdir" "-p" tmp-dir))
    (call-with-output-file el-tmp
      (lambda (port) (display block-extract-el port)))
    (with-output-to-file out-file
      (lambda ()
        (let ((pipe (open-input-pipe
                     (string-join
                      `(,(string-append "emacs --batch --script " el-tmp)
                        ,configs-rawfile ,name) " "))))
          (let loop ((line (read-line pipe)))
            (unless (eof-object? line)
              (display line) (newline)
              (loop (read-line pipe))))
          (close-pipe pipe))))
    (display out-file) (newline)))

(define (block-replace)
  "用 stdin 内容替换 #+NAME: $MAAK_BLOCK 块的 body，原子写回 + 自动括号验证（仅 scheme 块）。
   用法: cat new-body.scm | MAAK_BLOCK=<name> maak block-replace
   非 scheme 块（fish/bash/js 等）跳过括号验证；失败时不自动回滚，用 git checkout source/config.org 恢复。"
  (let* ((name (or (getenv "MAAK_BLOCK")
                   (error "MAAK_BLOCK 未设置，用法: cat new.scm | MAAK_BLOCK=<name> maak block-replace")))
         (new-file (string-append tmp-dir "/block-new.scm"))
         (out-org (string-append tmp-dir "/config.org.new")))
    ($ (list "mkdir" "-p" tmp-dir))
    ;; 1. 读 stdin（管道式调用必须先读；非管道调用会阻塞于此）
    ($ (list "sh" "-c" (string-append "cat > " new-file)))
    ;; 2. 把 block-replace-el 写到 tmp/block-replace.el
    (let ((el-tmp (string-append tmp-dir "/block-replace.el")))
      (call-with-output-file el-tmp
        (lambda (port) (display block-replace-el port)))
      ;; 3. emacs 替换并写到 tmp/config.org.new（同时输出块语言）
      (let* ((probe (open-input-pipe
                     (string-join
                      `(,(string-append "emacs --batch --script " el-tmp)
                        ,configs-rawfile ,name ,new-file ,out-org) " ")))
             (lang-line (read-line probe)))
        (close-pipe probe)
        (let ((lang (if (string-prefix? "lang=" lang-line)
                        (substring lang-line 5)
                        "")))
          ;; 4. 原子写回 source/config.org
          (let ((content (call-with-input-file out-org get-string-all)))
            (write-file-atomically configs-rawfile
                                   (lambda (port) (display content port))))
          ;; 5. 仅 scheme 块做括号验证（tangle 全文件后检查）
          (cond
           ((string=? lang "scheme")
            (tangle)
            (let ((ok (check-paren-balance (string-append tmp-dir "/config.scm"))))
              (tmprm)
              (if ok
                  (log-info "[OK] 块 ~a 替换成功且括号验证通过~%" name)
                  (begin
                    (log-error "括号验证失败！请用以下命令回滚:~%")
                    (log-error "  git checkout ~a~%" configs-rawfile)
                    (error "block-replace 括号验证失败")))))
           (else
            (tmprm)
            (log-info "[OK] 块 ~a (~a) 替换成功（非 scheme 块跳过括号验证）~%" name lang))))))))

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
  (let ((scm (prepare-config "%system")))
    (log-info "正在安装系统~%")
    ($guix `("system" "init" ,scm "/mnt") #:sudo? #t)
    (tmprm)))

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

; 注意：$guix 走 $ (fork+exec)，子进程 stdout 继承终端而非 Guile port，
; 不能用 with-output-to-port 捕获。改用 open-input-pipe 直接捕获子进程 stdout。
(define (update)
  "更新 channel.lock 并签名提交"
  (let* ((cmd (string-join
               `("guix" "time-machine"
                 ,(string-append "--channels=" channel-fresh) "--"
                 "describe" "--format=channels") " "))
         (pipe (open-input-pipe cmd))
         (content (get-string-all pipe)))
    (close-pipe pipe)
    (write-file-atomically channel-lock
      (lambda (port) (display content port)))
    ($ (list "git" "commit" "-S" "-m"
             "UPDATE: (channel.lock) bump version."
             channel-lock))))
