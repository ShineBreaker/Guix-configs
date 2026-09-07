;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;;; ============================================================
;;; blueprint.scm —— blue 任务运行器（项目主入口）
;;; ============================================================
;;;
;;; 定义 `blue` 在本项目能跑的全部指令（sub-commands），并接入 blue 框架
;;; 所需的 buildable / testable 钩子。全文按"从底层到上层"分节：
;;;
;;;   §0  路径常量            —— 绝对路径集中于此，方便整体迁移
;;;   §1  子进程执行          —— %run 及 guix / emacs 包装（唯一子进程出口）
;;;   §2  文件与管道 I/O      —— 原子写、shell 拼接、管道读取
;;;   §3  括号平衡检查        —— 手写词法扫描 + 统一报告
;;;   §4  配置管线与块解析    —— config.org → config.scm → reconfigure
;;;   §5  密钥扫描            —— secret-scan 命令的实现
;;;   §6  目录树生成器        —— structor 命令的实现
;;;   §7  GNU Stow 包装       —— stow / stow-all 命令的实现
;;;   §8  命令定义            —— 每条 `blue <指令>` 的实际逻辑
;;;   §9  入口点              —— (blueprint ...) 注册一切
;;;
;;; 【关键不变量】改动前请先理解：
;;;   * `blue build` / `blue check` / `blue clean` 是 blue 框架的【内建
;;;     命令】；本文件通过 <org-config>（buildable）和 <paren-check>
;;;     （testable）两个类告诉它们"建什么 / 测什么"。
;;;   * `%run` 是所有直接子进程的唯一出口。`blue --dry-run` 时它默认短路
;;;     （只打印不执行）；必须真跑的（tangle、括号检查）传 `#:real? #t`。
;;;     走 shell 管道读取的命令（%pipe->string / %pipe->lines）不经过
;;;     %run 短路，调用方需自行确认在 dry-run 下无害。
;;;   * tools/*.scm 与 tools/*.el 必须跑在 guix / emacs 子进程环境：blue
;;;     的 Guile 进程没有 guix 模块树（展开 openpgp-fingerprint 宏会报
;;;     unbound variable），见 §8 的 update / build-iso。
;;;   * 改源 ≠ 生效：~/.config/<app>/ 指向 /gnu/store 只读副本，改完
;;;     dotfiles 要 `blue home` 才同步。

(use-modules (blue build)               ; make-build-manifest
             (blue states)              ; dry-build?
             (blue types)               ; define-blue-class / define-blue-method
             (blue types blueprint)     ; blueprint 主入口
             (blue types buildable)     ; <buildable> 基类
             (blue types command)       ; define-command 宏
             (blue types testable)      ; <testable> 基类（接 blue check）
             (blue subprocess)          ; popen（子进程，返回退出码）
             (guix utils)               ; %current-system（ISO 文件名用）
             (guix build utils)         ; mkdir-p / delete-file-recursively / find-files
             (ice-9 ftw)                ; scandir（列目录）
             (ice-9 format)             ; format 完整版（~{ ~} 迭代指令需要，
                                        ;  core 的 simple-format 不支持）
             (ice-9 match)              ; match / match-lambda
             (ice-9 popen)              ; open-input-pipe / close-pipe
             (ice-9 rdelim)             ; read-line
             (ice-9 regex)              ; string-match / make-regexp
             (ice-9 textual-ports)      ; get-string-all（读整个文件）
             (srfi srfi-1)              ; first / filter-map / any / every / concatenate
             (srfi srfi-19)             ; date->string（ISO 文件名）
             (srfi srfi-26))            ; cut（简写 lambda）

;;; ============================================================
;;; §0  路径常量
;;; ============================================================
;;; `%repo-root' 取决于运行 blue 时的工作目录（见 bootstrap.sh 的 cd）。

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

;;; ============================================================
;;; §1  子进程执行 —— 跑外部命令的统一出口
;;; ============================================================

;; 子进程失败的统一出口：打一行错误并以子进程退出码终止。刻意不用
;; (error ...)：blue 框架会给任何异常打整套 Guile backtrace，而"子进程
;; 非零退出"是预期内失败，堆栈无诊断价值。必须用 primitive-exit——Guile
;; 的 `exit' 抛 `quit' 异常仍会被框架捕获照打 backtrace。本文件其余逻辑
;; 校验的 error 保留 backtrace，便于定位 Scheme 逻辑 bug。
(define (%subprocess-fail! status message)
  (format (current-error-port) "~a~%" message)
  (primitive-exit (or status 1)))

;; dry-run 预演打印。%run 短路时用它；需要手动短路管道命令的调用方
;; （如 update 的 describe）也用它，保证预演输出格式一致。
(define (%print-preview command)
  (match command
    [(program . args)
     (format #t "\t[预演]\t~a ~{~a ~}~%" program args)]))

;; 唯一允许启动子进程的地方。`blue --dry-run' 时默认只打印不执行；
;; #:real? #t 是逃生口（tangle、括号检查等 dry-run 下也必须真跑）。
(define* (%run command #:key real?)
  (if (and (dry-build?) (not real?))
      (begin (%print-preview command) #t)
      (match command
        [(program . args)
         (let ([status (popen program args)])
           (unless (zero? status)
             (%subprocess-fail! status
                                (format #f "命令执行失败 (~a): ~s" status command)))
           #t)])))

;; 构造（但不执行）一条锁定频道的 guix 命令。所有 guix 调用都必须走
;; `guix time-machine --channels=...'，否则频道版本与 channel.lock 不一致，
;; 构建结果不可复现。%guix、%emacs-command、update 命令共用此构造。
(define* (%guix-command args #:key (channels %channel-lock))
  `("guix" "time-machine"
    ,(string-append "--channels=" channels) "--"
    ,@args))

;; 执行一条锁定频道的 guix 命令；#:sudo? #t 时在最前面加 sudo。
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

;;; ============================================================
;;; §2  文件与管道 I/O
;;; ============================================================

;; 原子写文件：先写 file.XXXXXX 临时文件，成功后 rename 覆盖目标。任何
;; 中途异常都清理临时文件，目标绝不停留在"写一半"状态。config.org /
;; channel.lock / AGENTS.md 等关键文件都用它。
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

;; POSIX shell 单引号转义：用 '\'' 切断再重开单引号，防注入。
(define (%shell-quote string)
  (string-append "'" (string-join (string-split string #\') "'\\''") "'"))

;; 把命令 list 转成一条 shell 字符串（各参数逐个 quote）。
(define (%shell-command command)
  (string-join (map %shell-quote command) " "))

;; 把一条 shell 命令的 stdout 按行读成 list。默认【不检查退出码】——
;; grep 等工具依赖非 0 退出码语义；#:check? #t 时非 0 视为失败（git 等）。
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

;; 把一条 shell 命令的 stdout 整体读成字符串，退出码非 0 视为失败。
(define (%pipe->string command)
  (let* ([pipe (open-input-pipe command)]
         [content (get-string-all pipe)]
         [status (status:exit-val (close-pipe pipe))])
    (unless (zero? status)
      (%subprocess-fail! status
                         (format #f "命令执行失败 (~a): ~a" status command)))
    content))

;;; ============================================================
;;; §3  括号平衡检查
;;; ============================================================
;;;
;;; 手写词法扫描而非用 guix 的 read：config.org 的块 / tangle 产物可能含
;;; unquote 等读取器宏，read 报错时定位差。只数括号并正确跳过字符串字面量
;;; 与 ; 注释，足以抓最常见的括号失配。Guile reader 要求 [ ] / ( ) 严格
;;; 配对，混搭（[ 配 )）也算错。

;; 数 port 里的圆括号和方括号，返回 5 元素向量：
;;   #(paren-open paren-close bracket-open bracket-close mismatch?)
;; 用栈记录每个开括号的类型，闭括号须与栈顶同类。
(define (count-parens port)
  (let loop ([char (read-char port)]
             [popen 0] [pclose 0]      ; 圆括号计数
             [bopen 0] [bclose 0]      ; 方括号计数
             [stack '()]               ; 括号类型栈：'paren 或 'bracket
             [mismatch? #f])
    (cond
     [mismatch?
      (vector popen pclose bopen bclose #t)]
     [(eof-object? char)
      (vector popen pclose bopen bclose #f)]
     ;; 圆括号
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
     ;; 方括号
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

;; 统一报告路径：检查 port 内容并打印 [OK]/[ERROR]（label 为文件路径或
;; "块 <名>"），返回布尔。逐块检查与整文件兜底共用这一份逻辑。
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

;; 检查单个文件的括号平衡（tangle 产物 / 周边 scm 整体兜底）。
(define (check-paren-balance file)
  (call-with-input-file file (cut %report-parens file <>)))

;;; ============================================================
;;; §4  配置构建管线与 Org 块解析
;;; ============================================================
;;;
;;;   config.org ──tangle──▶ config.scm ──括号检查──▶ (通过) ──reconfigure──▶ 系统
;;;
;;; 两个 blue 类把 tangle / 检查接进内建命令：
;;;   * <org-config>（继承 <buildable>）→ `blue build` 触发 tangle
;;;   * <paren-check>（继承 <testable>）→ `blue check` 逐块括号检查：
;;;     不 tangle，直接解析 config.org 的每个 #+NAME 块 + 周边 scm 文件，
;;;     出错定位到具体块名
;;;
;;; 块编辑的 elisp 脚本外置在 tools/block-{extract,replace,list}.el，
;;; 经 %run-elisp 以 emacs-minimal --script 方式运行。

;; ---- 两个 blue 类 --------------------------------------------------------

;; "Org 配置" buildable：输入 config.org，输出 config.scm。
(define-blue-class <org-config>
  (inherit <buildable>)
  (constructor org-config)
  (predicate org-config?))

;; "括号检查" testable：不依赖 buildable（不 tangle），输出占位标记。
(define-blue-class <paren-check>
  (inherit <testable>)
  (constructor paren-check)
  (predicate paren-check?))

;; 对任意 org 文件跑 ob-tangle（把 Noweb <<ref>> 拼合成完整 .scm）。
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
     (string-append "编织\t" output)             ; 显示用标题
     (lambda ()                                  ; 实际执行体
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

;; 两个实例：注册到 (blueprint (buildables ...)) / (testables ...) 即可被
;; `blue build` / `blue check` 发现。
(define %config-buildable
  (org-config
   (inputs '("source/config.org"))
   (outputs '("tmp/config.scm"))))

(define %config-check
  (paren-check
   (inputs '())                                  ; 不依赖 tangle，直接解析 config.org
   (outputs '("tmp/config.scm.check"))))         ; 仅作占位，内容见上

;; ---- Org 块解析（blue check 与块编辑命令的共用层） ------------------------

;; 跑 tools/<name>.el（emacs-minimal --script），extra-args 成为脚本的
;; command-line-args-left，返回脚本 stdout。
(define (%run-elisp name . extra-args)
  (%pipe->string
   (%shell-command
    (%emacs-command
     `("--quick" "--batch" "--script"
       ,(string-append %tools-dir "/" name ".el")
       ,%config-org ,@extra-args)))))

;; block-list.el 一次遍历导出全部命名块（避免每块起一个 emacs），输出用
;; >>> ... <<< 作记录分隔（避免与 body 内任意文本冲突）：
;;   >>>name=<n>\tlang=<l>\tnoweb=plain|noweb
;;   <body>
;;   <<<
;; 解析成 ((name lang noweb body) ...)；body 已去掉首尾换行。
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
        [else
         ;; body 行：累积（记录外的行丢弃）
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

;; 与 config.org 同级的独立 Scheme 源，逐个整体检查。
(define %peripheral-scm-files
  (map (cut string-append %repo-root "/" <>)
       '("source/channel.scm" "source/information.scm" "source/manifest.scm")))

;; 逐块 + 周边文件全量检查，返回总布尔。失败不立即中止——继续跑完，
;; 让用户一次看到所有错误。
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

;; ---- 三步流水线（被各 reconfigure 命令复用） -----------------------------

;; 步骤 1：tangle config.org → tmp/config.scm。
(define (tangle-config)
  (mkdir-p %tmp-dir)
  (%tangle-file %config-org))

;; 步骤 1+2：tangle 后把 tail-expression（通常是 %system 或 %home 变量名）
;; 追加到 config.scm 末尾，再整体括号兜底。返回最终 config.scm 路径。
(define (prepare-config tail-expression)
  (tangle-config)
  (let ([port (open-file %config-scm "a")])
    (display (string-append "\n" tail-expression "\n") port)
    (close-port port))
  (unless (check-paren-balance %config-scm)
    (error "配置括号平衡检查失败"))
  %config-scm)

;; 步骤 3：对 subsystem（"system" 或 "home"）执行 reconfigure。
;; dry-run 时改成 `guix <subsystem> build --dry-run`（只验证不写入）。
;; 成功后清掉 tmp/ 中间产物。`after' 是成功后的回调（rebuild 跑 locate 用）。
(define* (apply-config subsystem tail-expression #:key sudo? after)
  (let ([scm (prepare-config tail-expression)])
    (if (dry-build?)
        (begin
          (format #t "[预演] 验证 ~a 配置~%" subsystem)
          (%guix `(,subsystem "build" ,scm "--dry-run")))
        (begin
          (format #t "正在应用 ~a 配置~%" subsystem)
          ;; --no-kexec：reconfigure 默认 kexec-load 新内核，此后 elogind 的
          ;; reboot 会走 kexec 路径并挂死（action_in_progress 卡住，后续一切
          ;; 电源操作被 OperationInProgress 静默拒绝）。home 不认此选项。
          (%guix `(,subsystem "reconfigure" ,scm
                              "--allow-downgrades" "--fallback"
                              ,@(if (string=? subsystem "system")
                                    '("--no-kexec")
                                    '()))
                 #:sudo? sudo?)
          (false-if-exception (delete-file-recursively %tmp-dir)))))
  (when after (after)))

;;; ============================================================
;;; §5  密钥扫描（secret-scan 命令）
;;; ============================================================
;;;
;;; 用 grep 在文本配置里搜疑似泄漏的凭据（GitHub PAT、OpenAI key、私钥……）。
;;; 命中只代表"看起来像"，是否真泄漏需人工判断。默认找到就 error（可用于
;;; CI 卡点），设 GUIX_SECRET_SCAN_FAIL_ON_FIND=0 则只警告。

;; 参与扫描的文件扩展名（其余文件不扫，省时间）。
(define %secret-exts
  '("*.conf" "*.toml" "*.yaml" "*.yml" "*.json" "*.ini" "*.cfg"
    "*.gitconfig" "*.scm" "*.fish" "*.el" "*.env" "*.netrc" "*.properties"))

;; 扫描时跳过的目录（.git/缓存/构建产物等）。
(define %secret-exclude-dirs
  '(".git" ".agents" "node_modules" "tmp" ".blue-store"))

;; 已知凭据的正则模式表：(显示名 . 正则)。可被 secret-scan 的额外参数扩展。
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

;; 拼两条 grep 命令共用的 --include / --exclude-dir 选项串。
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

;; 统计 dir 下参与扫描的文件数（仅用于扫描结束后的提示信息）。
(define (%secret-count-files dir)
  (let ([lines (%pipe->lines
                (string-append (%secret-grep-options "grep -rIl")
                               " -e '.' " (%shell-quote dir)
                               " 2>/dev/null | wc -l"))])
    (if (null? lines)
        0
        (or (string->number (string-trim-both (first lines))) 0))))

;; 扫描 dir。fail?=真 时发现密钥就 error；extra-patterns 是用户额外传入的
;; 正则。返回 #t（无命中或仅警告）/ 抛错（fail? 且有命中）。
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

;;; ============================================================
;;; §6  目录树生成器（structor 命令）
;;; ============================================================
;;;
;;; 仓库里每个 AGENTS.md 都有一个被标记圈起的"## 目录结构"章节，内容由
;;; 本节代码自动生成（树形 ASCII 图）。新增/移动文件后跑 `blue structor`
;;; 刷新所有 AGENTS.md 的目录树。详见仓库根 AGENTS.md 的同名章节。
;;;
;;; 标记格式（独立于运行器）：
;;;   <!-- structor:begin depth=N -->     ← N 可选，覆盖默认深度
;;;   ... 自动生成的树 ...
;;;   <!-- /structor -->
;;;
;;; 【可见性 = git 驱动】对每个 target 所在目录跑
;;; `git ls-files --cached --others --exclude-standard`，拿到"git 能看见的
;;; 所有相对路径"。一个条目可见 ⟺ 列表里有等于它、或以 `<它>/` 为前缀的
;;; 路径。这样根 .gitignore + 所有嵌套 .gitignore + submodule gitlink 都
;;; 自动正确。额外只结构化跳过两类 git 不会帮我们挡的：AGENTS.md（树所在
;;; 文件本身，不能列出自己）和 `*.swp`（编辑器交换文件）。

(define %structor-marker-end "<!-- /structor -->")

;; 同时识别 begin 标记行并抽取 depth=N。depth 组整体可选（兼容无参数标记）。
;; Guile ERE：`(`、`)` 是分组符号（不是字面括号），故无需 `\\` 转义。
(define %structor-depth-regex
  (make-regexp
   "<!--[[:space:]]*structor:begin([[:space:]]+depth[[:space:]]*=[[:space:]]*([0-9]+))?[[:space:]]*-->"))

;; 枚举仓库内所有需要维护目录树的 AGENTS.md/README.md（返回相对路径）。
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

;; git 之外的硬性跳过：`.` / `..` 隐式条目、AGENTS.md（树所在文件自身）、
;; `*.swp` 编辑器交换文件（可能被 git 跟踪）。其余一律由 git 可见性决定。
(define (%structor-skip? name)
  (or (member name '("." ".." "AGENTS.md"))
      (string-suffix? ".swp" name)))

;; 对 scope 目录跑 git ls-files，返回"git 能看见的所有相对路径"列表
;; （相对 scope）。退出码非 0（非 git 仓库）→ error 中止。
(define (%structor-git-visible-paths scope)
  (%pipe->lines
   (%shell-command
    `("git" "-C" ,scope "ls-files" "--cached" "--others" "--exclude-standard"))
   #:check? #t))

;; 条目 rel（相对 scope 的路径）是否在 git 可见路径集合 visible 中。
(define (%structor-visible? rel visible)
  (let ([prefix (string-append rel "/")])
    (any (lambda (p) (or (string=? p rel) (string-prefix? prefix p))) visible)))

;; 列出 dir 的直接子条目，目录在前文件在后（各自字母序）。返回
;; ((is-dir? . name) ...)。rel-of 把 dir 内的 name 翻译成相对 scope 的
;; 路径，供可见性判断用（每下钻一层由 %structor-render 套一层前缀）。
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

;; 递归渲染 dir 的树形行列表。max-depth 限制深度；depth/prefix 是递归状态。
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

;; dir 的根标签：通常 (basename dir)。但 scope 为仓库根时 dir 形如
;; `<repo>/.`，basename 返回 "."，退一阶取仓库名（如 "Guix-configs"）。
(define (%structor-root-label dir)
  (let ([base (basename dir)])
    (if (string=? base ".")
        (basename (dirname dir))
        base)))

;; 渲染 dir 的整棵树，顶部加一行根目录名。
(define (%structor-tree dir visible depth)
  (cons (string-append (%structor-root-label dir) "/")
        (%structor-render dir visible depth 0 "" identity)))

;; 从 AGENTS.md 的正文 content 里解析第一个 structor begin 标记带的
;; depth。返回整数 depth 或 #f（无标记 / 标记无 depth 参数）。
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

;; 在 content 里用 replacement 替换 structor 标记之间的内容。返回新内容
;; （没找到标记则 #f 表示无需改动）。begin 行用 regex 匹配（兼容 depth=N
;; 写法）；end 行精确匹配。
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
        ;; 进入标记：把整段替换内容塞进输出，状态切到 in-block
        [(and (eq? state 'normal)
              (regexp-exec %structor-depth-regex (string-trim-both line)))
         (loop rest (append (reverse replacement) out) 'in-block #t)]
        ;; 离开标记：状态切回 normal（标记行本身被丢弃）
        [(and (eq? state 'in-block)
              (string=? (string-trim-both line) %structor-marker-end))
         (loop rest out 'normal changed?)]
        ;; normal 态：原样保留；in-block 态：丢弃原标记区内容
        [(eq? state 'normal)
         (loop rest (cons line out) state changed?)]
        [else
         (loop rest out state changed?)])])))

;; 对每个 target AGENTS.md 渲染并写回目录树。dry?=#t 时只打印不写。
;; depth 作为全局回退默认；标记内 `depth=N`（经 %structor-parse-depth）优先。
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

;;; ============================================================
;;; §7  GNU Stow 包装（stow / stow-all 命令）
;;; ============================================================
;;;
;;; dotfiles/mutable/ 目录用 GNU Stow 直接建软链接到仓库源（改源即生效，
;;; 无需 blue home），与 dotfiles/immutable/（Guix Home stow，只读 store
;;; 副本）互补。适合频繁手改且需 git 备份的配置（emacs / pi / hermes）。
;;;
;;; 包身份与行为均由包目录下的标记文件显式声明：.stow-package 声明
;;; "这是一个包"（stow-all 枚举依据），.stow-folding 按包 opt-in 整目录
;;; 折叠。无标记目录只可能是分组容器，下钻一层找带标记的子包。

;; 枚举包时跳过的仓库元目录。包身份由 .stow-package 标记声明，无标记
;; 目录（.mimosa/.github/node_modules 等 dot 杂物）只会作为分组下钻、
;; 天然产不出包，故名单只剩 .git——避免下钻时 scandir 巨大的对象库。
(define %stow-meta-names '("." ".." ".git"))

;; 把 --adopt/--restow/--delete 模式名翻译成 stow 命令行 flag 与中文动词。
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

;; 标记文件名：放在 dotfiles/mutable/<PKG>/.stow-folding 即对该包启用
;; tree folding（目标目录整目录折叠成单条软链）。无标记的包走默认
;; --no-folding（真实目录 + 逐文件软链，保护应用运行时产物不污染源）。
(define %stow-folding-marker ".stow-folding")

(define (%stow-folding? pkg)
  (file-exists? (string-append %stow-dir "/" pkg "/" %stow-folding-marker)))

;; 标记文件名：放在 dotfiles/mutable/<PKG>/.stow-package 即声明该目录是
;; 一个 stow 包（stow-all 的枚举依据）。空文件，仅作身份声明；blue stow
;; 显式指定包名不受此限（只查目录存在）。
(define %stow-package-marker ".stow-package")

;; 把 "group/pkg" 形式的包名拆成 (实际 stow-dir . 一级包名)。分组前缀并入
;; --dir，stow 本身永远只收一级包名（GNU Stow 不保证接受带斜杠的包名）。
(define (%stow-split-pkg pkg)
  (let loop ([i (- (string-length pkg) 1)])
    (cond [(< i 0) (cons %stow-dir pkg)]
          [(char=? (string-ref pkg i) #\/)
           (cons (string-append %stow-dir "/" (substring pkg 0 i))
                 (substring pkg (+ i 1) (string-length pkg)))]
          [else (loop (- i 1))])))

;; 对单个包执行 stow。--ignore=\.stow-(folding|package)$ 始终带上，确保
;; 标记文件本身永不部署到 $HOME（多个包的同名标记会冲突）。
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

;; 包身份唯一判据：目录下存在 .stow-package 标记。此前的启发式（目录内
;; 含 dot 条目即包）会被分组目录里的 dot 杂物（.gitignore/.mimosa 等）
;; 误触发、也会漏掉尚未放内容的空包，故改为显式声明。
(define (%stow-package-dir? path)
  (file-exists? (string-append path "/" %stow-package-marker)))

;; 枚举 dotfiles/mutable/ 下所有包（含一层分组目录内的包），按字母序。
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

;; 解析 blue stow / blue stow-all 的命令行参数：裸参数视为包名，
;; --adopt/--restow/--delete 设置模式。
;; 返回 alist：((mode . "adopt"|"restow"|"delete"|"stow") (packages . (...)))
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

;;; ============================================================
;;; §8  命令定义
;;; ============================================================
;;;
;;; 每条命令用 define-command 定义，统一形态：
;;;   (define-command (xxx-command arguments)
;;;     ((invoke "xxx")           ; 命令名（blue xxx）
;;;      (category 'cat)          ; 分类（影响 blue list 归组）
;;;      (synopsis "...")         ; 一句话（blue list 用）
;;;      (help "..."))            ; 多行帮助（blue help xxx 用）
;;;     <body>)
;;;
;;; `arguments' 是命令行剩余参数列表。`(command-procedure foo-command)'
;;; 取另一条命令的过程，用于复用（如 rebuild 先跑 clean-artifacts）。

;;; ---------- 部署 ----------

;; 世代修剪上限。limine 每次reconfigure都按当时全部 system 世代在 ESP 重建
;; UKI（CURRENT.EFI + 每个旧世代一个 OLD-N.EFI，单个约 50M），世代无上限增长
;; 会挤爆 ESP。reconfigure 成功后删掉老世代；ESP 里的多余 UKI 由下一次
;; reconfigure 按剩余世代重建时收敛（delete-generations 顺带的
;; reinstall-bootloader 对 limine 只写一个无人读取的 /boot/grub/grub.cfg）。
(define %keep-system-generations 10)

;; 删掉系统世代 1..N-上限，使剩余世代（含当前代）恰好 %keep-system-generations
;; 个。delete-matching-generations 内部保证不删当前代。
(define (%prune-system-generations)
  ;; dry-run 下 reconfigure 未发生，代数失真，跳过（预演不演算）。
  (unless (dry-build?)
    (let* ([link (and=> (false-if-exception
                         (readlink "/var/guix/profiles/system"))
                        basename)]
           [m (and=> link (cut string-match "^system-([0-9]+)-link$" <>))]
           [number (and=> m (lambda (m)
                              (string->number (match:substring m 1))))])
      (when (and number (> number %keep-system-generations))
        (format #t "修剪系统世代，保留最新 ~a 个~%" %keep-system-generations)
        (%guix `("system" "delete-generations"
                 ,(format #f "1..~a" (- number %keep-system-generations)))
               #:sudo? #t)))))

;; blue rebuild —— 应用 Guix System 配置（需 sudo）。
;; 流程：先清编译产物 → tangle+括号检查 → system reconfigure → 修剪系统世代
;; （保 %keep-system-generations 个）→ guix locate --update。
;; dry-run：tangle+括号检查真跑，reconfigure 短路成 build --dry-run。
;; ⚠ Agent 不要自行运行此命令（需 sudo 会卡 CLI），只许 blue home 调试。
(define-command (rebuild-command arguments)
  ((invoke "rebuild")
   (category 'deployment)
   (synopsis "应用 Guix System 配置")
   (help "应用 operating-system 表。blue --dry-run rebuild 仅构建验证、不写入系统。"))
  ((command-procedure clean-artifacts-command) '())
  (apply-config "system" "%system"
                #:sudo? #t
                #:after (lambda ()
                          (%prune-system-generations)
                          (%guix '("locate" "--update")))))

;; blue home —— 应用 Guix Home 配置（不需 sudo，首选调试方式）。
(define-command (home-command arguments)
  ((invoke "home")
   (category 'deployment)
   (synopsis "应用 Guix Home 配置")
   (help "应用 home-environment 表。blue --dry-run home 仅构建验证、不写入系统。"))
  ((command-procedure clean-artifacts-command) '())
  (apply-config "home" "%home"))

;; blue init —— 新机装机：把系统配置安装到 /mnt（挂载好根分区后用）。
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

;; ---- Live ISO 辅助（build-iso-command 用） -----------------------------
;;
;; 仿 Testament blueprint.scm 的 %images / images-from-arguments，前缀为
;; 本仓库自有名 "jeans"。minimal 目前共用 desktop 的 live-installation-os
;; （config.org 只定义了 desktop 版本）；要做 minimal 得加独立 OS 块。

;; ISO 变体列表（顺序即构建顺序：先 desktop 主目标，再 minimal fallback）。
(define %images '("desktop" "minimal"))

;; 把命令参数（变体名列表）过滤成实际要构建的子集。
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

;; blue build-iso [VARIANT] ... —— 构建 Guix System Live ISO。
;; 先 tangle（让 :tangle ../tmp/live-iso.scm 的块出产物），再对每个变体
;; 调 tools/build-image.scm（跑在 guix repl 环境，见文件头）。不带参数
;; 构建全部变体。构建耗时 30+ 分钟，见 docs/iso-build.md。
(define-command (build-iso-command arguments)
  ((invoke "build-iso")
   (category 'deployment)
   (synopsis "构建 Guix System Live ISO")
   (help "[VARIANT] ...
构建 Live ISO 镜像，产物落到 dist/jeans-<variant>-<YYYYMMDD>.<arch>.iso。
不带参数则构建 %images 列出的所有变体；带参数只构建匹配 VARIANT 的。"))
  (tangle-config)
  (mkdir-p (string-append %repo-root "/dist"))
  (let ([scm (string-append %tmp-dir "/live-iso.scm")])
    (every
     (cut eq? #t <>)
     (map
      (lambda (variant)
        (let* ([iso-name (%live-iso-filename variant)]
               [iso-path (string-append %repo-root "/dist/" iso-name)])
          (format #t "\tBUILD ISO\t~a~%" iso-name)
          (%guix `("repl" "--"
                   ,(string-append %tools-dir "/build-image.scm")
                   ,iso-path ,scm "--image-type=iso9660"))))
      (images-from-arguments arguments)))))

;;; ---------- 编辑 ----------

;; 块名只允许字母/数字/连字符/下划线：block-show 的 name 拼进输出文件路径、
;; block-replace 的 name 交给 elisp 处理，特殊字符（../ 与空白）会构成
;; 路径穿越 / 匹配注入面
(define (%valid-block-name? name)
  (and (string? name) (not (string-null? name))
       (string-every (lambda (c)
                       (or (char-alphabetic? c) (char-numeric? c)
                           (memv c '(#\- #\_))))
                     name)))

;; blue block-show BLOCK —— 从 config.org 抽取名为 BLOCK 的代码块。
;; 输出写到 tmp/block-<BLOCK>.scm 并打印其路径；内容前两行是 lang 和
;; noweb/plain 标记，第三行起才是 body。
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

;; blue block-replace BLOCK BODY-FILE —— 用 BODY-FILE 替换 config.org 中
;; 的 BLOCK 块。若被替换的是 scheme 块，自动跑 tangle+括号检查验证；失败
;; 时提示用 git 还原 config.org。
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
     ;; block-replace 真实写 source/config.org（tangle 与 tmp 清理也真跑），
     ;; dry-run 承诺「不写入」——这里短路而不是半途留下产物
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

;; blue pull —— 用锁定的频道跑 guix pull。
(define-command (pull-command arguments)
  ((invoke "pull")
   (category 'guix)
   (synopsis "通过锁定频道执行 guix pull"))
  (%guix '("pull" "--allow-downgrades" "--fallback")))

;; ---- 单频道刷新辅助（blue update --channel 用） ----------------------------
;;
;; 原理：Guix 的 channels 文件原生支持「pin 混搭」——带 (commit ...) 的频道
;; 固定在该 commit（update-cached-checkout 不拉新），不带的跟随 branch 最新
;; （手册 "Specifying Channels"）。单刷新 = 生成一份临时 channels 文件：
;; 目标频道用 channel.scm 的可变定义（commit 参数非 #f 时直接 pin 到该
;; commit），其余频道换成 channel.lock 的锁定版本，再照常用 time-machine
;; describe 产出完整的新 lock。
;;
;; 临时文件由 tools/gen-partial.scm 生成：blue 的 Guile 环境缺 (guix
;; openpgp) 等模块，展开 openpgp-fingerprint 宏会报 unbound variable，
;; 必须走 guix repl 子进程（guix 的 Guile 环境自带这些模块）。
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
;; -c/--channel 选频道（需搭配 --guix）、-C/--commit 指定 pin 的 commit
;; （需搭配 -c）、--flake 需搭配 --nix，其余未知参数报 usage。
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

;; channel.lock 的提交信息按 target 区分，让 git log 直接可读：全量 bump、
;; 单频道 bump、单频道 pin（commit 取前 8 位短哈希）。
(define (%lock-commit-message target)
  (match target
    ['all "build(channel.lock): bump channels"]
    [(name . #f) (format #f "build(channel.lock): bump ~a" name)]
    [(name . commit)
     (format #f "build(channel.lock): pin ~a at ~a"
             name (substring commit 0 (min 8 (string-length commit))))]))

;; guix 侧更新：用可变频道定义跑 guix describe，结果原子写回 channel.lock。
;; target 为 'all（channel.scm 全量）、(name . #f)（单频道刷新到最新，其余
;; pin）或 (name . commit)（单频道 pin 到指定 commit，其余 pin）。
;; dry-run 下仅预演、不写 channel.lock：describe 是捕获 stdout 的管道命令，
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

;; blue update [--guix [-c NAME [-C COMMIT]]] [--nix [--flake NAME]] —— 刷新
;; channel.lock / flake.lock 并各自 git commit -S。不带参数两侧全量刷新。
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

;; 删旧的 system/home generations（system 需 sudo）。原为独立命令
;; clean-generations，现已并入 gc，仅作为内部过程保留。
(define (%clean-generations)
  (%run '("sh" "-c" "sudo guix system delete-generations > /dev/null"))
  (%run '("sh" "-c" "guix home delete-generations > /dev/null")))

;; blue clean-artifacts —— 清仓库里的编译产物（__pycache__ / *.elc / *.o 等）
;; 和 emacs 运行时缓存目录。rebuild / home 前会自动先跑这个。
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
            (format #t "移除 ~a~%" target)
            (delete-file-recursively target))
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

;; blue gc —— 一键大扫除：删旧世代 → guix gc → 删旧 EFI（均需人工触发）。
(define-command (gc-command arguments)
  ((invoke "gc")
   (category 'maintenance)
   (synopsis "删除旧世代、执行 Guix GC 并清理旧 Guix EFI 文件")
   (help "依次删除旧 system/home 世代、执行 guix gc 并删除 /boot/EFI/Guix/OLD-*.EFI。删除 system 世代与 EFI 文件需要 sudo。"))
  (%clean-generations)
  (%run '("guix" "gc"))
  ;; %run 经 popen 直 exec、无 shell 展开，OLD-*.EFI 须在 Guile 侧收集
  ;; 后逐个删除。ESP 挂载点是 /efi（limine-efi-removable-bootloader 的
  ;; targets），旧命令的 /boot/EFI/Guix 路径在这台机器上并不存在。
  (let ([stale (or (false-if-exception
                    (scandir "/efi/EFI/Guix" (cut string-prefix? "OLD-" <>)))
                   '())])
    (if (null? stale)
        (format #t "没有待清理的 OLD-*.EFI~%")
        (for-each (lambda (name)
                    (%run `("sudo" "rm" "-rf" ,(string-append "/efi/EFI/Guix/" name))))
                  stale))))

;; blue reuse —— 用 reuse 工具给仓库文件批量补 SPDX 版权/许可证头。
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

;; blue structor [TARGET] ... —— 刷新 AGENTS.md 的自动目录树。
;; 深度优先级：标记内 depth=N > ORG_STRUCTOR_DEPTH > 默认 4。
;; 环境变量：ORG_STRUCTOR_DEPTH=N 全局回退深度；ORG_STRUCTOR_DRY=1 预览。
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

;; blue nix —— 应用备用 Nix home-manager 配置（与 Guix 不互通，独立使用）。
;; 通过 nh（nix helper）封装切换，自动处理备份与构建输出；flake 路径
;; 通过位置参数传入，配置名显式指定为 Guix（flake.nix: homeConfigurations.Guix）。
(define-command (nix-command arguments)
  ((invoke "nix")
   (category 'nix)
   (synopsis "应用备用 Nix home-manager 配置"))
  (%run `("nh" "home" "switch" ,%nix-dir
          "--configuration" "Guix"
          "--backup-extension" "backup")))

;; blue nix-init —— 初始化 Nix channel 并安装 home-manager（首次用）。
(define-command (nix-init-command arguments)
  ((invoke "nix-init")
   (category 'nix)
   (synopsis "初始化 Nix channel 并安装 home-manager"))
  (%run '("nix-channel" "--update"))
  (%run '("nix-shell" "<home-manager>" "-A" "install")))

;;; ---------- 校验 ----------

;; blue secret-scan [DIR] [PATTERN] ... —— 扫描文本配置里的疑似凭据。
;; DIR 默认 dotfiles/immutable；后续裸参数作为额外正则。找到默认报错，
;; 设 GUIX_SECRET_SCAN_FAIL_ON_FIND=0 则仅警告。
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

;; blue stow [--adopt|--restow|--delete] PKG ... —— 用 GNU Stow 部署
;; dotfiles/mutable/PKG。详见命令 help 文本（含忽略机制三层说明）。
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

;; blue stow-all [--adopt|--restow|--delete] —— 对 dotfiles/mutable/ 下所有
;; 包批量操作。裸参数作为包名过滤（为空则取全部）。逐一执行，遇错即停。
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

;; blue list —— 列出本项目所有指令（覆盖框架默认的 help 风格）。
(define-command (list-command arguments)
  ((invoke "list")
   (category 'help)
   (synopsis "列出项目指令")
   (help "列出本项目可用指令及其用途。"))
  (print-command-list))

;; 命令分类表：单一清单，同时驱动 blue list 的展示与 §9 的注册。
;; 必须定义在全部命令（含上面的 list-command）之后——quasi-quote 在定义
;; 求值时刻就取各命令变量的值。
(define %command-categories
  `(("部署 (deployment)" ,rebuild-command ,home-command ,init-command ,build-iso-command)
    ("编辑 (editing)" ,block-show-command ,block-replace-command)
    ("Guix 频道 (guix)" ,pull-command ,update-command)
    ("维护 (maintenance)" ,clean-artifacts-command
     ,gc-command ,reuse-command ,structor-command)
    ("Nix 备用 (nix)" ,nix-command ,nix-init-command)
    ("Stow (stow)" ,stow-command ,stow-all-command)
    ("验证 (validation)" ,secret-scan-command)
    ("帮助 (help)" ,list-command)))

;; 按类别分组打印全部自写指令。
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

;;; ============================================================
;;; §9  入口点 —— 把上面定义的一切注册给 blue 框架
;;; ============================================================

(blueprint
 (buildables (list %config-buildable))
 (testables (list %config-check))
 (commands (concatenate (map cdr %command-categories))))
