;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

(use-modules (blue build)
             (blue types)
             (blue types blueprint)
             (blue types buildable)
             (blue types command)
             (blue types testable)
             (blue subprocess)
             (guix build utils)
             (ice-9 ftw)
             (ice-9 match)
             (ice-9 popen)
             (ice-9 rdelim)
             (ice-9 regex)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-19)
             (srfi srfi-26))

;;; ============================================================
;;; 路径
;;; ============================================================

(define %repo-root (getcwd))
(define %home-dir (getenv "HOME"))
(define %config-org (string-append %repo-root "/source/config.org"))
(define %nix-dir (string-append %repo-root "/source/nix"))
(define %tmp-dir (string-append %repo-root "/tmp"))
(define %config-scm (string-append %tmp-dir "/config.scm"))
(define %channel-scm (string-append %repo-root "/source/channel.scm"))
(define %channel-lock (string-append %repo-root "/source/channel.lock"))

(define (%env-set? name)
  (let ((value (getenv name)))
    (and value (not (string-null? value)))))

(define (%dry-run?)
  (%env-set? "GUIX_DRY_RUN"))

(define (%print-header action target)
  (format #t "\t~a\t~a~%" action target))

(define (%run command)
  (match command
    ((program . args)
     (let ((status (popen program args)))
       (unless (zero? status)
         (error (format #f "命令执行失败 (~a): ~s" status command)))
       #t))))

(define* (%guix args #:key (channels %channel-lock) sudo?)
  (let ((command `("guix" "time-machine"
                   ,(string-append "--channels=" channels) "--"
                   ,@args)))
    (%run (if sudo? (cons "sudo" command) command))))

(define (%guix-command args)
  `("guix" "time-machine"
    ,(string-append "--channels=" %channel-lock) "--"
    ,@args))

(define (%emacs-command args)
  `("env"
    "-u" "EMACSLOADPATH"
    "-u" "EMACSDATA"
    "-u" "EMACSDOC"
    "-u" "EMACSPATH"
    "-u" "INSIDE_EMACS"
    ,@(%guix-command `("shell" "emacs-minimal" "--" "emacs" ,@args))))

(define (%write-file-atomically file thunk)
  (let* ((template (string-append file ".XXXXXX"))
         (port (mkstemp! template)))
    (with-throw-handler #t
                        (lambda ()
                          (thunk port)
                          (force-output port)
                          (close-port port)
                          (rename-file template file))
                        (lambda _
                          (false-if-exception (delete-file template))
                          (false-if-exception (close-port port))))))

(define (%append-to-file file text)
  (let ((port (open-file file "a")))
    (display text port)
    (close-port port)))

(define (%pipe->string command)
  (let* ((pipe (open-input-pipe command))
         (content (get-string-all pipe))
         (status (close-pipe pipe)))
    (unless (zero? (status:exit-val status))
      (error (format #f "命令执行失败 (~a): ~a"
                     (status:exit-val status) command)))
    content))

(define (%pipe->lines command)
  (let ((pipe (open-input-pipe command)))
    (let loop ((lines '()))
      (let ((line (read-line pipe)))
        (if (eof-object? line)
            (begin
              (close-pipe pipe)
              (reverse lines))
            (loop (cons line lines)))))))

(define (%shell-quote string)
  (string-append "'" (string-join (string-split string #\') "'\\''") "'"))

;;; ============================================================
;;; 构建源: source/config.org -> tmp/config.scm
;;; ============================================================

(define-blue-class <org-config>
  (inherit <buildable>)
  (constructor org-config)
  (predicate org-config?))

(define-blue-class <paren-check>
  (inherit <testable>)
  (constructor paren-check)
  (predicate paren-check?))

(define-blue-method (ask-build-manifest (this <org-config>)
                                        (inputs <list>)
                                        (output <string>))
  (let ((input (first inputs)))
    (make-build-manifest
     (string-append "编织\t" output)
     (lambda ()
       (mkdir-p (dirname output))
       (%run (%emacs-command
              `("--quick" "--batch" "-l" "org"
                "--eval" "(require 'ob-tangle)"
                "--eval" ,(format #f "(org-babel-tangle-file ~s)" input))))))))

(define %config-buildable
  (org-config
   (inputs '("source/config.org"))
   (outputs '("tmp/config.scm"))))

(define %config-check
  (paren-check
   (inputs (list %config-buildable))
   (outputs '("tmp/config.scm.check"))))

;;; ============================================================
;;; 配置辅助函数
;;; ============================================================

(define (count-parens port)
  (let loop ((char (read-char port)) (opens 0) (closes 0))
    (cond
     ((eof-object? char) (cons opens closes))
     ((eq? char #\() (loop (read-char port) (+ opens 1) closes))
     ((eq? char #\)) (loop (read-char port) opens (+ closes 1)))
     ((eq? char #\")
      (let skip-string ((char (read-char port)))
        (cond
         ((eof-object? char) (cons opens closes))
         ((eq? char #\") (loop (read-char port) opens closes))
         ((eq? char #\\) (read-char port) (skip-string (read-char port)))
         (else (skip-string (read-char port))))))
     ((eq? char #\;)
      (let skip-comment ((char (read-char port)))
        (cond
         ((eof-object? char) (cons opens closes))
         ((eq? char #\newline) (loop (read-char port) opens closes))
         (else (skip-comment (read-char port))))))
     (else (loop (read-char port) opens closes)))))

(define (check-paren-balance file)
  (call-with-input-file file
    (lambda (port)
      (match (count-parens port)
        ((opens . closes)
         (cond
          ((= opens closes)
           (format #t "[OK] 括号平衡: ~a 对 (~a)~%" opens file)
           #t)
          ((> opens closes)
           (format (current-error-port)
                    "[ERROR] 多余 ~a 个左括号 (open=~a close=~a)~%"
                    (- opens closes) opens closes)
           #f)
          (else
           (format (current-error-port)
                    "[ERROR] 多余 ~a 个右括号 (open=~a close=~a)~%"
                    (- closes opens) opens closes)
           #f)))))))

(define-blue-method (ask-build-manifest (this <paren-check>)
                                        (inputs <list>)
                                        (output <string>))
  (let ((input (first inputs)))
    (make-build-manifest
     (string-append "检查\t" input)
     (lambda ()
     (unless (check-paren-balance input)
          (error "括号平衡检查失败"))
       (call-with-output-file output
         (lambda (port)
            (format port "已检查 ~a~%" input)))))))

(define (tangle-config)
  (mkdir-p %tmp-dir)
  (%run (%emacs-command
         `("--quick" "--batch" "-l" "org"
           "--eval" "(require 'ob-tangle)"
           "--eval" ,(format #f "(org-babel-tangle-file ~s)" %config-org)))))

(define (prepare-config tail-expression)
  (tangle-config)
  (%append-to-file %config-scm (string-append "\n" tail-expression "\n"))
  (unless (check-paren-balance %config-scm)
    (error "配置括号平衡检查失败"))
  %config-scm)

(define* (apply-config subsystem tail-expression #:key sudo? after)
  (let ((scm (prepare-config tail-expression)))
    (if (%dry-run?)
        (begin
          (format #t "[预演] 验证 ~a 配置~%" subsystem)
          (%guix `(,subsystem "build" ,scm "--dry-run")))
        (begin
          (format #t "正在应用 ~a 配置~%" subsystem)
          (%guix `(,subsystem "reconfigure" ,scm
                              "--allow-downgrades" "--fallback")
                 #:sudo? sudo?)
          (false-if-exception (delete-file-recursively %tmp-dir)))))
  (when after (after)))

;;; ============================================================
;;; Org 代码块编辑
;;; ============================================================

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
      (unless body
        (princ (format \"[ERROR] 未找到代码块 %s\\n\" name))
        (kill-emacs 1))
      (princ (format \"%s\\n%s\\n\" (or lang \"\") (if has-noweb \"noweb\" \"plain\")))
      (princ (string-trim body \"\\n\" \"\\n\")))
    (kill-emacs 0))")

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
              (delete-region body-start (line-beginning-position))
              (goto-char body-start)
              (insert (string-trim-right new-body \"\\n\") \"\\n\")
              (setq replaced t))))))
      (if replaced
          (progn
            (write-region (point-min) (point-max) out-file)
            (princ (format \"lang=%s\\n\" (or lang \"\"))))
          (progn
            (princ (format \"[ERROR] 未找到代码块 %s\\n\" name))
            (kill-emacs 1)))))")

(define (write-temp-elisp name body)
  (mkdir-p %tmp-dir)
  (let ((file (string-append %tmp-dir "/" name)))
    (call-with-output-file file
      (lambda (port) (display body port)))
    file))

;;; ============================================================
;;; 密钥扫描
;;; ============================================================

(define %secret-exts
  '("*.conf" "*.toml" "*.yaml" "*.yml" "*.json" "*.ini" "*.cfg"
    "*.gitconfig" "*.scm" "*.fish" "*.el" "*.env" "*.netrc" "*.properties"))

(define %secret-exclude-dirs
  '(".git" ".agents" "node_modules" "tmp" ".blue-store"))

(define %secret-patterns
  '(("github-pat" . "ghp_[A-Za-z0-9]{36}")
    ("github-oauth" . "gho_[A-Za-z0-9]{36}")
    ("github-user" . "ghu_[A-Za-z0-9]{36}")
    ("github-server" . "ghs_[A-Za-z0-9]{36}")
    ("github-refresh" . "ghr_[A-Za-z0-9]{36}")
    ("openai" . "sk-[A-Za-z0-9]{20,}")
    ("anthropic" . "sk-ant-[A-Za-z0-9-]{20,}")
    ("openrouter" . "sk-or-[A-Za-z0-9-]{20,}")
    ("xai" . "xai-[A-Za-z0-9]{20,}")
    ("google-api" . "AIza[A-Za-z0-9_-]{35}")
    ("aws-access-key" . "AKIA[0-9A-Z]{16}")
    ("gitlab" . "glpat-[A-Za-z0-9_-]{20,}")
    ("slack" . "xox[bpars]-[A-Za-z0-9-]{10,}")
    ("private-key" . "-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----")
    ("oauth-token" . "oauth_token[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_-]{16,}")
    ("api-key" . "api[_-]key[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_-]{16,}")
    ("access-token" . "access_token[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_-]{16,}")
    ("password" . "password[[:space:]]*[:=][[:space:]]*[\"'][^\"']{8,}[\"']")))

(define (%secret-grep-options flags)
  (string-append
   flags " "
   (string-join
    (map (lambda (ext) (%shell-quote (string-append "--include=" ext)))
         %secret-exts)
    " ")
   " "
   (string-join
    (map (lambda (dir) (%shell-quote (string-append "--exclude-dir=" dir)))
         %secret-exclude-dirs)
    " ")))

(define (%secret-count-files dir)
  (let ((lines
         (%pipe->lines
          (string-append (%secret-grep-options "grep -rIl")
                         " -e '.' " (%shell-quote dir)
                         " 2>/dev/null | wc -l"))))
    (if (null? lines)
        0
        (or (string->number (string-trim-both (first lines))) 0))))

(define (scan-secrets dir fail? extra-patterns)
  (let ((patterns (append %secret-patterns
                          (map (cut cons "user-pattern" <>)
                               extra-patterns)))
        (found 0)
        (file-count (%secret-count-files dir)))
    (for-each
     (match-lambda
       ((name . pattern)
        (let ((hits
               (%pipe->lines
                (string-append (%secret-grep-options "grep -HrnIE")
                               " -e " (%shell-quote pattern)
                               " " (%shell-quote dir) " 2>/dev/null"))))
          (for-each
           (lambda (raw)
             (let ((match (string-match "^([^:]+):([0-9]+):(.*)$" raw)))
               (when match
                 (let* ((path (match:substring match 1))
                        (lineno (match:substring match 2))
                        (content (match:substring match 3))
                        (size (stat:size (stat path))))
                   (when (< size 1048576)
                     (format #t "[HINT] ~a:~a:~a:~a~%"
                             path lineno name
                             (if (> (string-length content) 80)
                                 (substring content 0 80)
                                 content))
                     (set! found (+ found 1)))))))
           hits))))
     patterns)
    (cond
     ((zero? found)
      (format #t "[OK] 未发现密钥，已扫描 ~a 个文件~%" file-count)
      #t)
     (fail?
      (error (format #f "密钥扫描: 发现 ~a 处密钥" found)))
     (else
      (format #t "[WARN] 密钥扫描: 发现 ~a 处疑似密钥~%" found)
      #t))))

;;; ============================================================
;;; 目录结构生成器
;;; ============================================================

(define %structor-marker-start "<!-- structor:begin -->")
(define %structor-marker-end "<!-- /structor -->")
(define %structor-skip-names
  '(".git" ".github" ".agents" "node_modules" ".blue-store"))

(define %structor-targets
  '("source/AGENTS.md"
    "dotfiles/AGENTS.md"
    "dotfiles/enable/utilities/AGENTS.md"
    "dotfiles/enable/terminal/AGENTS.md"
    "dotfiles/enable/system/AGENTS.md"
    "dotfiles/enable/desktop/AGENTS.md"
    "dotfiles/enable/desktop-suite/AGENTS.md"))

(define (%structor-skip? name)
  (or (member name '("." ".." "AGENTS.md"))
      (member name %structor-skip-names)
      (string-suffix? ".swp" name)))

(define (%structor-children dir)
  (let* ((entries (scandir dir (negate %structor-skip?)))
         (typed (map (lambda (name)
                       (cons (file-is-directory?
                              (string-append dir "/" name))
                             name))
                     entries))
         (dirs (filter car typed))
         (files (filter (compose not car) typed)))
    (append (sort dirs (lambda (a b) (string<? (cdr a) (cdr b))))
            (sort files (lambda (a b) (string<? (cdr a) (cdr b)))))))

(define (%structor-render dir max-depth depth prefix)
  (let* ((entries (%structor-children dir))
         (count (length entries)))
    (let loop ((index 0) (lines '()))
      (if (>= index count)
          (reverse lines)
          (let* ((entry (list-ref entries index))
                 (is-dir? (car entry))
                 (name (cdr entry))
                 (path (string-append dir "/" name))
                 (last? (= (+ index 1) count))
                 (connector (if last? "└── " "├── "))
                 (child-prefix (string-append prefix
                                              (if last? "    " "│   ")))
                 (line (string-append prefix connector name
                                      (if is-dir? "/" "")))
                 (children (if (and is-dir? (< (+ depth 1) max-depth))
                               (%structor-render path max-depth
                                                 (+ depth 1) child-prefix)
                               '())))
            (loop (+ index 1)
                  (append (reverse children) (cons line lines))))))))

(define (%structor-tree dir depth)
  (cons (string-append (basename dir) "/")
        (%structor-render dir depth 0 "")))

(define (%replace-structor-block content replacement)
  (let loop ((lines (string-split content #\newline))
             (out '())
             (state 'normal)
             (changed? #f))
    (match lines
      (()
       (and changed? (string-join (reverse out) "\n")))
      ((line . rest)
       (cond
        ((and (eq? state 'normal)
              (string=? (string-trim-both line) %structor-marker-start))
         (loop rest (append (reverse replacement) out) 'in-block #t))
        ((and (eq? state 'in-block)
              (string=? (string-trim-both line) %structor-marker-end))
         (loop rest out 'normal changed?))
        ((eq? state 'normal)
         (loop rest (cons line out) state changed?))
        (else
         (loop rest out state changed?)))))))

(define* (run-structor targets #:key (depth 4) dry?)
  (for-each
   (lambda (rel-path)
     (let* ((file (string-append %repo-root "/" rel-path))
            (dir (string-append %repo-root "/" (dirname rel-path))))
       (when (file-exists? file)
         (let* ((replacement
                 (append
                  (list %structor-marker-start
                        ""
                        "<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->"
                        ""
                        "```")
                  (%structor-tree dir depth)
                  (list "```" "" %structor-marker-end)))
                (content (call-with-input-file file get-string-all))
                (new-content (%replace-structor-block content replacement)))
           (if new-content
               (begin
                 (format #t "[~a] ~a (scan=~a depth=~a)~%"
                         (if dry? "DRY" "WRITE") rel-path
                         (dirname rel-path) depth)
                 (if dry?
                     (display new-content)
                     (%write-file-atomically
                      file
                      (lambda (port) (display new-content port)))))
               (format #t " 跳过 ~a（无 structor 标记）~%" rel-path))))))
   targets))

;;; ============================================================
;;; 指令
;;; ============================================================

(define %project-command-groups
  `((workflow
     ("build" "将 source/config.org 导出为 tmp/config.scm")
     ("check" "导出配置并检查 Scheme 括号平衡")
     ("clean" "清理 Blue 生成的构建/检查产物"))
    (deployment
     ("home" "应用 Guix Home 配置")
     ("rebuild" "应用 Guix System 配置")
     ("init" "将系统配置安装到 /mnt"))
    (editing
     ("block-show BLOCK" "提取指定名称的 Org 源代码块")
     ("block-replace BLOCK BODY-FILE" "替换指定 Org 源代码块；Scheme 块会自动验证"))
    (guix
     ("pull" "通过锁定频道执行 guix pull")
     ("update" "更新 source/channel.lock 并提交"))
    (maintenance
     ("clean-artifacts" "清理仓库内编译产物")
     ("clean-generations" "删除旧的 Guix System/Home generations")
     ("gc" "执行 Guix GC 并清理旧 Guix EFI 文件")
     ("reuse" "为文件补充 SPDX 版权和许可证头")
     ("structor [TARGET] ..." "刷新 AGENTS.md 中自动生成的目录结构"))
    (nix
     ("nix" "应用备用 Nix home-manager 配置")
     ("nix-init" "初始化 Nix channel 并安装 home-manager")
     ("nix-update" "更新 Nix channel 和 flake"))
    (validation
     ("secret-scan [DIR] [PATTERN] ..." "扫描文本配置中疑似泄漏的凭据"))))

(define (print-command-list)
  (format #t "用法: blue 指令 [参数]...~%~%")
  (format #t "可用指令:~%")
  (for-each
   (match-lambda
     ((category . commands)
      (format #t "~%  ~a:~%" category)
      (let ((width (fold (lambda (command current)
                           (max current (string-length (first command))))
                         0
                         commands)))
        (for-each
         (match-lambda
           ((name description)
            (format #t "    ~a~a  ~a~%"
                    name
                    (make-string (+ 2 (- width (string-length name))) #\space)
                    description)))
         commands))))
   %project-command-groups)
  (format #t "~%需要更详细说明时，可运行 `blue help 指令`。~%"))

(define-command (list-command arguments)
  ((invoke "list")
   (category 'help)
   (synopsis "列出项目指令")
   (help "列出本项目可用指令及其用途。"))
  (print-command-list))

(define-command (rebuild-command arguments)
  ((invoke "rebuild")
   (category 'deployment)
    (synopsis "应用 Guix System 配置")
    (help "应用 operating-system 表。支持 GUIX_DRY_RUN=1 环境变量。"))
  (apply-config "system" "%system"
                #:sudo? #t
                #:after (lambda () (%guix '("locate" "--update")))))

(define-command (home-command arguments)
  ((invoke "home")
   (category 'deployment)
   (synopsis "应用 Guix Home 配置")
   (help "应用 home-environment 表。支持 GUIX_DRY_RUN=1 环境变量。"))
  (apply-config "home" "%home"))

(define-command (block-show-command arguments)
  ((invoke "block-show")
   (category 'editing)
    (synopsis "提取指定名称的 Org 源代码块")
    (help "BLOCK
从 source/config.org 提取 BLOCK 到 tmp/block-BLOCK.scm 并打印路径。"))
  (match arguments
    ((name)
     (let* ((script (write-temp-elisp "block-show.el" block-extract-el))
            (out-file (string-append %tmp-dir "/block-" name ".scm"))
            (content
             (%pipe->string
              (string-join
               (map %shell-quote
                    (%emacs-command
                     `("--quick" "--batch" "--script" ,script
                       ,%config-org ,name)))
               " "))))
       (call-with-output-file out-file
         (lambda (port) (display content port)))
       (format #t "~a~%" out-file)))
    (_ (error "usage: blue block-show BLOCK"))))

(define-command (block-replace-command arguments)
  ((invoke "block-replace")
   (category 'editing)
    (synopsis "替换指定名称的 Org 源代码块")
    (help "BLOCK BODY-FILE
用 BODY-FILE 替换 source/config.org 中的 BLOCK。替换后自动验证 Scheme 代码块。"))
  (match arguments
    ((name body-file)
     (let* ((script (write-temp-elisp "block-replace.el" block-replace-el))
            (out-org (string-append %tmp-dir "/config.org.new"))
            (output
             (%pipe->string
              (string-join
               (map %shell-quote
                    (%emacs-command
                     `("--quick" "--batch" "--script" ,script
                       ,%config-org ,name ,body-file ,out-org)))
               " ")))
            (lang (if (string-prefix? "lang=" output)
                      (string-trim-both (substring output 5))
                      "")))
       (%write-file-atomically
        %config-org
        (lambda (port)
          (display (call-with-input-file out-org get-string-all) port)))
       (if (string=? lang "scheme")
           (begin
             (tangle-config)
             (unless (check-paren-balance %config-scm)
               (error "block-replace 验证失败；请用 git 检查/还原 source/config.org"))
             (false-if-exception (delete-file-recursively %tmp-dir))
                           (format #t "[OK] 代码块 ~a 已替换并验证~%" name))
           (begin
             (false-if-exception (delete-file-recursively %tmp-dir))
              (format #t "[OK] 代码块 ~a（~a）已替换~%" name lang)))))
    (_ (error "usage: blue block-replace BLOCK BODY-FILE"))))

(define-command (clean-generations-command arguments)
  ((invoke "clean-generations")
   (category 'maintenance)
    (synopsis "删除旧的 Guix System/Home 世代")
    (help "删除旧 system 和 home 世代。删除 system 世代可能需要 sudo 权限。"))
  (%run '("sh" "-c" "sudo guix system delete-generations > /dev/null"))
  (%run '("sh" "-c" "guix home delete-generations > /dev/null")))

(define-command (clean-artifacts-command arguments)
  ((invoke "clean-artifacts")
   (category 'maintenance)
    (synopsis "移除仓库编译产物")
    (help "移除仓库内的 __pycache__、*.elc、*.o、*.a 和 *.so 文件。"))
  (for-each
   (match-lambda
     ((pattern type)
      (if (eq? type 'directory)
          (%run `("find" ,%repo-root "-type" "d" "-name" ,pattern
                  "-not" "-path" "*/.git/*"
                  "-print" "-exec" "rm" "-rf" "{}" "+"))
          (%run `("find" ,%repo-root "-type" "f" "-name" ,pattern
                  "-not" "-path" "*/.git/*"
                  "-print" "-delete")))))
   '(("__pycache__" directory)
     ("*.elc" file)
     ("*.o" file)
     ("*.a" file)
     ("*.so" file))))

(define-command (secret-scan-command arguments)
  ((invoke "secret-scan")
   (category 'validation)
    (synopsis "扫描文本配置文件中疑似泄漏的密钥")
    (help "[DIR] [PATTERN] ...
扫描 DIR（默认为 dotfiles/enable）。额外正则模式可作为后续参数传入。
设置 GUIX_SECRET_SCAN_FAIL_ON_FIND=0 可仅警告而不报错。"))
  (let* ((dir (if (null? arguments) "dotfiles/enable" (first arguments)))
         (extra (if (null? arguments) '() (cdr arguments)))
         (fail? (not (string=? (or (getenv "GUIX_SECRET_SCAN_FAIL_ON_FIND") "1") "0"))))
    (scan-secrets dir fail? extra)))

(define-command (gc-command arguments)
  ((invoke "gc")
   (category 'maintenance)
    (synopsis "执行 Guix GC 并清理旧 Guix EFI 文件")
    (help "依次执行 clean-generations、guix gc 并删除 /boot/EFI/Guix/OLD-*.EFI。"))
  ((command-procedure clean-generations-command) '())
  (%run '("guix" "gc"))
  (%run '("sudo" "rm" "-rf" "/boot/EFI/Guix/OLD-*.EFI")))

(define-command (init-command arguments)
  ((invoke "init")
   (category 'deployment)
    (synopsis "将系统配置安装到 /mnt")
    (help "将 operating-system 表安装到 /mnt。"))
  (let ((scm (prepare-config "%system")))
    (format #t "正在将系统安装到 /mnt~%")
    (%guix `("system" "init" ,scm "/mnt") #:sudo? #t)
    (false-if-exception (delete-file-recursively %tmp-dir))))

(define-command (nix-command arguments)
  ((invoke "nix")
   (category 'nix)
    (synopsis "应用备用 Nix home-manager 配置"))
  (%run `(,(string-append %home-dir "/.nix-profile/bin/home-manager")
          "switch" "-b" "backup"
          "--flake" ,(string-append %nix-dir "/#Guix")
          "--extra-experimental-features" "nix-command"
          "--extra-experimental-features" "flakes")))

(define-command (nix-init-command arguments)
  ((invoke "nix-init")
   (category 'nix)
    (synopsis "初始化 Nix channel 并安装 home-manager"))
  (%run '("nix-channel" "--update"))
  (%run '("nix-shell" "<home-manager>" "-A" "install")))

(define-command (nix-update-command arguments)
  ((invoke "nix-update")
   (category 'nix)
    (synopsis "更新 Nix channel 和 flake"))
  (%run '("nix-channel" "--update"))
  (%run `("git" "commit" "-S" "-m"
          "UPDATE: (flake.lock) bump version."
          ,(string-append %nix-dir "/flake.nix")))
  (%run `("nix" "flake" "update" "--flake" ,%nix-dir)))

(define-command (pull-command arguments)
  ((invoke "pull")
   (category 'guix)
    (synopsis "通过锁定频道执行 guix pull"))
  (%guix '("pull" "--allow-downgrades" "--fallback")))

(define-command (reuse-command arguments)
  ((invoke "reuse")
   (category 'maintenance)
    (synopsis "为文件补充 SPDX 版权和许可证头"))
  (%run `("reuse" "annotate"
          "--copyright" "BrokenShine <xchai404@gmail.com>"
          "--license" "MIT"
          "--skip-unrecognised" "--recursive"
          "--year" ,(strftime "%Y" (localtime (time-second (current-time))))
          ".")))

(define-command (update-command arguments)
  ((invoke "update")
   (category 'guix)
    (synopsis "更新 source/channel.lock 并提交"))
  (let ((content
         (%pipe->string
          (string-join
           (map %shell-quote
                (list "guix" "time-machine"
                      (string-append "--channels=" %channel-scm)
                      "--" "describe" "--format=channels"))
           " "))))
    (%write-file-atomically %channel-lock
                            (lambda (port) (display content port)))
    (%run `("git" "commit" "-S" "-m"
            "UPDATE: (channel.lock) bump version."
            ,%channel-lock))))

(define-command (structor-command arguments)
  ((invoke "structor")
   (category 'maintenance)
    (synopsis "刷新 AGENTS.md 中自动生成的目录树章节")
    (help "[TARGET] ...
刷新所有 structor 目标，或仅刷新指定的 AGENTS.md。
支持 ORG_STRUCTOR_DEPTH=N 和 ORG_STRUCTOR_DRY=1 环境变量。"))
  (let* ((depth (or (and=> (getenv "ORG_STRUCTOR_DEPTH") string->number) 4))
         (targets (if (null? arguments) %structor-targets arguments))
         (dry? (%env-set? "ORG_STRUCTOR_DRY")))
    (run-structor targets #:depth depth #:dry? dry?)))

;;; ============================================================
;;; 入口点
;;; ============================================================

(blueprint
 (buildables (list %config-buildable))
 (testables (list %config-check))
 (commands
  (list list-command
        rebuild-command
        home-command
        block-show-command
        block-replace-command
        clean-generations-command
        clean-artifacts-command
        secret-scan-command
        gc-command
        init-command
        nix-command
        nix-init-command
        nix-update-command
        pull-command
        reuse-command
        update-command
        structor-command)))
