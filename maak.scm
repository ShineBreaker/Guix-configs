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

;;; ============================================================
;;; secret-scan: 扫描文本配置中的凭据泄漏（Oracle 2026-06-16 建议的兜底工具）
;;; ============================================================
;;; 常用调用：
;;;   maak secret-scan                                          扫描 dotfiles/enable
;;;   MAAK_SECRET_SCAN_DIR=. maak secret-scan                   扫描整个仓库
;;;   MAAK_SECRET_SCAN_FAIL_ON_FIND=0 maak secret-scan          只警告不退出非零
;;;   MAAK_SECRET_SCAN_EXTRA_PATTERN='foo,bar' maak secret-scan 追加自定义正则（逗号分隔）
;;; 设计取舍：
;;; - 用 grep -HrnIE 递归 + --include 扩展名白名单 + --exclude-dir 排除目录（严格遵循 -rI）
;;; - >1MB 文件在 Scheme 层按 stat:size 过滤（GNU grep 无 --max-filesize，该过滤与 -r 不兼容，
;;;   故在命中后逐条 stat 判定；命中数稀疏，开销可忽略）
;;; - 每条规则一次 grep，命中行经 ice-9 regex 解析为 [HINT] path:lineno:rule:content(截 80)

(define %secret-exts
  '("*.conf" "*.toml" "*.yaml" "*.yml" "*.json" "*.ini" "*.cfg"
    "*.gitconfig" "*.scm" "*.fish" "*.el" "*.env" "*.netrc" "*.properties"))

(define %secret-exclude-dirs
  '(".git" ".agents" "node_modules" "tmp"))

(define %secret-patterns
  '(("github-pat"     . "ghp_[A-Za-z0-9]{36}")        ; GitHub PAT
    ("github-oauth"   . "gho_[A-Za-z0-9]{36}")        ; GitHub OAuth
    ("github-user"    . "ghu_[A-Za-z0-9]{36}")        ; GitHub user token
    ("github-server"  . "ghs_[A-Za-z0-9]{36}")        ; GitHub server token
    ("github-refresh" . "ghr_[A-Za-z0-9]{36}")        ; GitHub refresh token
    ("openai"         . "sk-[A-Za-z0-9]{20,}")
    ("anthropic"      . "sk-ant-[A-Za-z0-9-]{20,}")
    ("openrouter"     . "sk-or-[A-Za-z0-9-]{20,}")
    ("xai"            . "xai-[A-Za-z0-9]{20,}")
    ("google-api"     . "AIza[A-Za-z0-9_-]{35}")
    ("aws-access-key" . "AKIA[0-9A-Z]{16}")
    ("gitlab"         . "glpat-[A-Za-z0-9_-]{20,}")
    ("slack"          . "xox[bpars]-[A-Za-z0-9-]{10,}")
    ("private-key"    . "-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----")
    ("oauth-token"    . "oauth_token[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_-]{16,}")
    ("api-key"        . "api[_-]key[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_-]{16,}")
    ("access-token"   . "access_token[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_-]{16,}")
    ("password"       . "password[[:space:]]*[:=][[:space:]]*[\"'][^\"']{8,}[\"']")))

(define (%secret-shell-quote s)
  "POSIX 单引号转义，安全传递含正则元字符的参数给 grep -e"
  (string-append "'" (string-join (string-split s #\') "'\\''") "'"))

(define (%secret-grep-flags-and-opts flags)
  "FLAGS（如 \"grep -HrnIE\" / \"grep -rIl\"）+ --include 扩展名白名单 + --exclude-dir 选项串。
   带参数是为了不被 maak 当成任务列出（框架自省所有零参数 define）。"
  (string-append
   flags " "
   (string-join (map (lambda (e) (%secret-shell-quote (string-append "--include=" e)))
                     %secret-exts) " ")
   " "
   (string-join (map (lambda (d) (%secret-shell-quote (string-append "--exclude-dir=" d)))
                     %secret-exclude-dirs) " ")))

(define (%secret-pipe->lines cmd)
  "通过 open-input-pipe 执行 shell 命令 CMD（字符串），返回 stdout 行列表（不含换行）"
  (let ((pipe (open-input-pipe cmd)))
    (let loop ((acc '()))
      (let ((line (read-line pipe)))
        (if (eof-object? line)
            (begin (close-pipe pipe) (reverse acc))
            (loop (cons line acc)))))))

(define (%secret-count-files dir)
  "统计 dir 内符合扫描范围的文件数（grep -rIl 列出含任意字符的文件，范围与扫描一致）"
  (let* ((cmd (string-append (%secret-grep-flags-and-opts "grep -rIl")
                             " -e '.' " (%secret-shell-quote dir)
                             " 2>/dev/null | wc -l"))
         (out (%secret-pipe->lines cmd)))
    (if (null? out) 0 (or (string->number (string-trim-both (car out))) 0))))

(define (secret-scan)
  "扫描 dotfiles 中的凭据泄漏"
  (let* ((dir (let ((v (getenv "MAAK_SECRET_SCAN_DIR")))
                (if (and v (not (string-null? v))) v "dotfiles/enable")))
         (fail? (not (string=? (or (getenv "MAAK_SECRET_SCAN_FAIL_ON_FIND") "1") "0")))
         (extra (getenv "MAAK_SECRET_SCAN_EXTRA_PATTERN"))
         (patterns (append %secret-patterns
                           (if (and extra (not (string-null? extra)))
                               (map (lambda (p) (cons "user-pattern" p))
                                    (string-split extra #\,))
                               '())))
         (nfiles (%secret-count-files dir))
         (found 0))
    (for-each
     (lambda (rule)
       (let* ((name (car rule))
              (pat  (cdr rule))
              (cmd  (string-append (%secret-grep-flags-and-opts "grep -HrnIE")
                                   " -e " (%secret-shell-quote pat)
                                   " " (%secret-shell-quote dir) " 2>/dev/null"))
              (hits (%secret-pipe->lines cmd)))
         (for-each
          (lambda (raw)
            (let ((m (string-match "^([^:]+):([0-9]+):(.*)$" raw)))
              (when m
                (let* ((path    (match:substring m 1))
                       (lineno  (match:substring m 2))
                       (content (match:substring m 3))
                       (size    (stat:size (stat path))))
                  ;; >1MB 的文件跳过（凭据极少在大文件里，且避免误报）
                  (when (< size 1048576)
                    (let ((trunc (if (> (string-length content) 80)
                                     (substring content 0 80) content)))
                      (display (string-append "[HINT] " path ":" lineno ":"
                                              name ":" trunc))
                      (newline)
                      (set! found (+ found 1))))))))
          hits)))
     patterns)
    (if (zero? found)
        (log-info "[OK] No secrets found, scanned ~a files~%" nfiles)
        (begin
          (log-info "[WARN] secret-scan: ~a hit(s)~%" found)
          (when fail?
            (error (format #f
                           "secret-scan: ~a secret(s) found (set MAAK_SECRET_SCAN_FAIL_ON_FIND=0 to warn-only)"
                           found)))))
    (or (zero? found) (not fail?))))

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

;; 注意：$guix 走 $ (fork+exec)，子进程 stdout 继承终端而非 Guile port，
;; 不能用 with-output-to-port 捕获。改用 open-input-pipe 直接捕获子进程 stdout。
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

;;; ============================================================
;;; structor: 维护 AGENTS.md 中 <!-- structor:begin -->...<!-- /structor -->
;;;           标记之间的目录 tree（不依赖外部 tree 命令，自包含）
;;; ============================================================
;;; 常用调用：
;;;   maak structor                              更新所有目标 AGENTS.md
;;;   MAAK_STRUCTOR_TARGET=<path> maak structor  只更新指定文件
;;;   MAAK_STRUCTOR_DEPTH=<n> maak structor      限制递归深度（默认 4）
;;;   MAAK_STRUCTOR_DRY=1 maak structor          预览输出但不写文件
;;;
;;; 设计取舍：
;;; - 用 Scheme 递归而非 `tree` 命令 → 仓库 root 可自包含，不依赖宿主工具
;;; - 标记格式独立于 maak（`<!-- structor -->` 而非 `<!-- maak:structor -->`），
;;;   其他仓库用 justfile / Makefile 包装时也可复用同一标记约定
;;; - 跳过规则与 dotfile-services excluded 对齐（.git / .github / node_modules）
;;; - 写入用原子写（write-file-atomically），避免中途失败半写文件

(define %structor-marker-start "<!-- structor:begin -->")
(define %structor-marker-end   "<!-- /structor -->")

;; 与 dotfile-services excluded 列表对齐；避免把 .git / 子模块内部暴露到结构图
(define %structor-skip-names
  '(".git" ".github" ".agents" "node_modules"))

(define (%structor-skip? name)
  ;; scandir 默认包含 "." ".."，必须显式排除，否则递归会跳到兄弟目录
  (or (string=? name ".") (string=? name "..")
      (member name %structor-skip-names)
      (string-suffix? ".swp" name)
      (string=? name "AGENTS.md")))

(define (%structor-children dir)
  "返回 ((is-dir? . name) ...) 排序：目录在前，文件在后，字母序"
  (let* ((all (scandir dir (negate %structor-skip?)))
         (typed (map (lambda (n)
                       (let ((p (string-append dir "/" n)))
                         (cons (file-is-directory? p) n)))
                     all))
         (dirs (filter car typed))
         (files (filter (compose not car) typed)))
    (append (sort dirs (lambda (a b) (string<? (cdr a) (cdr b))))
            (sort files (lambda (a b) (string<? (cdr a) (cdr b)))))))

(define (%structor-render dir max-depth depth prefix)
  "递归渲染 DIR 的 children。PREFIX 为上层缩进，输出不含 DIR 自身行"
  (let* ((entries (%structor-children dir))
         (n (length entries)))
    (let loop ((i 0) (out '()))
      (if (>= i n)
          (reverse out)
          (let* ((entry (list-ref entries i))
                 (name (cdr entry))
                 (path (string-append dir "/" name))
                 (is-dir? (car entry))
                 (is-last? (= (+ i 1) n))
                 (connector (if is-last? "└── " "├── "))
                 (child-prefix (string-append prefix
                                              (if is-last? "    " "│   ")))
                 (line (string-append prefix connector name
                                      (if is-dir? "/" "")))
                 (children-lines
                  (if (and is-dir? (< (+ depth 1) max-depth))
                      (%structor-render path max-depth
                                        (+ depth 1) child-prefix)
                      '())))
            (loop (+ i 1)
                  (append (reverse children-lines)
                          (cons line out))))))))

(define (%structor-tree abs-dir max-depth)
  "返回 ABS-DIR 的 tree lines 列表，第一行是 DIR 的 basename + /"
  (cons (string-append (basename abs-dir) "/")
        (%structor-render abs-dir max-depth 0 "")))

(define (%structor-process-file file abs-dir depth dry?)
  "在 FILE 中替换 structor 标记为 ABS-DIR 的 tree；DRY? 为 #t 时仅打印到 stdout。
   无 marker 时直接返回（跳过写入），保证幂等且避免无谓 IO。"
  (let* ((content (call-with-input-file file get-string-all))
         (has-marker (and (string-contains content %structor-marker-start)
                          (string-contains content %structor-marker-end))))
    (if (not has-marker)
        (log-info "  跳过 ~a（无 structor 标记）~%" file)
        (let* ((lines (string-split content #\newline))
               ;; replacement 自带 begin/end marker，下次跑仍能定位
               (replacement
                (append
                 (list "<!-- structor:begin -->"
                       ""
                       "<!-- 此结构图由 maak structor 自动维护，请勿手改 -->"
                       ""
                       "```")
                 (%structor-tree abs-dir depth)
                 (list "```" "" "<!-- /structor -->"))))
          (let loop ((ls lines) (out '()) (state 'normal))
            (cond
             ((null? ls)
              (let ((new-content (string-join (reverse out) "\n")))
                (if dry?
                    (display new-content)
                    (write-file-atomically file
                                           (lambda (port) (display new-content port))))))
             (else
              (let ((line (car ls)))
                (cond
                 ((and (eq? state 'normal)
                       (string=? (string-trim-both line) %structor-marker-start))
                  (loop (cdr ls) (append (reverse replacement) out) 'in-block))
                 ((and (eq? state 'in-block)
                       (string=? (string-trim-both line) %structor-marker-end))
                  (loop (cdr ls) out 'normal))
                 ((eq? state 'normal)
                  (loop (cdr ls) (cons line out) state))
                 (else
                  ;; in-block 内除结束标记外的内容：跳过
                  (loop (cdr ls) out state)))))))))))

;; structor 扫描的目标 AGENTS.md（每个对应一个 dotfile 子目录 / 顶层结构）
;; 不包括 emacs 子模块（workspace slots 描述）和 agents/（无 "## 目录结构" 章节）
(define %structor-targets
  '("source/AGENTS.md"
    "dotfiles/AGENTS.md"
    "dotfiles/enable/utilities/AGENTS.md"
    "dotfiles/enable/terminal/AGENTS.md"
    "dotfiles/enable/system/AGENTS.md"
    "dotfiles/enable/desktop/AGENTS.md"
    "dotfiles/enable/desktop-suite/AGENTS.md"))

(define (structor)
  "扫描仓库内的 AGENTS.md，刷新 structor 标记之间的目录 tree"
  (let* ((depth (let ((v (getenv "MAAK_STRUCTOR_DEPTH")))
                  (if (and v (not (string-null? v))) (string->number v) 4)))
         (target (or (getenv "MAAK_STRUCTOR_TARGET") ""))
         (dry? (and (getenv "MAAK_STRUCTOR_DRY")
                    (not (string-null? (getenv "MAAK_STRUCTOR_DRY"))))))
    (for-each
     (lambda (rel-path)
       (when (or (string=? target "") (string=? target rel-path))
         (let* ((abs-file (string-append repo-root "/" rel-path))
                (abs-dir (string-append repo-root "/" (dirname rel-path))))
           (when (file-exists? abs-file)
             (log-info "[~a] ~a (scan=~a depth=~a)~%"
                       (if dry? "DRY" "WRITE") rel-path
                       (dirname rel-path) depth)
             (%structor-process-file abs-file abs-dir depth dry?)))))
     %structor-targets)))
