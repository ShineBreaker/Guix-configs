;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; blueprint.scm — blue 任务运行器（Guix-configs 项目主入口）
;; 结构地图、管线与设计理由：docs/scripts/blueprint.md

(use-modules (blue build)
             (blue states)
             (blue types)
             (blue types blueprint)
             (blue types buildable)
             (blue types command)
             (blue types testable)
             (blue subprocess)
             (guix utils)
             (guix build utils)
             (ice-9 ftw)
             (ice-9 format)             ; ~{ ~} 迭代指令需要完整版 format，
                                        ;  core 的 simple-format 不支持
             (ice-9 match)
             (ice-9 popen)
             (ice-9 rdelim)
             (ice-9 regex)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-13)
             (srfi srfi-19)
             (srfi srfi-26))

;;; --- §0 路径常量 ---
;; %repo-root 取决于运行 blue 时的工作目录（须在仓库根运行 blue）。

(define %repo-root    (getcwd))
(define %home-dir     (getenv "HOME"))
(define %config-org   (string-append %repo-root "/source/config.org")) ; 唯一 Org 源
(define %nix-dir      (string-append %repo-root "/source/nix"))    ; Nix 备用配置
(define %tmp-dir      (string-append %repo-root "/tmp"))           ; tangle 中间产物
(define %config-scm   (string-append %tmp-dir "/config.scm"))      ; tangle 产物
(define %channel-scm  (string-append %repo-root "/source/channel.scm"))  ; 频道定义（可变分支）
(define %channel-lock (string-append %repo-root "/source/channel.lock")) ; 频道锁（固定 commit）
(define %stow-dir     (string-append %repo-root "/dotfiles/mutable"))
(define %tools-dir    (string-append %repo-root "/tools"))         ; 外置脚本与 elisp

;;; --- §1 子进程执行 ---

;; 子进程失败的统一出口：用 primitive-exit 而非 error/exit——blue 框架会
;; 给异常打整套 backtrace，而"子进程非零退出"是预期内失败，堆栈无诊断价值。
(define (%subprocess-fail! status message)
  (format (current-error-port) "~a~%" message)
  (primitive-exit (or status 1)))

;; dry-run 预演打印；需要手动短路管道命令的调用方（如 update 的
;; describe）也用同一格式。
(define (%print-preview command)
  (match command
    [(program . args)
     (format #t "\t[预演]\t~a ~{~a ~}~%" program args)]))

;; 唯一允许启动子进程的地方：`blue --dry-run' 时默认只打印不执行；
;; #:real? #t 是逃生口（tangle、括号检查等 dry-run 下也必须真跑）。
(define* (%run command #:key real?)
  (if (and (dry-build?) (not real?))
      (begin (%print-preview command) #t)
      (match command
        [(program . args)
         (let ([status (popen program args)])
           (unless (zero? status)
             ;; popen 返回原始 wait status（退出码在高位），须解包后再交
             ;; primitive-exit，否则低 8 位截断后失败也报 0
             (%subprocess-fail! (status:exit-val status)
                                (format #f "命令执行失败 (~a): ~s" status command)))
           #t)])))

;; 所有 guix 调用都必须经 `guix time-machine --channels=...'，否则频道
;; 版本与 channel.lock 不一致，构建结果不可复现。
(define* (%guix-command args #:key (channels %channel-lock))
  `("guix" "time-machine"
    ,(string-append "--channels=" channels) "--"
    ,@args))

(define* (%guix args #:key sudo?)
  (let ([command (%guix-command args)])
    (%run (if sudo? (cons "sudo" command) command))))

;; 用 emacs-minimal 跑 emacs。unset 五个 EMACS* 变量：blue 可能运行在
;; 用户 emacs 的环境里，这些变量会干扰新进程的 load-path / data。
(define (%emacs-command args)
  `("env"
    "-u" "EMACSLOADPATH" "-u" "EMACSDATA" "-u" "EMACSDOC"
    "-u" "EMACSPATH" "-u" "INSIDE_EMACS"
    ,@(%guix-command `("shell" "emacs-minimal" "--" "emacs" ,@args))))

;;; --- §2 文件与管道 I/O ---

;; rename 覆盖保证目标绝不停留在"写一半"；config.org / channel.lock 等关键文件用它。
(define (%write-file-atomically file thunk)
  (let* ([template (string-append file ".XXXXXX")]
         [port (mkstemp! template)])
    (with-throw-handler #t
      (lambda ()
        (thunk port)
        (force-output port)
        (close-port port)
        (rename-file template file))
      (lambda _
        (false-if-exception (delete-file template))
        (false-if-exception (close-port port))))))

(define (%shell-quote string)
  (string-append "'" (string-join (string-split string #\') "'\\''") "'"))

(define (%shell-command command)
  (string-join (map %shell-quote command) " "))

;; 管道读取（不经 %run）：dry-run 下也真跑，调用方须自行确认只读。
;; 默认不检查退出码（grep 等非 0 语义）；#:check? #t 时非 0 视为失败。
(define* (%pipe->lines command #:key check?)
  (let* ([pipe (open-input-pipe command)]
         [lines (let loop ([acc '()])
                  (let ([line (read-line pipe)])
                    (if (eof-object? line)
                        (reverse acc)
                        (loop (cons line acc)))))]
         [status (status:exit-val (close-pipe pipe))])
    (when (and check? (not (zero? status)))
      (%subprocess-fail! status
                         (format #f "命令执行失败 (~a): ~a" status command)))
    lines))

;; 整体读 stdout，退出码非 0 视为失败；失败时把已捕获输出转发到 stderr
;; （elisp 的 [ERROR] 等诊断会随之可见），再按子进程退出码终止。
(define (%pipe->string command)
  (let* ([pipe (open-input-pipe command)]
         [content (get-string-all pipe)]
         [status (status:exit-val (close-pipe pipe))])
    (unless (zero? status)
      (unless (string-null? content)
        (format (current-error-port) "~a" content))
      (%subprocess-fail! status
                         (format #f "命令执行失败 (~a): ~a" status command)))
    content))

;;; --- §3 括号平衡检查 ---
;; 手写词法扫描而非 guix read：config.org 的块含读取器宏（unquote 等），
;; read 报错定位差。已知限制：字符串未闭合不会单独报错（emergency-blue
;; 的 awk 移植版额外覆盖，见 docs/emergency-blue.md §关键约束）。

;; 返回 #(paren-open paren-close bracket-open bracket-close mismatch?)；
;; 栈记录开括号类型，闭括号须与栈顶同类（[ 配 ) 算错）。
(define (count-parens port)
  (let loop ([char (read-char port)]
             [popen 0] [pclose 0]
             [bopen 0] [bclose 0]
             [stack '()]               ; 'paren 或 'bracket
             [mismatch? #f])
    (cond
     [mismatch?
      (vector popen pclose bopen bclose #t)]
     [(eof-object? char)
      (vector popen pclose bopen bclose #f)]
     [(eq? char #\()
      (loop (read-char port) (+ popen 1) pclose bopen bclose
            (cons 'paren stack) #f)]
     [(eq? char #\))
      (match stack
        [('paren . rest)
         (loop (read-char port) popen (+ pclose 1) bopen bclose rest #f)]
        [_
         ;; 栈顶不是圆括号（空栈或栈顶是方括号）→ 类型错配
         (vector popen pclose bopen bclose #t)])]
     [(eq? char #\[)
      (loop (read-char port) popen pclose (+ bopen 1) bclose
            (cons 'bracket stack) #f)]
     [(eq? char #\])
      (match stack
        [('bracket . rest)
         (loop (read-char port) popen pclose bopen (+ bclose 1) rest #f)]
        [_
         (vector popen pclose bopen bclose #t)])]
     ;; 双引号字符串：读到下一个未转义的 " 为止
     [(eq? char #\")
      (let skip-string ([c (read-char port)])
        (cond
         [(eof-object? c)
          (vector popen pclose bopen bclose mismatch?)]
         [(eq? c #\") (loop (read-char port) popen pclose bopen bclose
                            stack mismatch?)]
         [(eq? c #\\) (read-char port) (skip-string (read-char port))]
         [else (skip-string (read-char port))]))]
     ;; 分号行注释：读到行尾
     [(eq? char #\;)
      (let skip-comment ([c (read-char port)])
        (cond
         [(eof-object? c)
          (vector popen pclose bopen bclose mismatch?)]
         [(eq? c #\newline) (loop (read-char port) popen pclose bopen bclose
                                  stack mismatch?)]
         [else (skip-comment (read-char port))]))]
     [else (loop (read-char port) popen pclose bopen bclose
                 stack mismatch?)])))

;; 逐块检查与整文件兜底共用这一报告出口；label 为路径或"块 <名>"。
(define (%report-parens label port)
  (match (count-parens port)
    [#(popen pclose bopen bclose mismatch?)
     (cond
      [mismatch?
       (format (current-error-port)
               "[ERROR] ~a: 括号类型错配 ([配) 或 (配])~%" label)
       #f]
      [(and (= popen pclose) (= bopen bclose))
       (format #t "[OK] ~a: ( ~a 对 ) + [ ~a 对 ]~%" label popen bopen)
       #t]
      [else
       (format (current-error-port)
               "[ERROR] ~a: 不平衡 ( open=~a close=~a ) [ open=~a close=~a ]~%"
               label popen pclose bopen bclose)
       #f])]))

(define (check-paren-balance file)
  (call-with-input-file file (cut %report-parens file <>)))

;;; --- §4 配置管线与 Org 块解析 ---
;; config.org ──tangle──▶ tmp/config.scm ──尾表达式+括号兜底──▶ reconfigure。
;; 两个 blue 类接进内建命令：<org-config> → `blue build` 触发 tangle；
;; <paren-check> → `blue check` 逐块括号检查（不 tangle，定位到块名）。
;; 块编辑 elisp 外置在 tools/block-*.el，输出协议见 docs/scripts/org-block-tools.md。

(define-blue-class <org-config>
  (inherit <buildable>)
  (constructor org-config)
  (predicate org-config?))

(define-blue-class <paren-check>
  (inherit <testable>)
  (constructor paren-check)
  (predicate paren-check?))

;; #:real? #t：dry-run 下也必须真跑，否则没法验证括号。
(define (%tangle-file org-file)
  (%run (%emacs-command
         `("--quick" "--batch" "-l" "org"
           "--eval" "(require 'ob-tangle)"
           "--eval" ,(format #f "(org-babel-tangle-file ~s)" org-file)))
        #:real? #t))

;; `blue build` 触发时对每个 buildable 调 ask-build-manifest 拿构建动作。
(define-blue-method (ask-build-manifest (this <org-config>)
                                        (inputs <list>)
                                        (output <string>))
  (let ([input (first inputs)])
    (make-build-manifest
     (string-append "编织\t" output)
     (lambda ()
       (mkdir-p (dirname output))
       (%tangle-file input)))))

(define-blue-method (ask-build-manifest (this <paren-check>)
                                        (inputs <list>)
                                        (output <string>))
  (make-build-manifest
   (string-append "检查\t" %config-org)
   (lambda ()
     (unless (%check-config-blocks)
       (error "括号平衡检查失败"))
     (mkdir-p (dirname output))
     (call-with-output-file output
       (lambda (port)
         (format port "已检查 ~a~%" %config-org))))))

(define %config-buildable
  (org-config
   (inputs '("source/config.org"))
   (outputs '("tmp/config.scm"))))

(define %config-check
  (paren-check
   (inputs '())                                  ; 不依赖 tangle，直接解析 config.org
   (outputs '("tmp/config.scm.check"))))         ; 仅作占位标记

;; extra-args 成为脚本的 command-line-args-left，返回脚本 stdout。
(define (%run-elisp name . extra-args)
  (%pipe->string
   (%shell-command
    (%emacs-command
     `("--quick" "--batch" "--script"
       ,(string-append %tools-dir "/" name ".el")
       ,%config-org ,@extra-args)))))

;; block-list.el 的 >>> / <<< 记录协议见 docs/scripts/org-block-tools.md，勿改。
(define %block-header-re
  (make-regexp "^>>>name=([^[:space:]]+)\tlang=([^[:space:]]+)\tnoweb=(.+)$"))

(define (%extract-all-blocks)
  (let loop ([lines (string-split (%run-elisp "block-list") #\newline)]
             [current #f]            ; 当前记录的 (name lang noweb)
             [body '()]              ; body 行累积（逆序）
             [blocks '()])
    (match lines
      [() (reverse blocks)]
      [(line . rest)
       (cond
        [(regexp-exec %block-header-re line)
         => (lambda (m)
              (loop rest
                    (map (cut match:substring m <>) '(1 2 3))
                    '() blocks))]
        [(string=? line "<<<")
         (loop rest #f '()
               (if current
                   (cons (append current
                                 (list (string-join (reverse body) "\n")))
                         blocks)
                   blocks))]
        ;; 记录外的行（分隔符之间不属于任何块）丢弃
        [else
         (loop rest current
               (if current (cons line body) body)
               blocks)])])))

;; 单块检查：只查 scheme 块（fish/bash 是嵌在 scheme 字符串里的内容）。
;; main 块也查——<<ref>> 占位本身括号平衡，能抓 main 自身的括号错。
(define (%check-block-parens block)
  (match block
    [(name lang _ body)
     (if (string=? lang "scheme")
         (call-with-input-string body
           (cut %report-parens (format #f "块 ~a" name) <>))
         (begin
           (format #t "[SKIP] 块 ~a (~a)~%" name lang)
           #t))]))

(define %peripheral-scm-files
  (map (cut string-append %repo-root "/" <>)
       '("source/channel.scm" "source/information.scm" "source/manifest.scm")))

;; 失败不立即中止——跑完全部块与周边文件，让用户一次看到所有错误。
(define (%check-config-blocks)
  (let* ([blocks (%extract-all-blocks)]
         [results (append (map %check-block-parens blocks)
                          (map (lambda (file)
                                 (if (file-exists? file)
                                     (check-paren-balance file)
                                     (begin
                                       (format (current-error-port)
                                               "[ERROR] 文件不存在: ~a~%" file)
                                       #f)))
                               %peripheral-scm-files))]
         [ok? (every identity results)]
         [scheme-count (length (filter (lambda (b) (string=? (cadr b) "scheme"))
                                       blocks))])
    (if ok?
        (format #t "[OK] 全部通过: ~a 个 scheme 块 + ~a 个周边文件~%"
                scheme-count (length %peripheral-scm-files))
        (format (current-error-port) "[FAIL] 括号检查未通过~%"))
    ok?))

;; ---- 三步流水线（被各 reconfigure 命令复用） ----

(define (tangle-config)
  (mkdir-p %tmp-dir)
  (%tangle-file %config-org))

;; 步骤 1+2：tangle 后把 tail-expression（%system / %home）追加到
;; config.scm 末尾（guix 取文件最后一个表达式的值为配置对象），再括号兜底。
(define (prepare-config tail-expression)
  (tangle-config)
  (let ([port (open-file %config-scm "a")])
    (display (string-append "\n" tail-expression "\n") port)
    (close-port port))
  (unless (check-paren-balance %config-scm)
    (error "配置括号平衡检查失败"))
  %config-scm)

;; 步骤 3：reconfigure；dry-run 降级为 `guix <subsystem> build --dry-run'
;; （只验证不写入）。成功后清掉 tmp/ 中间产物。
(define* (apply-config subsystem tail-expression #:key sudo? after)
  (let ([scm (prepare-config tail-expression)])
    (if (dry-build?)
        (begin
          (format #t "[预演] 验证 ~a 配置~%" subsystem)
          (%guix `(,subsystem "build" ,scm "--dry-run")))
        (begin
          (format #t "正在应用 ~a 配置~%" subsystem)
          ;; --no-kexec：reconfigure 默认 kexec-load 新内核，此后 elogind 的
          ;; reboot 会走 kexec 路径并挂死电源操作（仅 system 有此选项）。
          (%guix `(,subsystem "reconfigure" ,scm
                              "--allow-downgrades" "--fallback"
                              ,@(if (string=? subsystem "system")
                                    '("--no-kexec")
                                    '()))
                 #:sudo? sudo?)
          (false-if-exception (delete-file-recursively %tmp-dir)))))
  (when after (after)))

;;; --- §5 密钥扫描（secret-scan 命令） ---
;; grep 命中=疑似，人工判断；默认找到即 error（CI 卡点），
;; GUIX_SECRET_SCAN_FAIL_ON_FIND=0 则只警告。

(define %secret-exts
  '("*.conf" "*.toml" "*.yaml" "*.yml" "*.json" "*.ini" "*.cfg"
    "*.gitconfig" "*.scm" "*.fish" "*.el" "*.env" "*.netrc" "*.properties"))

(define %secret-exclude-dirs
  '(".git" ".agents" "node_modules" "tmp" ".blue-store"))

;; (显示名 . 正则) 表；secret-scan 的额外参数以 "user-pattern" 名追加。
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
    (append
     (map (lambda (ext) (%shell-quote (string-append "--include=" ext)))
          %secret-exts)
     (map (lambda (dir) (%shell-quote (string-append "--exclude-dir=" dir)))
          %secret-exclude-dirs))
    " ")))

;; 文件数只用于扫描结束后的提示信息。
(define (%secret-count-files dir)
  (let ([lines (%pipe->lines
                (string-append (%secret-grep-options "grep -rIl")
                               " -e '.' " (%shell-quote dir)
                               " 2>/dev/null | wc -l"))])
    (if (null? lines)
        0
        (or (string->number (string-trim-both (first lines))) 0))))

;; fail?=真 且有命中时 error；否则打 [HINT]/[WARN] 并返回 #t。
(define (scan-secrets dir fail? extra-patterns)
  (let ([patterns (append %secret-patterns
                          (map (cut cons "user-pattern" <>)
                               extra-patterns))]
        [found 0]
        [file-count (%secret-count-files dir)])
    (for-each
     (match-lambda
       [(name . pattern)
        (for-each
         (lambda (raw)
           (match (string-match "^([^:]+):([0-9]+):(.*)$" raw)
             [#f #f]
             [m (let ([path (match:substring m 1)])
                  ;; 只报小于 1MB 的文件，避免误报二进制/大文件
                  (when (< (stat:size (stat path)) 1048576)
                    (let ([content (match:substring m 3)])
                      (format #t "[HINT] ~a:~a:~a:~a~%"
                              path (match:substring m 2) name
                              (if (> (string-length content) 80)
                                  (substring content 0 80)
                                  content))
                      (set! found (+ found 1)))))]))
         (%pipe->lines
          (string-append (%secret-grep-options "grep -HrnIE")
                         " -e " (%shell-quote pattern)
                         " " (%shell-quote dir) " 2>/dev/null")))])
     patterns)
    (cond
     [(zero? found)
      (format #t "[OK] 未发现密钥，已扫描 ~a 个文件~%" file-count)
      #t]
     [fail?
      (error (format #f "密钥扫描: 发现 ~a 处密钥" found))]
     [else
      (format #t "[WARN] 密钥扫描: 发现 ~a 处疑似密钥~%" found)
      #t])))

;;; --- §6 目录树生成器（structor 命令） ---
;; 标记对 `<!-- structor:begin depth=N -->' / `<!-- /structor -->' 之间的
;; 内容由本节生成。可见性 = `git ls-files' 驱动（.gitignore 与 submodule
;; 自动正确）；规则细节见 docs/scripts/blueprint.md。

(define %structor-marker-end "<!-- /structor -->")

;; Guile ERE：`('、`)' 是分组符号（不是字面括号），故无需 `\\' 转义。
(define %structor-depth-regex
  (make-regexp
   "<!--[[:space:]]*structor:begin([[:space:]]+depth[[:space:]]*=[[:space:]]*([0-9]+))?[[:space:]]*-->"))

(define (%structor-targets)
  (filter-map
   (lambda (path)
     (and (file-exists? path)
          (not (string-contains path "/.git/"))
          (not (string-contains path "/disable/"))
          (not (string-contains path "/tmp/"))
          (not (string-contains path "/.blue-store/"))
          (not (string-contains path "/.agents/"))
          (substring path (string-length %repo-root))))
   (find-files %repo-root "(^|/)(AGENTS|README)\\.md$")))

;; git 管不到的硬跳：AGENTS.md（树所在文件不能列自己）与可能被 git
;; 跟踪的 *.swp。
(define (%structor-skip? name)
  (or (member name '("." ".." "AGENTS.md"))
      (string-suffix? ".swp" name)))

;; git 可见路径列表（相对 scope）；非 0 退出（非 git 仓库）→ error。
(define (%structor-git-visible-paths scope)
  (%pipe->lines
   (%shell-command
    `("git" "-C" ,scope "ls-files" "--cached" "--others" "--exclude-standard"))
   #:check? #t))

(define (%structor-visible? rel visible)
  (let ([prefix (string-append rel "/")])
    (any (lambda (p) (or (string=? p rel) (string-prefix? prefix p))) visible)))

;; 返回 ((is-dir? . name) ...)，目录在前各自字母序；rel-of 把 dir 内
;; name 翻译成相对 scope 的路径（每层下钻由调用方套前缀）。
(define (%structor-children dir visible rel-of)
  (let* ([entries
          (map (lambda (name)
                 (cons (file-is-directory? (string-append dir "/" name)) name))
               (sort (filter (lambda (name)
                               (%structor-visible? (rel-of name) visible))
                             (scandir dir (negate %structor-skip?)))
                     string<?))]
         [dirs (filter car entries)]
         [files (filter (compose not car) entries)])
    (append dirs files)))

(define (%structor-render dir visible max-depth depth prefix rel-of)
  (let* ([entries (%structor-children dir visible rel-of)]
         [count (length entries)])
    (let loop ([index 0] [lines '()])
      (if (>= index count)
          (reverse lines)
          (let* ([entry (list-ref entries index)]
                 [name (cdr entry)]
                 [last? (= (+ index 1) count)]
                 [line (string-append prefix
                                      (if last? "└── " "├── ")
                                      name
                                      (if (car entry) "/" ""))]
                 [children (if (and (car entry) (< (+ depth 1) max-depth))
                               (%structor-render
                                (string-append dir "/" name)
                                visible max-depth (+ depth 1)
                                (string-append prefix (if last? "    " "│   "))
                                (lambda (n)
                                  (rel-of (string-append name "/" n))))
                               '())])
            (loop (+ index 1)
                  (append (reverse children) (cons line lines))))))))

;; scope 为仓库根时 dir 形如 `<repo>/.'，basename 返回 "."——退一阶取仓库名。
(define (%structor-root-label dir)
  (let ([base (basename dir)])
    (if (string=? base ".")
        (basename (dirname dir))
        base)))

(define (%structor-tree dir visible depth)
  (cons (string-append (%structor-root-label dir) "/")
        (%structor-render dir visible depth 0 "" identity)))

;; 返回第一个 begin 标记的 depth；无标记/无参数返回 #f。
(define (%structor-parse-depth content)
  (let loop ([lines (string-split content #\newline)])
    (match lines
      [() #f]
      [(line . rest)
       (let ([m (regexp-exec %structor-depth-regex (string-trim-both line))])
         (if m
             (let ([d (match:substring m 2)])
               (and d (string->number d)))
             (loop rest)))])))

;; 没找到标记返回 #f（无需改动）。begin 行 regex 匹配（兼容 depth=N），
;; end 行精确匹配。
(define (%replace-structor-block content replacement)
  (let loop ([lines (string-split content #\newline)]
             [out '()]
             [state 'normal]
             [changed? #f])
    (match lines
      [()
       (and changed? (string-join (reverse out) "\n"))]
      [(line . rest)
       (cond
        ;; 进入标记：替换段塞入输出，切到 in-block
        [(and (eq? state 'normal)
              (regexp-exec %structor-depth-regex (string-trim-both line)))
         (loop rest (append (reverse replacement) out) 'in-block #t)]
        ;; 离开标记：切回 normal（标记行本身也被丢弃，由 replacement 重写）
        [(and (eq? state 'in-block)
              (string=? (string-trim-both line) %structor-marker-end))
         (loop rest out 'normal changed?)]
        [(eq? state 'normal)
         (loop rest (cons line out) state changed?)]
        [else
         (loop rest out state changed?)])])))

;; depth 是全局回退；标记内 `depth=N'（%structor-parse-depth）优先。
(define* (run-structor targets #:key (depth 4) dry?)
  (for-each
   (lambda (rel-path)
     (let* ([file (string-append %repo-root "/" rel-path)]
            [dir (string-append %repo-root "/" (dirname rel-path))])
       (when (file-exists? file)
         (let* ([content (call-with-input-file file get-string-all)]
                [doc-depth (%structor-parse-depth content)]
                [eff-depth (or doc-depth depth)]
                [visible (%structor-git-visible-paths dir)])
           (let* ([replacement
                   (append
                    (list (format #f "<!-- structor:begin depth=~a -->" eff-depth)
                          ""
                          "<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->"
                          ""
                          "```")
                    (%structor-tree dir visible eff-depth)
                    (list "```" "" %structor-marker-end))]
                  [new-content (%replace-structor-block content replacement)])
             (if new-content
                 (begin
                   (format #t "[~a] ~a (scan=~a depth=~a~a)~%"
                           (if dry? "DRY" "WRITE") rel-path
                           (dirname rel-path) eff-depth
                           (if doc-depth " ←doc" ""))
                   (if dry?
                       (display new-content)
                       (%write-file-atomically
                        file
                        (lambda (port) (display new-content port)))))
                 (format #t " 跳过 ~a（无 structor 标记）~%" rel-path)))))))
   targets))

;;; --- §7 GNU Stow 包装（stow / stow-all 命令） ---
;; dotfiles/mutable/ 用 GNU Stow 直链到仓库源（改源即生效）。
;; 包身份与行为由标记文件显式声明：.stow-package 声明"这是一个包"
;; （stow-all 枚举依据），.stow-folding 按包 opt-in 整目录折叠；
;; 无标记目录只可能是分组容器，下钻一层找带标记的子包。

;; 枚举包时跳过的元目录。包身份由 .stow-package 声明，无标记目录只会
;; 作为分组下钻、天然产不出包，名单只剩 .git（避免 scandir 巨大对象库）。
(define %stow-meta-names '("." ".." ".git"))

(define (%stow-flag mode)
  (case (string->symbol mode)
    [(adopt) "--adopt"]
    [(restow) "--restow"]
    [(delete) "--delete"]
    [else ""]))

(define (%stow-verb mode)
  (case (string->symbol mode)
    [(adopt) "收养"]
    [(restow) "重建"]
    [(delete) "撤销"]
    [else "部署"]))

;; 标记文件：放在 dotfiles/mutable/<PKG>/.stow-folding 即整目录折叠；
;; 无标记走默认 --no-folding（真实目录 + 逐文件软链，保护运行时产物）。
(define %stow-folding-marker ".stow-folding")

(define (%stow-folding? pkg)
  (file-exists? (string-append %stow-dir "/" pkg "/" %stow-folding-marker)))

;; 标记文件：放在 dotfiles/mutable/<PKG>/.stow-package 即声明是 stow 包
;; （stow-all 的枚举依据；blue stow 显式包名不受此限）。
(define %stow-package-marker ".stow-package")

;; 把 "group/pkg" 拆成 (stow-dir . 一级包名)：分组前缀并入 --dir，
;; stow 永远只收一级包名（GNU Stow 不保证接受带斜杠的包名）。
(define (%stow-split-pkg pkg)
  (match (string-rindex pkg #\/)
    [#f (cons %stow-dir pkg)]
    [i (cons (string-append %stow-dir "/" (substring pkg 0 i))
             (substring pkg (+ i 1) (string-length pkg)))]))

;; --ignore=\.stow-(folding|package)$ 始终带上：标记文件本身永不部署到
;; $HOME（多个包的同名标记会冲突）。
(define (%stow-package pkg mode home)
  (let ([pkg-dir (string-append %stow-dir "/" pkg)])
    (unless (file-exists? pkg-dir)
      (error (format #f "stow 包不存在: ~a" pkg-dir)))
    (let* ([split (%stow-split-pkg pkg)]
           [folding? (%stow-folding? pkg)]
           [flag (%stow-flag mode)])
      (format #t "[~a] ~a -> ~a (~a)~%"
              (%stow-verb mode) pkg home
              (if folding? "folding" "no-folding"))
      (%run `("stow"
              "--ignore=\\.stow-(folding|package)$"
              ,@(if folding? '() (list "--no-folding"))
              ,(string-append "--dir=" (car split))
              ,(string-append "--target=" home)
              ,@(if (string=? flag "") '() (list flag))
              ,(cdr split))))))

;; 包身份唯一判据（显式声明，不启发式——启发式会被 dot 杂物误触发）。
(define (%stow-package-dir? path)
  (file-exists? (string-append path "/" %stow-package-marker)))

;; 含一层分组目录内的包（分组是无标记目录，下钻找带标记子包）。
(define (%stow-list-packages)
  (sort
   (append-map
    (lambda (name)
      (let ([path (string-append %stow-dir "/" name)])
        (cond [(or (member name %stow-meta-names)
                   (not (file-is-directory? path)))
               '()]
              [(%stow-package-dir? path) (list name)]
              [else
               (filter-map
                (lambda (sub)
                  (let ([sub-path (string-append path "/" sub)])
                    (and (not (member sub %stow-meta-names))
                         (file-is-directory? sub-path)
                         (%stow-package-dir? sub-path)
                         (string-append name "/" sub))))
                (or (scandir path) '()))])))
    (or (scandir %stow-dir) '()))
   string<?))

;; 返回 ((mode . "adopt"|"restow"|"delete"|"stow") (packages . (...)))
(define (parse-stow-args args)
  (let loop ([rest args] [mode "stow"] [packages '()])
    (match rest
      [()
       `((mode . ,mode) (packages . ,packages))]
      [("--adopt" . rest)
       (loop rest "adopt" packages)]
      [("--restow" . rest)
       (loop rest "restow" packages)]
      [("--delete" . rest)
       (loop rest "delete" packages)]
      [(pkg . rest)
       (loop rest mode (append packages (list pkg)))])))

;;; --- §8 命令定义 ---
;; 每条命令：(define-command (xxx-command arguments)
;;            ((invoke "xxx") (category 'cat) (synopsis "...") (help "..."))
;;            <body>)

;;; ---------- 部署 ----------

;; 世代修剪上限：limine 每次 reconfigure 按全部 system 世代在 ESP 重建
;; UKI（每代约 50M），无上限会挤爆 ESP。修剪刻意放 rebuild 最前——首个
;; sudo 落在宽限期内，后续 reconfigure 不再要密码（细节见文档）。
(define %keep-system-generations 20)

;; 列出实际存在的 system 世代号（升序）。世代号单调递增、不因清理重新
;; 编号，低号段有空洞，不能按 1..N 连续范围假设。
(define (%system-generation-numbers)
  (sort (filter-map
         (lambda (name)
           (and=> (string-match "^system-([0-9]+)-link$" name)
                  (lambda (m) (string->number (match:substring m 1)))))
         (or (false-if-exception (scandir "/var/guix/profiles")) '()))
        <))

;; 删最旧的溢出世代使剩余恰好 %keep-system-generations 个；数量未超限
;; 静默跳过（不起 sudo）。delete-generations 内部兜底绝不删当前代。
(define (%prune-system-generations)
  (let* ([numbers (%system-generation-numbers)]
         [stale (take numbers (max 0 (- (length numbers) %keep-system-generations)))])
    (unless (null? stale)
      (format #t "修剪系统世代 ~a（保留最新 ~a 个）~%"
              (string-join (map number->string stale) ", ")
              %keep-system-generations)
      (%guix `("system" "delete-generations"
               ,(string-join (map number->string stale) ","))
             #:sudo? #t))))

;; ⚠ Agent 不要自行运行此命令（会卡 sudo 密码提示），调试只许 blue home。
(define-command (rebuild-command arguments)
  ((invoke "rebuild")
   (category 'deployment)
   (synopsis "应用 Guix System 配置")
   (help "应用 operating-system 表。blue --dry-run rebuild 仅构建验证、不写入系统。"))
  (%prune-system-generations)
  ((command-procedure clean-artifacts-command) '())
  (apply-config "system" "%system"
                #:sudo? #t
                #:after (lambda () (%guix '("locate" "--update")))))

;; 不需 sudo，agent 首选调试方式。
(define-command (home-command arguments)
  ((invoke "home")
   (category 'deployment)
   (synopsis "应用 Guix Home 配置")
   (help "应用 home-environment 表。blue --dry-run home 仅构建验证、不写入系统。"))
  ((command-procedure clean-artifacts-command) '())
  (apply-config "home" "%home"))

;; dry-run 下仅 tangle+括号检查+预演打印，不做 build 验证（init 没有
;; build --dry-run 降级；应急脚本 emergency-blue.sh 有）。
(define-command (init-command arguments)
  ((invoke "init")
   (category 'deployment)
   (synopsis "将系统配置安装到 /mnt")
   (help "将 operating-system 表安装到 /mnt。"))
  (let ([scm (prepare-config "%system")])
    (format #t "正在将系统安装到 /mnt~%")
    (%guix `("system" "init" ,scm "/mnt") #:sudo? #t)
    ;; dry-run 下 reconfigure 未发生，保留 tmp/ 产物供检查（同 apply-config 守卫）
    (unless (dry-build?)
      (false-if-exception (delete-file-recursively %tmp-dir)))))

;; ---- Live ISO 辅助（build-iso-command 用） ----
;; 每个变体对应 config.org 独立 tangle 目标 tmp/live-iso-<variant>.scm
;; （desktop=XFCE 救援桌面，minimal=TUI 安装器；详见 docs/iso-build.md）。

;; ISO 变体列表（顺序即构建顺序：先 desktop 主目标，再 minimal fallback）。
(define %images '("desktop" "minimal"))

(define (images-from-arguments arguments)
  (if (null? arguments)
      %images
      (filter (cut member <> arguments) %images)))

;; 拼合 ISO 文件名（不含路径）：<prefix>-<variant>-<YYYYMMDD>.<arch>.iso。
(define (%live-iso-filename variant)
  (format #f "~a-~a-~a.~a.iso"
          "jeans" variant
          (date->string (current-date) "~Y~m~d")
          (%current-system)))

;; 先 tangle 让 live-iso 目标块出产物，再对每个变体调 build-image.scm
;; （guix repl 子进程）。构建耗时 30+ 分钟，见 docs/iso-build.md。
(define-command (build-iso-command arguments)
  ((invoke "build-iso")
   (category 'deployment)
   (synopsis "构建 Guix System Live ISO")
   (help "[VARIANT] ...
构建 Live ISO 镜像，产物落到 dist/jeans-<variant>-<YYYYMMDD>.<arch>.iso。
不带参数则构建 %images 列出的所有变体；带参数只构建匹配 VARIANT 的。"))
  (tangle-config)
  (mkdir-p (string-append %repo-root "/dist"))
  (every
   (cut eq? #t <>)
   (map
    (lambda (variant)
      (let* ([iso-name (%live-iso-filename variant)]
             [iso-path (string-append %repo-root "/dist/" iso-name)]
             [scm (string-append %tmp-dir "/live-iso-" variant ".scm")])
        (format #t "\tBUILD ISO\t~a~%" iso-name)
        (%guix `("repl" "--"
                 ,(string-append %tools-dir "/build-image.scm")
                 ,iso-path ,scm "--image-type=iso9660"))))
    (images-from-arguments arguments))))

;;; ---------- 编辑 ----------

;; 块名只允许字母/数字/连字符/下划线：block-show 的 name 拼进输出路径、
;; block-replace 的 name 交给 elisp，特殊字符（../ 与空白）会构成
;; 路径穿越 / 匹配注入面。
(define (%valid-block-name? name)
  (and (string? name) (not (string-null? name))
       (string-every (lambda (c)
                       (or (char-alphabetic? c) (char-numeric? c)
                           (memv c '(#\- #\_))))
                     name)))

;; 输出文件前两行是 lang/noweb 标记，第三行起是 body（协议见 org-block-tools.md）。
(define-command (block-show-command arguments)
  ((invoke "block-show")
   (category 'editing)
   (synopsis "提取指定名称的 Org 源代码块")
   (help "BLOCK
从 source/config.org 提取 BLOCK 到 tmp/block-BLOCK.scm 并打印路径。"))
  (match arguments
    [(name)
     (unless (%valid-block-name? name)
       (error "block name 只允许字母/数字/-/_：" name))
     (mkdir-p %tmp-dir)
     (let* ([content (%run-elisp "block-extract" name)]
            [out-file (string-append %tmp-dir "/block-" name ".scm")])
       (call-with-output-file out-file
         (lambda (port) (display content port)))
       (format #t "~a~%" out-file))]
    [_ (error "usage: blue block-show BLOCK")]))

;; 原子写回 config.org；scheme 块自动跑 tangle+括号检查验证。
(define-command (block-replace-command arguments)
  ((invoke "block-replace")
   (category 'editing)
   (synopsis "替换指定名称的 Org 源代码块")
   (help "BLOCK BODY-FILE
用 BODY-FILE 替换 source/config.org 中的 BLOCK。替换后自动验证 Scheme 代码块。"))
  (match arguments
    [(name body-file)
     (unless (%valid-block-name? name)
       (error "block name 只允许字母/数字/-/_：" name))
     ;; 真实写 source/config.org：dry-run 承诺不写入，这里短路而不是
     ;; 半途留下产物
     (when (dry-build?)
       (error "block-replace 会写入 source/config.org，dry-run 模式下禁用"))
     (mkdir-p %tmp-dir)
     (let* ([out-org (string-append %tmp-dir "/config.org.new")]
            [output (%run-elisp "block-replace" name body-file out-org)]
            [lang (if (string-prefix? "lang=" output)
                      (string-trim-both (substring output 5))
                      "")])
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
             (format #t "[OK] 代码块 ~a（~a）已替换~%" name lang))))]
    [_ (error "usage: blue block-replace BLOCK BODY-FILE")]))

;;; ---------- Guix 频道 ----------

(define-command (pull-command arguments)
  ((invoke "pull")
   (category 'guix)
   (synopsis "通过锁定频道执行 guix pull"))
  (%guix '("pull" "--allow-downgrades" "--fallback")))

;; ---- 单频道刷新辅助（blue update --channel 用） ----

;; 生成"单频道刷新"的临时 channels 文件：目标频道用 channel.scm 定义
;; （commit 非 #f 时 pin 到该 commit），其余用 channel.lock 的锁定版本。
;; 必须走 guix repl 子进程：blue 的 Guile 环境缺 (guix openpgp) 等模块，
;; 展开 openpgp-fingerprint 宏会报 unbound variable（契约见
;; docs/scripts/blue-helpers.md §gen-partial.scm）。
(define (%partial-channels-file target commit)
  (let ([out (string-append %tmp-dir "/update-channels.scm")])
    (if (dry-build?)
        (begin
          (format #t "[预演] 生成单频道刷新文件 ~a（目标: ~a~a，其余 pin）~%"
                  out target (if commit (format #f " pin@~a" commit) ""))
          ;; 预演时不实际生成临时文件，直接复用原 channel.scm 以通过后续的 dry-run 分支
          %channel-scm)
        (begin
          (mkdir-p %tmp-dir)
          (%run `("guix" "repl"
                  ,(string-append %tools-dir "/gen-partial.scm")
                  ,target ,out
                  ,@(if commit (list commit) '()))
                #:real? #t)
          out))))

;; 解析 blue update 的参数 → (guix nix)。每侧为 #f（不更新）、'all（全量）
;; 或单目标：nix 侧为 flake 名字符串，guix 侧为 (频道名 . commit) 对——
;; commit 为 #f 表示刷新到 branch 最新，字符串表示 pin 到该 commit。
;; -c/--channel 需搭配 --guix、-C/--commit 需搭配 -c、--flake 需搭配 --nix。
(define (%update-scope arguments)
  (let loop ([rest arguments] [guix #f] [nix #f])
    (match rest
      [() (list guix nix)]
      [("--guix" . more)
       (if guix (error "重复指定 --guix") (loop more 'all nix))]
      [("--nix" . more)
       (if nix (error "重复指定 --nix") (loop more guix 'all))]
      [((or "-c" "--channel") name . more)
       (match guix
         [(n . _) (error "重复指定 -c/--channel")]
         ['all
          (if (string-null? name)
              (error "-c/--channel 不能为空")
              (loop more (cons name #f) nix))]
         [_ (error "-c/--channel 需搭配 --guix（用法: blue update --guix -c NAME [-C COMMIT]）")])]
      [((or "-C" "--commit") commit . more)
       (match guix
         [(name . #f)
          (if (string-null? commit)
              (error "-C/--commit 不能为空")
              (loop more (cons name commit) nix))]
         [(name . _) (error "重复指定 -C/--commit")]
         [_ (error "-C/--commit 需搭配 -c/--channel（用法: blue update --guix -c NAME -C COMMIT）")])]
      [("--flake" name . more)
       (match nix
         ['all (loop more guix name)]
         [_ (error "--flake 需搭配 --nix（用法: blue update --nix --flake NAME）")])]
      [_ (error "usage: blue update [--guix [-c NAME [-C COMMIT]]] [--nix [--flake NAME]]")])))

;; 锁文件有实际变化才提交：单频道/单 flake 刷新常无新版本，git commit 的
;; 空提交以非零退出会让 %run 当失败报错。git status 只读，真跑无害；
;; dry-run 下锁文件不会被写，直接视作有变化以保留 commit 预演输出。
(define (%commit-lock file message)
  (when (or (dry-build?)
            (pair? (%pipe->lines (%shell-command
                                  `("git" "status" "--porcelain" "--" ,file)))))
    (%run `("git" "commit" "-S" "-m" ,message ,file))))

(define (%lock-commit-message target)
  (match target
    ['all "build(channel.lock): bump channels"]
    [(name . #f) (format #f "build(channel.lock): bump ~a" name)]
    [(name . commit)
     (format #f "build(channel.lock): pin ~a at ~a"
             name (substring commit 0 (min 8 (string-length commit))))]))

;; guix 侧更新：用可变频道定义跑 guix describe，结果原子写回 channel.lock。
;; dry-run 仅预演、不写 channel.lock：describe 是捕获 stdout 的管道命令，
;; 不走 %run 短路，必须在此手动短路。
(define (%update-guix target)
  (let* ([channels-file (if (eq? target 'all)
                            %channel-scm
                            (%partial-channels-file (car target) (cdr target)))]
         [describe (%guix-command '("describe" "--format=channels")
                                  #:channels channels-file)])
    (if (dry-build?)
        (%print-preview describe)
        (let ([content (%pipe->string (%shell-command describe))])
          (%write-file-atomically %channel-lock
                                  (lambda (port) (display content port))))))
  (%commit-lock %channel-lock (%lock-commit-message target)))

;; nix 侧更新：'all 先刷 nix channel 再全量刷新 flake.lock；给 flake 名则
;; 只更新该 input（nix 2.19+ 语法）。nix 命令全走 %run，dry-run 自动短路。
(define (%update-nix target)
  (when (eq? target 'all)
    (%run '("nix-channel" "--update")))
  (%run `("nix" "flake" "update"
          ,@(if (string? target) (list target) '())
          "--flake" ,%nix-dir))
  (%commit-lock (string-append %nix-dir "/flake.lock")
                (if (string? target)
                    (format #f "build(flake.lock): bump ~a" target)
                    "build(flake.lock): bump flake inputs")))

(define-command (update-command arguments)
  ((invoke "update")
   (category 'guix)
   (synopsis "更新 channel.lock / flake.lock 并提交")
   (help "[--guix [-c NAME [-C COMMIT]]] [--nix [--flake NAME]]
不带参数：guix 频道与 Nix 全部刷新。
--guix：只刷新 guix 频道；-c/--channel NAME 只刷新该频道，其余保持 channel.lock 锁定的 commit。
-C/--commit COMMIT：搭配 -c 使用，目标频道 pin 到指定 commit 而非刷新到最新。
--nix：只更新 Nix；--flake NAME 只更新该 flake input（不刷 nix channel）。"))
  (match (match (%update-scope arguments)
           ;; 无任何参数 → 两侧全量
           [(#f #f) '(all all)]
           [scope scope])
    [(guix nix)
     (when guix (%update-guix guix))
     (when nix (%update-nix nix))]))

;;; ---------- 维护 ----------

;; system 删世代需 sudo；仅作为 gc 的内部过程。
(define (%clean-generations)
  (%run '("sh" "-c" "sudo guix system delete-generations > /dev/null"))
  (%run '("sh" "-c" "guix home delete-generations > /dev/null")))

;; rebuild / home 前自动先跑。目录删除不走 %run，必须显式守
;; dry-build?——否则 dry-run 也会真删（原实现即此 bug）。
(define-command (clean-artifacts-command arguments)
  ((invoke "clean-artifacts")
   (category 'maintenance)
   (synopsis "移除仓库编译产物")
   (help "移除仓库内的 __pycache__、*.elc、*.o、*.a、*.so 文件以及 Emacs 运行时缓存目录。"))
  (for-each
   (match-lambda
     [(target type)
      (if (eq? type 'directory)
          (when (file-exists? target)
            (if (dry-build?)
                (format #t "\t[预演]\t移除 ~a~%" target)
                (begin
                  (format #t "移除 ~a~%" target)
                  (delete-file-recursively target))))
          (%run `("find" ,%repo-root "-type" "f" "-name" ,target
                  "-not" "-path" "*/.git/*"
                  "-print" "-delete")))])
   `(("__pycache__" directory)
     ("*.elc" file)
     ("*.o" file)
     ("*.a" file)
     ("*.so" file)
     ("main.el" file)
     ("org-roam.db" file)
     (,(string-append %stow-dir "/emacs/.config/emacs/etc") directory)
     (,(string-append %stow-dir "/emacs/.config/emacs/var") directory))))

;; 删旧世代 → guix gc → 删旧 EFI（均需人工触发）。
(define-command (gc-command arguments)
  ((invoke "gc")
   (category 'maintenance)
   (synopsis "删除旧世代、执行 Guix GC 并清理旧 Guix EFI 文件")
   (help "依次删除旧 system/home 世代、执行 guix gc 并删除 /efi/EFI/Guix/OLD-*.EFI。删除 system 世代与 EFI 文件需要 sudo。"))
  (%clean-generations)
  (%run '("guix" "gc"))
  ;; %run 经 popen 直 exec、无 shell 展开，OLD-*.EFI 须在 Guile 侧收集后
  ;; 逐个删除。ESP 挂载点是 /efi（limine-efi-removable-bootloader 的
  ;; targets），旧命令的 /boot/EFI/Guix 路径在这台机器上并不存在。
  (let ([stale (or (false-if-exception
                    (scandir "/efi/EFI/Guix" (cut string-prefix? "OLD-" <>)))
                   '())])
    (if (null? stale)
        (format #t "没有待清理的 OLD-*.EFI~%")
        (for-each (lambda (name)
                    (%run `("sudo" "rm" "-rf" ,(string-append "/efi/EFI/Guix/" name))))
                  stale))))

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

;; 委派 tools/doc-format.sh（编排规则见 docs/scripts/doc-format.md）：
;; 先 doc-punct.py 规范标点，再 prettier 统一 Markdown 结构。
(define-command (format-command arguments)
  ((invoke "format")
   (category 'maintenance)
   (synopsis "规范化仓库文档的中文标点与 Markdown 排版")
   (help "按仓库文档规范跑两级格式化：

1. doc-punct.py 规范中文标点与中英间距（规则见 docs/scripts/doc-punct.md）；
2. prettier 统一 Markdown 结构——表格列宽、列表缩进、末尾换行。

正文不做折行：仓库规范禁止把段落按固定列宽切断，.prettierrc.json 的
proseWrap=preserve 即为此设；文档内嵌的代码块也不重排，示例的写法归作者。

不带 FILE 时经 doc-punct.py --list 取仓库自有文档清单（排除 vendored
子模块与 agent skills）。.org 只跑标点一级，prettier 不认 org。

  blue format                处理全部文档
  blue format source/README  只处理指定文件
  blue --dry-run format      仅预演打印，不执行脚本
  blue format --check        只报告待处理项，有改动退出 1"))
  (%run `("bash" ,(string-append %tools-dir "/doc-format.sh") ,@arguments)))

;; 深度优先级：标记内 `depth=N' > ORG_STRUCTOR_DEPTH > 默认 4；
;; ORG_STRUCTOR_DRY=1 预览。
(define-command (structor-command arguments)
  ((invoke "structor")
   (category 'maintenance)
   (synopsis "刷新 AGENTS.md 中自动生成的目录树章节")
   (help "[TARGET] ...
刷新所有 structor 目标，或仅刷新指定的 AGENTS.md。
可见性遵循 .gitignore（git ls-files 驱动）。
深度优先级：标记内 `<!-- structor:begin depth=N -->` > ORG_STRUCTOR_DEPTH > 默认 4。"))
  (let* ([depth (or (and=> (getenv "ORG_STRUCTOR_DEPTH") string->number) 4)]
         [targets (if (null? arguments) (%structor-targets) arguments)]
         [dry? (or (and=> (getenv "ORG_STRUCTOR_DRY") (negate string-null?))
                   (dry-build?))])
    (run-structor targets #:depth depth #:dry? dry?)))

;;; ---------- Nix 备用 ----------

;; 备用 Nix home-manager（与 Guix 不互通）；配置名显式指定为 Guix
;;（flake.nix 的 homeConfigurations.Guix）。
(define-command (nix-command arguments)
  ((invoke "nix")
   (category 'nix)
   (synopsis "应用备用 Nix home-manager 配置"))
  (%run `("nh" "home" "switch" ,%nix-dir
          "--configuration" "Guix"
          "--backup-extension" "backup")))

;; 首次或损坏后引导：不依赖 channel / nh / 现有 profile，版本由 flake.lock 锁定。
(define-command (nix-init-command arguments)
  ((invoke "nix-init")
   (category 'nix)
   (synopsis "构建并激活备用 Nix home-manager 配置"))
  (%run `("nix" "build" ,(string-append %nix-dir "#homeConfigurations.Guix.activationPackage")
          "--out-link" "/tmp/hm-activation"))
  (%run '("/tmp/hm-activation/activate")))

;;; ---------- 校验 ----------

;; 额外裸参数作为正则扩展；GUIX_SECRET_SCAN_FAIL_ON_FIND=0 把报错降为警告。
(define-command (secret-scan-command arguments)
  ((invoke "secret-scan")
   (category 'validation)
   (synopsis "扫描文本配置文件中疑似泄漏的密钥")
   (help "[DIR] [PATTERN] ...
扫描 DIR（默认为 dotfiles/immutable）。额外正则模式可作为后续参数传入。
设置 GUIX_SECRET_SCAN_FAIL_ON_FIND=0 可仅警告而不报错。"))
  (let* ([dir (if (null? arguments) "dotfiles/immutable" (first arguments))]
         [extra (if (null? arguments) '() (cdr arguments))]
         [fail? (not (string=? (or (getenv "GUIX_SECRET_SCAN_FAIL_ON_FIND") "1") "0"))])
    (scan-secrets dir fail? extra)))

;;; ---------- Stow ----------

;; 用法细节见命令 help 文本。
(define-command (stow-command arguments)
  ((invoke "stow")
   (category 'stow)
   (synopsis "用 GNU Stow 管理频繁变动的 dotfiles")
   (help "[--adopt|--restow|--delete] PKG ...
GNU Stow 直链部署 dotfiles/mutable/PKG/ 到 $HOME。改源即生效（无需 blue home）。

模式:
  blue stow PKG ...          从源部署（创建软链接）
  blue stow --adopt PKG ...  把 $HOME 下已有文件移动到源目录，再建软链接
  blue stow --restow PKG ... 强制重建所有软链接（先删除再重建）
  blue stow --delete PKG ... 删除软链接（$HOME 下变回实际文件）

PKG 支持一层分组路径（如 agents/hermes，对应 dotfiles/mutable/agents/hermes/）。

包识别（stow-all 枚举依据）:
  dotfiles/mutable/<PKG>/.stow-package      存在即该目录是一个包（空文件，仅作身份声明）
  无标记目录视为分组，下钻一层收集带标记子目录；blue stow 显式包名只查目录存在
--no-folding（默认）/ folding: 目标目录默认保持为真实目录、stow 只对单个文件建软链，
保护应用运行时产物（logs/、state.db、sessions/ 等）不污染源。想让某个包改用整目录
折叠（目标目录本身变成指向源的软链），在该包目录下放 .stow-folding 标记文件即可。
批量操作所有包见 `blue stow-all`。

folding 控制:
  dotfiles/mutable/<PKG>/.stow-folding      存在即对该包启用 tree folding（opt-in）
  其余包默认 --no-folding
忽略机制（每包 + 命令行）:
  dotfiles/mutable/<PKG>/.stow-local-ignore  每包 Perl 正则，逐行，# 注释允许
  --ignore=REGEX              命令行一次性（blueprint 内部固定加 --ignore=\\.stow-(folding|package)$）

源目录布局: dotfiles/mutable/PKG/.local/share/hermes/ -> ~/.local/share/hermes/
改后用 git commit 备份。配合 dotfiles/immutable/ 的 Guix stow（仅读源）使用。"))
  (let* ([parsed (parse-stow-args arguments)]
         [mode (assq-ref parsed 'mode)]
         [packages (assq-ref parsed 'packages)]
         [home (or (getenv "HOME") "/root")])
    (when (null? packages)
      (error "stow: 至少需要一个包名（批量操作请用 blue stow-all）"))
    (unless (file-exists? %stow-dir)
      (error (format #f "stow 源目录不存在: ~a" %stow-dir)))
    (for-each (cut %stow-package <> mode home) packages)))

;; 裸参数作为包名过滤（为空取全部）；逐一执行，遇错即停。
(define-command (stow-all-command arguments)
  ((invoke "stow-all")
   (category 'stow)
   (synopsis "对 dotfiles/mutable/ 下所有包批量执行 stow 操作")
   (help "[--adopt|--restow|--delete]
枚举 dotfiles/mutable/ 下所有包（含一层分组目录内的包，如 agents/hermes），逐个执行。默认为部署。

  blue stow-all              部署所有包
  blue stow-all --restow     重建所有软链接（最常用）
  blue stow-all --delete     撤销所有软链接（$HOME 下变回实际文件）
  blue stow-all --adopt      把 $HOME 下已有文件收养进各包源

逐一执行，遇错即停（与 blue stow 一致）。语义同 blue stow，见其帮助。"))
  (let* ([parsed (parse-stow-args arguments)]
         [mode (assq-ref parsed 'mode)]
         ;; --restow 等模式开关之外的裸参数视为包名过滤；为空则取全部。
         [only (assq-ref parsed 'packages)]
         [home (or (getenv "HOME") "/root")])
    (unless (file-exists? %stow-dir)
      (error (format #f "stow 源目录不存在: ~a" %stow-dir)))
    (let ([packages
           (if (null? only)
               (%stow-list-packages)
               (filter (cut member <> only) (%stow-list-packages)))])
      (when (null? packages)
        (error "stow-all: dotfiles/mutable/ 下无可用包（或指定的包不存在）"))
      (format #t "stow-all: 共 ~a 个包，模式=~a~%" (length packages) mode)
      (for-each (cut %stow-package <> mode home) packages))))

;;; ---------- 帮助 ----------

(define-command (list-command arguments)
  ((invoke "list")
   (category 'help)
   (synopsis "列出项目指令")
   (help "列出本项目可用指令及其用途。"))
  (print-command-list))

;; 命令分类表：单一清单，同时驱动 blue list 的展示与 §9 的注册。
;; 必须定义在全部命令之后——quasi-quote 在定义求值时刻就取各命令变量的值。
(define %command-categories
  `(("部署 (deployment)" ,rebuild-command ,home-command ,init-command ,build-iso-command)
    ("编辑 (editing)" ,block-show-command ,block-replace-command)
    ("Guix 频道 (guix)" ,pull-command ,update-command)
    ("维护 (maintenance)" ,clean-artifacts-command
     ,format-command ,gc-command ,reuse-command ,structor-command)
    ("Nix 备用 (nix)" ,nix-command ,nix-init-command)
    ("Stow (stow)" ,stow-command ,stow-all-command)
    ("验证 (validation)" ,secret-scan-command)
    ("帮助 (help)" ,list-command)))

(define (print-command-list)
  (display "本项目自写指令：\n")
  (for-each
   (lambda (cat)
     (format #t "~%  ~a~%" (car cat))
     (for-each
      (lambda (cmd)
        (format #t "    ~a\t~a~%" (command-invoke cmd) (command-synopsis cmd)))
      (cdr cat)))
   %command-categories)
  (format #t "~%共 ~a 条。详细帮助：blue help <命令名>~%"
          (length (concatenate (map cdr %command-categories)))))

;;; --- §9 入口点：注册给 blue 框架 ---

(blueprint
 (buildables (list %config-buildable))
 (testables (list %config-check))
 (commands (concatenate (map cdr %command-categories))))
