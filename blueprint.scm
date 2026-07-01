;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;;; ============================================================
;;; blueprint.scm —— blue 任务运行器（项目主入口）
;;; ============================================================
;;;
;;; 这个文件定义了 `blue` 命令行工具在本项目里能跑的所有"指令"
;;; （sub-commands），以及把它们接进 blue 框架所需的 buildable/testable
;;; 钩子。读完本文件就能完全理解 `blue <指令>` 背后到底做了什么。
;;;
;;; 全文按"从底层到上层"的顺序分节：
;;;   §0  路径常量            —— 本文件到处引用的绝对路径集中在此
;;;   §1  执行原语            —— 跑外部命令（guix/emacs/任意程序）的统一出口
;;;   §2  文件 I/O 辅助       —— 原子写、管道读、shell 转义
;;;   §3  配置构建管线        —— config.org → config.scm → reconfigure
;;;   §4  Org 代码块编辑      —— block-show / block-replace 的 elisp 脚本
;;;   §5  密钥扫描            —— secret-scan 命令的实现
;;;   §6  目录树生成器        —— structor 命令的实现
;;;   §7  GNU Stow 包装       —— stow / stow-all 命令的实现
;;;   §8  指令清单            —— `blue list` 展示用的分类表
;;;   §9  所有命令定义        —— 每条 `blue <指令>` 的实际逻辑
;;;   §10 入口点              —— (blueprint ...) 注册一切
;;;
;;; 【关键不变量】改动前请先理解：
;;;   * `blue build` / `blue check` / `blue clean` 等是 blue 框架的【内建
;;;     命令】，不在本文件定义；本文件只是通过 <org-config>（buildable）
;;;     和 <paren-check>（testable）两个类，告诉内建命令"建什么/测什么"。
;;;   * `%run` 是所有子进程的唯一出口。`blue --dry-run` 时它默认短路（只
;;;     打印不执行）；少数必须真跑的（tangle、括号检查）用 `#:real? #t`。
;;;   * 改源 ≠ 生效：~/.config/<app>/ 指向 /gnu/store 只读副本，改完 dotfiles
;;;     要 `blue home` 才同步。本文件的命令不会自动触发那一步。

(use-modules (blue build)               ; make-build-manifest 等
             (blue states)              ; dry-build? 等运行态参数
             (blue types)               ; define-blue-class / define-blue-method
             (blue types blueprint)     ; blueprint 主入口
             (blue types buildable)     ; <buildable> 基类
             (blue types command)       ; define-command 宏
             (blue types testable)      ; <testable> 基类（接 blue check）
             (blue subprocess)          ; popen（子进程，返回退出码）
             (guix build utils)         ; mkdir-p / delete-file-recursively
             (ice-9 ftw)                ; scandir（列目录）
             (ice-9 match)              ; match / match-lambda（模式匹配）
             (ice-9 popen)              ; open-input-pipe（读管道）
             (ice-9 rdelim)             ; read-line / get-string-all
             (ice-9 regex)              ; string-match（密钥扫描用）
             (ice-9 textual-ports)      ; get-string-all（读整个文件）
             (srfi srfi-1)              ; list 工具：first / fold / filter-map
             (srfi srfi-19)             ; 日期（reuse 命令取当前年份）
             (srfi srfi-26))            ; cut（简写 lambda）

;;; ============================================================
;;; §0  路径常量
;;; ============================================================
;;; 把本文件用到的绝对路径集中在这里，方便日后整体迁移或改名。
;;; `%repo-root' 取决于运行 blue 时的工作目录（见 bootstrap.sh 的 cd）。

(define %repo-root   (getcwd))                                    ; 仓库根
(define %home-dir    (getenv "HOME"))                             ; 用户主目录
(define %config-org  (string-append %repo-root "/source/config.org")) ; 唯一 Org 源
(define %nix-dir     (string-append %repo-root "/source/nix"))    ; Nix 备用配置
(define %tmp-dir     (string-append %repo-root "/tmp"))           ; tangle 中间产物
(define %config-scm  (string-append %tmp-dir "/config.scm"))      ; tangle 产物
(define %channel-scm (string-append %repo-root "/source/channel.scm")) ; 频道定义（可变分支）
(define %channel-lock (string-append %repo-root "/source/channel.lock")) ; 频道锁（固定 commit）

;; 判断某个环境变量是否"被设置且非空"。blue --dry-run 之外的若干开关用它读。
(define (%env-set? name)
  (let ((value (getenv name)))
    (and value (not (string-null? value)))))

;;; ============================================================
;;; §1  执行原语 —— 所有"跑外部命令"的统一出口
;;; =================================================;;=========
;;;
;;; 这一组函数是本文件里【唯一】允许启动子进程的地方。统一出口带来两个
;;; 好处：(1) `blue --dry-run` 只需在这里加一层短路就能让全项目命令都进
;;; 入预演模式；(2) 命令构造方式一致，便于阅读和审计。

;; ---- %run：子进程唯一出口 -----------------------------------------------
;;
;; 设计要点（dry-run 短路 + #:real? 逃生口）：
;;   * `blue --dry-run` 会把框架的 (dry-build?) 设为 #t。此时 %run 默认
;;     【不执行】命令，只打印一行 `[预演]\t程序 参数...` 然后返回 #t。
;;     reconfigure / gc / stow 等"会改系统"的命令因此全部安全短路。
;;   * 但有两类操作即使在 dry-run 时也必须真跑：tangle（要生成 config.scm
;;     才能验证括号）和括号检查本身。这类调用显式传 `#:real? #t` 跳过短路。
;;   * 真跑时若退出码非 0，立即 error 中止——避免"静默失败后继续 reconfigure"。
(define* (%run command #:key real?)
  (match command
    ((program . args)
     (if (and (dry-build?) (not real?))
         (begin
           (format #t "\t[预演]\t~a ~{~a ~}~%" program args)
           #t)
         (let ((status (popen program args)))
           (unless (zero? status)
             (error (format #f "命令执行失败 (~a): ~s" status command)))
           #t)))))

;; ---- %guix：锁定频道的 guix 包装 ----------------------------------------
;;
;; 所有 guix 调用都必须走 `guix time-machine --channels=source/channel.lock`，
;; 否则用的频道版本和 channel.lock 不一致，构建结果不可复现。
;; `#:sudo? #t' 时在最前面加 sudo（system reconfigure 需要 root）。
(define* (%guix args #:key (channels %channel-lock) sudo?)
  (let ((command `("guix" "time-machine"
                   ,(string-append "--channels=" channels) "--"
                   ,@args)))
    (%run (if sudo? (cons "sudo" command) command))))

;; ---- %guix-command：构造（但不执行）一条锁定频道的 guix 命令 ------------
;;
;; 只返回命令列表（program . args），交给调用方决定怎么跑。%emacs-command
;; 用它把 emacs 包进 `guix shell emacs-minimal -- emacs ...` 里。
(define (%guix-command args)
  `("guix" "time-machine"
    ,(string-append "--channels=" %channel-lock) "--"
    ,@args))

;; ---- %emacs-command：用 emacs-minimal 跑 emacs --------------------------
;;
;; 为什么要 unset 五个 EMACS* 环境变量？
;;   当 blue 本身运行在用户的 emacs 里（或继承了它的环境）时，这些变量
;;   会干扰新启动的 emacs-minimal，导致它加载错误的 load-path/data。
;;   `env -u VAR` 在子进程里把这些变量清掉，保证用的是 emacs-minimal 自带环境。
(define (%emacs-command args)
  `("env"
    "-u" "EMACSLOADPATH"
    "-u" "EMACSDATA"
    "-u" "EMACSDOC"
    "-u" "EMACSPATH"
    "-u" "INSIDE_EMACS"
    ,@(%guix-command `("shell" "emacs-minimal" "--" "emacs" ,@args))))

;;; ============================================================
;;; §2  文件 I/O 辅助
;;; =================================================;;=========

;; 原子写文件：先写到 file.XXXXXX 临时文件，成功后再 rename 覆盖目标。
;; 任何中途异常（thunk 抛错、rename 失败）都清理临时文件，绝不让目标
;; 文件停留在"写一半"状态。config.org / channel.lock 等关键文件都用它。
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

;; 追加一段文本到文件末尾（用于把 %system / %home 追加到 config.scm）。
(define (%append-to-file file text)
  (let ((port (open-file file "a")))
    (display text port)
    (close-port port)))

;; 把一条 shell 命令的【标准输出整体】读成字符串。
;; 注意：command 是单个 shell 字符串（含管道/重定向），由调用方自行 quote。
;; 退出码非 0 时 error。用于 update（读 guix describe 输出）等场景。
(define (%pipe->string command)
  (let* ((pipe (open-input-pipe command))
         (content (get-string-all pipe))
         (status (close-pipe pipe)))
    (unless (zero? (status:exit-val status))
      (error (format #f "命令执行失败 (~a): ~a"
                     (status:exit-val status) command)))
    content))

;; 把一条 shell 命令的【标准输出按行】读成 list。
;; 与 %pipe->string 的区别：分行返回，便于逐行解析（密钥扫描结果用）。
;; 这里【不检查退出码】，因为密钥扫描依赖 grep 的非 0 退出码语义。
(define (%pipe->lines command)
  (let ((pipe (open-input-pipe command)))
    (let loop ((lines '()))
      (let ((line (read-line pipe)))
        (if (eof-object? line)
            (begin
              (close-pipe pipe)
              (reverse lines))
            (loop (cons line lines)))))))

;; POSIX shell 单引号转义：把任意字符串安全地包进单引号。
;; 思路：用 '\'' 切断再重开单引号，这是把 ' 嵌入单引号串的标准技巧。
;; %pipe->string / %pipe->lines 拼命令时用它避免注入。
(define (%shell-quote string)
  (string-append "'" (string-join (string-split string #\') "'\\''") "'"))

;;; ============================================================
;;; §3  配置构建管线：source/config.org → tmp/config.scm
;;; =================================================;;=========
;;;
;;; 这一段是整个项目的心脏。流水线分三步：
;;;
;;;   config.org ──tangle──▶ config.scm ──括号检查──▶ (通过) ──reconfigure──▶ 系统
;;;
;;; 其中 tangle 由 Org Mode 的 ob-tangle 完成（把 Noweb <<ref>> 拼合成完整
;;; .scm）。两个 blue 类把 tangle 和括号检查接进 blue 的内建命令：
;;;
;;;   * <org-config>（继承 <buildable>） → `blue build` 会触发 tangle
;;;   * <paren-check>（继承 <testable>） → `blue check` 会触发括号检查
;;;
;;; 所以 `blue build` 等价于 tangle。`blue check` 走的是另一条路：不 tangle，
;;; 而是直接解析 config.org 的每个 #+NAME 块 + 周边 scm 文件，逐个做括号平衡
;;; 检查（见 §4 的 %check-config-blocks）——能定位到具体出错的块名。

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

;; `blue build` 触发时，框架对每个 buildable 调 ask-build-manifest 拿到
;; "要执行的构建动作"。这里返回的动作 = 用 emacs-minimal 跑 ob-tangle。
;; 用 #:real? #t：即使在 --dry-run 下 tangle 也必须真跑，否则没法验证括号。
(define-blue-method (ask-build-manifest (this <org-config>)
                                        (inputs <list>)
                                        (output <string>))
  (let ((input (first inputs)))
    (make-build-manifest
     (string-append "编织\t" output)            ; 显示用标题
     (lambda ()                                  ; 实际执行体
       (mkdir-p (dirname output))
       (%run (%emacs-command
              `("--quick" "--batch" "-l" "org"
                "--eval" "(require 'ob-tangle)"
                "--eval" ,(format #f "(org-babel-tangle-file ~s)" input))
              #:real? #t))))))

;; 两个实例：注册到 (blueprint (buildables ...)) / (testables ...) 即可被
;; `blue build` / `blue check` 发现。
(define %config-buildable
  (org-config
   (inputs '("source/config.org"))
   (outputs '("tmp/config.scm"))))

(define %config-check
  (paren-check
   (inputs '())                                  ; 不依赖 tangle，直接解析 config.org
   (outputs '("tmp/config.scm.check"))))         ; 仅作占位，内容见下

;; ---- 括号平衡检查（手写 Scheme 词法扫描） --------------------------------
;;
;; 为什么不用 guile 自带的 read？因为 config.org 的块/tangle 出的 config.scm
;; 可能含 unquote / 各种读取器宏，read 报错时定位差。这里只做最朴素的"数括号"
;; 检查，且正确跳过字符串字面量和 ; 注释，足以抓出最常见的"括号不匹配"症状。
;;
;; 两处复用：
;;   * blue check（§4 的 %check-config-blocks）：对每个 scheme 块的 body 调
;;     count-parens，出错定位到块名。
;;   * prepare-config（本节下方，rebuild/home 用）：对完整 tangle 出的
;;     config.scm 调 check-paren-balance，作 reconfigure 前的整体兜底。

;; 数 port 里的左/右括号数量，返回 (opens . closes)。
(define (count-parens port)
  (let loop ((char (read-char port)) (opens 0) (closes 0))
    (cond
     ((eof-object? char) (cons opens closes))
     ((eq? char #\() (loop (read-char port) (+ opens 1) closes))
     ((eq? char #\)) (loop (read-char port) opens (+ closes 1)))
     ;; 双引号字符串：读到下一个未转义的 " 为止
     ((eq? char #\")
      (let skip-string ((char (read-char port)))
        (cond
         ((eof-object? char) (cons opens closes))
         ((eq? char #\") (loop (read-char port) opens closes))
         ((eq? char #\\) (read-char port) (skip-string (read-char port)))
         (else (skip-string (read-char port))))))
     ;; 分号行注释：读到行尾
     ((eq? char #\;)
      (let skip-comment ((char (read-char port)))
        (cond
         ((eof-object? char) (cons opens closes))
         ((eq? char #\newline) (loop (read-char port) opens closes))
         (else (skip-comment (read-char port))))))
     (else (loop (read-char port) opens closes)))))

;; 检查单个文件的括号平衡。返回 #t/#f，并打印 [OK]/[ERROR] 结果。
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

;; `blue check` 触发时调这个：逐块 + 周边 scm 括号检查，全过则写占位标记。
;; 不再依赖 tangle（不消费 inputs），直接解析 config.org 的命名块。
(define-blue-method (ask-build-manifest (this <paren-check>)
                                        (inputs <list>)
                                        (output <string>))
  (make-build-manifest
   (string-append "检查\t" %config-org)
   (lambda ()
     (unless (%check-config-blocks)             ; 见 §4（块感知检查）
       (error "括号平衡检查失败"))
     (call-with-output-file output
       (lambda (port)
         (format port "已检查 ~a~%" %config-org))))))
;; ---- 三步流水线（被各 reconfigure 命令复用） -----------------------------

;; 步骤 1：跑 tangle，生成 tmp/config.scm。#:real? #t 保证 dry-run 也真跑。
(define (tangle-config)
  (mkdir-p %tmp-dir)
  (%run (%emacs-command
         `("--quick" "--batch" "-l" "org"
           "--eval" "(require 'ob-tangle)"
           "--eval" ,(format #f "(org-babel-tangle-file ~s)" %config-org)))
        #:real? #t))

;; 步骤 1+2：tangle 后，把 tail-expression（通常是 %system 或 %home 变量名）
;; 追加到 config.scm 末尾，然后跑括号检查。返回最终 config.scm 路径。
(define (prepare-config tail-expression)
  (tangle-config)
  (%append-to-file %config-scm (string-append "\n" tail-expression "\n"))
  (unless (check-paren-balance %config-scm)
    (error "配置括号平衡检查失败"))
  %config-scm)

;; 步骤 3：对 subsystem（"system" 或 "home"）执行 reconfigure。
;; dry-run 时改成 `guix <subsystem> build --dry-run`（只验证不写入）。
;; 成功后清掉 tmp/ 中间产物。`after' 是成功后的回调（rebuild 用它跑 locate）。
(define* (apply-config subsystem tail-expression #:key sudo? after)
  (let ((scm (prepare-config tail-expression)))
    (if (dry-build?)
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
;;; §4  Org 代码块编辑（block-show / block-replace 的 elisp）
;;; =================================================;;=========
;;;
;;; 这两段是嵌入式 Emacs Lisp，由 %emacs-command 以 `--script` 方式跑。
;;; 作用：在不读整个 config.org（2000+ 行）的前提下，按 #+NAME 精确抽取
;;; 或替换单个代码块，方便 agent / 脚本做"块级编辑"。
;;;
;;; 它们以 Scheme 字符串常量形式存这里，运行时写到 tmp/*.el 再交给 emacs。
;;; 逻辑独立、调试周期长，所以原样保留，只在 Scheme 包装层做整理。

;; 抽取：从 file 中找名为 name 的 #+NAME 块，打印 "lang\nnoweb|plain\n<body>"。
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

;; 替换：把 file 中名为 name 的块 body 换成 body-file 的内容，输出到 out-file。
;; 打印 "lang=..." 让外层知道被替换块的语言（scheme 块要额外做括号验证）。
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

;; 枚举：一次性遍历 file，导出【所有】 #+NAME 块。blue check 用它做逐块检查，
;; 避免每个块启动一次 emacs。与 block-extract-el 共用同一套正则风格，可对照阅读。
;;
;; 输出格式（用 >>> / <<< 作记录分隔，避免与 body 内任意文本冲突）：
;;   >>>name=<n>\tlang=<l>\tnoweb=plain|noweb
;;   <body 第 1 行>
;;   ...
;;   <<<
;; 每条记录：一行 >>> 头 + body（已 string-trim 首尾换行）+ 一行 <<< 结束。
(define block-list-el
  "(let* ((file (nth 0 command-line-args-left))
         (name-re \"^#[+]NAME:[[:space:]]+\\\\([^[:space:]\n]+\\\\)\")
         (begin-re \"^#[+]begin_src[[:space:]]+\\\\([^[:space:]\n]+\\\\)\")
         (end-re \"^#[+]end_src\")
         name lang body-start has-noweb)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward name-re nil t)
        (setq name (match-string-no-properties 1))
        (forward-line 1)
        (when (re-search-forward begin-re nil t)
          (setq lang (match-string-no-properties 1))
          (forward-line 1)
          (setq body-start (point))
          (when (re-search-forward end-re nil t)
            (let ((body (buffer-substring-no-properties
                         body-start (line-beginning-position))))
              (setq has-noweb (string-match-p \"<<[^>]+>>\" body))
              (princ (format \">>>name=%s\\tlang=%s\\tnoweb=%s\\n\"
                             name (or lang \"\")
                             (if has-noweb \"noweb\" \"plain\")))
              (princ (string-trim body \"\\n\" \"\\n\"))
              (princ \"\\n<<<\\n\"))))))
    (kill-emacs 0))")

;; 把一段 elisp 写到 tmp/<name>.el，返回文件路径。block-show/block-replace 用。
(define (write-temp-elisp name body)
  (mkdir-p %tmp-dir)
  (let ((file (string-append %tmp-dir "/" name)))
    (call-with-output-file file
      (lambda (port) (display body port)))
    file))

;; 公共包装：用 emacs-minimal 跑一段已写到 tmp 的 .el 脚本，传入额外参数，
;; 返回脚本的标准输出字符串。把 block-show / block-replace 里重复的
;; "拼 shell 命令 → %pipe->string" 模式抽出来。
(define (%run-elisp-script script-file extra-args)
  (%pipe->string
   (string-join
    (map %shell-quote
         (%emacs-command
          `("--quick" "--batch" "--script" ,script-file
            ,%config-org ,@extra-args)))
    " ")))

;; 跑 block-list-el 导出 config.org 里所有命名块，解析 >>>...<<< 记录，
;; 返回 ((name lang noweb body) ...) 列表。body 已去掉首尾换行。
;; blue check 用它拿到每个块的 body 做逐块括号检查。
(define (%extract-all-blocks)
  (let* ((script (write-temp-elisp "block-list.el" block-list-el))
         (output (%run-elisp-script script '())))
    (let loop ((lines (string-split output #\newline))
               (current #f)            ; 当前记录的 (name lang noweb)
               (body-acc '())          ; body 行累积（逆序）
               (result '()))
      (cond
       ;; 输入耗尽：返回结果（末尾应有空行，current 应已是 #f）
       ((null? lines)
        (reverse result))
       ;; 记录头 >>>name=...	lang=...	noweb=...
       ((string-prefix? ">>>" (car lines))
        (let* ((header (substring (car lines) 3)) ; 去掉 ">>>"
               (fields (map (lambda (field)
                              (cons (car (string-split field #\=))
                                    (string-join
                                     (cdr (string-split field #\=)) "=")))
                            (string-split header #\tab))))
          (loop (cdr lines)
                (list (or (assoc-ref fields "name") "")
                      (or (assoc-ref fields "lang") "")
                      (or (assoc-ref fields "noweb") ""))
                '()
                result)))
       ;; 记录结束 <<<：收尾当前记录，body 行逆序拼回字符串
       ((string=? "<<<" (car lines))
        (if current
            (loop (cdr lines) #f '()
                  (cons (append current
                                (list (string-join (reverse body-acc) "\n")))
                        result))
            (loop (cdr lines) #f '() result)))
       ;; body 行：累积（仅在记录内才有意义；记录外的行丢弃）
       (else
        (loop (cdr lines) current
              (if current (cons (car lines) body-acc) body-acc)
              result))))))

;; ---- 逐块 + 周边 scm 括号检查（blue check 的核心） -----------------------
;;
;; 这三个函数复用 §3 的 count-parens / check-paren-balance 和上面的
;; %extract-all-blocks，实现"逐块定位"的括号检查。blue check 不再 tangle，
;; 而是解析 config.org 的每个命名块单独检查——出错时能报具体块名。

;; 周边 scm 文件：与 config.org 同级的独立 Scheme 源，逐个整体检查。
(define %peripheral-scm-files
  (list (string-append %repo-root "/source/channel.scm")
        (string-append %repo-root "/source/information.scm")
        (string-append %repo-root "/source/manifest.scm")))

;; 检查单个块：(name lang noweb body) → #t/#f。
;; 只检查 lang=scheme 的块（fish/bash/js 是嵌在 scheme 字符串里的内容，跳过）。
;; main 块也检查——<<ref>> 占位本身括号平衡，能抓 main 自身的括号错。
(define (%check-block-parens block)
  (match block
    ((name lang noweb body)
     (if (string=? lang "scheme")
         (call-with-input-string body
                                 (lambda (port)
                                   (match (count-parens port)
                                     ((opens . closes)
                                      (cond
                                       ((= opens closes)
                                        (format #t "[OK] 块 ~a: ~a 对~%" name opens)
                                        #t)
                                       ((> opens closes)
                                        (format (current-error-port)
                                                "[ERROR] 块 ~a: 多余 ~a 个左括号 (open=~a close=~a)~%"
                                                name (- opens closes) opens closes)
                                        #f)
                                       (else
                                        (format (current-error-port)
                                                "[ERROR] 块 ~a: 多余 ~a 个右括号 (open=~a close=~a)~%"
                                                name (- closes opens) opens closes)
                                        #f))))))
         (begin
           (format #t "[SKIP] 块 ~a (~a)~%" name lang)
           #t)))))

;; 逐块检查 config.org + 整体检查周边 scm 文件。全部通过返回 #t，任一失败 #f。
;; 失败不立即中止——继续跑完，让用户一次看到所有错误。
(define (%check-config-blocks)
  (let* ((blocks (%extract-all-blocks))
         (scheme-count (length (filter (lambda (b) (string=? (cadr b) "scheme"))
                                       blocks)))
         (block-results (map %check-block-parens blocks))
         (scm-results
          (map (lambda (file)
                 (if (file-exists? file)
                     (check-paren-balance file)
                     (begin
                       (format (current-error-port) "[ERROR] 文件不存在: ~a~%" file)
                       #f)))
               %peripheral-scm-files)))
    (let ((all-ok? (every identity (append block-results scm-results))))
      (if all-ok?
          (format #t "[OK] 全部通过: ~a 个 scheme 块 + ~a 个周边文件~%"
                  scheme-count (length %peripheral-scm-files))
          (format (current-error-port) "[FAIL] 括号检查未通过~%"))
      all-ok?)))

;;; ============================================================
;;; §5  密钥扫描（secret-scan 命令）
;;; =================================================;;=========
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

;; 拼 grep 的 --include / --exclude-dir 选项串。flags 是 grep 前置参数。
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

;; 统计 dir 下参与扫描的文件数（仅用于扫描结束后的提示信息）。
(define (%secret-count-files dir)
  (let ((lines
         (%pipe->lines
          (string-append (%secret-grep-options "grep -rIl")
                         " -e '.' " (%shell-quote dir)
                         " 2>/dev/null | wc -l"))))
    (if (null? lines)
        0
        (or (string->number (string-trim-both (first lines))) 0))))

;; 扫描 dir。fail?=真 时发现密钥就 error；extra-patterns 是用户额外传入的正则。
;; 返回 #t（无命中或仅警告）/ 抛错（fail? 且有命中）。
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
                   ;; 只报小于 1MB 的文件，避免误报二进制/大文件
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
;;; §6  目录树生成器（structor 命令）
;;; =================================================;;=========
;;;
;;; 仓库里每个 AGENTS.md 都有一个被标记圈起的"## 目录结构"章节，内容由
;;; 本节代码自动生成（树形 ASCII 图）。新增/移动文件后跑 `blue structor`
;;; 刷新所有 AGENTS.md 的目录树。详见仓库根 AGENTS.md 的同名章节。
;;;
;;; 标记格式（独立于运行器）：
;;;   <!-- structor:begin -->
;;;   ... 自动生成的树 ...
;;;   <!-- /structor -->
;;;
;;; 跳过规则与 dotfile-services 的 excluded 列表对齐（.git / .github 等）。

(define %structor-marker-start "<!-- structor:begin -->")
(define %structor-marker-end "<!-- /structor -->")
(define %structor-skip-names
  '(".git" ".github" ".agents" "node_modules" ".blue-store"))

;; 枚举仓库内所有需要维护目录树的 AGENTS.md/README.md（返回相对路径）。
;; 排除 .git / disable / tmp / .blue-store / .agents 下的文件。
(define (%structor-targets)
  (let ((root %repo-root))
    (filter-map
     (lambda (path)
       (and (file-exists? path)
            (not (string-contains path "/.git/"))
            (not (string-contains path "/disable/"))
            (not (string-contains path "/tmp/"))
            (not (string-contains path "/.blue-store/"))
            (not (string-contains path "/.agents/"))
            (substring path (string-length root))))
     (find-files root "(^|/)(AGENTS|README)\\.md$"))))

;; 某个目录条目是否应被 structor 忽略（. / .. / 元目录 / vim 交换文件 / AGENTS.md 自身）。
(define (%structor-skip? name)
  (or (member name '("." ".." "AGENTS.md"))
      (member name %structor-skip-names)
      (string-suffix? ".swp" name)))

;; 列出 dir 的直接子条目，目录在前文件在后，各自字母序。返回 ((is-dir? . name) ...)。
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

;; 递归渲染 dir 的树形行列表。max-depth 限制深度；depth/prefix 是递归状态。
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

;; 渲染 dir 的整棵树，顶部加一行根目录名。
(define (%structor-tree dir depth)
  (cons (string-append (basename dir) "/")
        (%structor-render dir depth 0 "")))

;; 在 AGENTS.md 的正文 content 里，用 replacement 替换 structor 标记之间的
;; 内容。返回新内容（若没找到标记则返回 #f 表示无需改动）。
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
        ;; 进入标记：把整段替换内容塞进输出，状态切到 in-block
        ((and (eq? state 'normal)
              (string=? (string-trim-both line) %structor-marker-start))
         (loop rest (append (reverse replacement) out) 'in-block #t))
        ;; 离开标记：状态切回 normal（标记行本身被丢弃）
        ((and (eq? state 'in-block)
              (string=? (string-trim-both line) %structor-marker-end))
         (loop rest out 'normal changed?))
        ;; normal 态：原样保留
        ((eq? state 'normal)
         (loop rest (cons line out) state changed?))
        ;; in-block 态：丢弃原标记区内容
        (else
         (loop rest out state changed?)))))))

;; 对每个 target AGENTS.md 渲染并写回目录树。dry?=#t 时只打印不写。
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
;;; §7  GNU Stow 包装（stow / stow-all 命令）
;;; =================================================;;=========
;;;
;;; stow/ 目录用 GNU Stow 直接建软链接到仓库源（改源即生效，无需 blue home），
;;; 与 dotfiles/enable/（Guix Home stow，只读 store 副本）互补。适合频繁手改
;;; 且需 git 备份的配置（emacs / pi / hermes）。

(define %stow-dir (string-append %repo-root "/stow"))

;; stow/ 下被视为元目录、不当作包的直接子目录。
(define %stow-meta-names
  '("." ".." ".git" ".github" ".agents" "node_modules" ".blue-store"))

;; 把 --adopt/--restow/--delete 模式名翻译成 stow 命令行 flag。
(define (%stow-flag mode)
  (case (string->symbol mode)
    ((adopt) "--adopt")
    ((restow) "--restow")
    ((delete) "--delete")
    (else "")))

;; 模式名翻译成中文动词（日志显示用）。
(define (%stow-verb mode)
  (case (string->symbol mode)
    ((adopt) "收养")
    ((restow) "重建")
    ((delete) "撤销")
    (else "部署")))

;; 对单个包执行 stow。--no-folding 与 stow/.stowrc 双重保险：目标保持真实
;; 目录，只对单个文件建软链，避免应用运行时产物经整目录软链污染源。
(define (%stow-package pkg mode home)
  (let ((pkg-dir (string-append %stow-dir "/" pkg)))
    (unless (file-exists? pkg-dir)
      (error (format #f "stow 包不存在: ~a" pkg-dir)))
    (format #t "[~a] ~a -> ~a~%" (%stow-verb mode) pkg home)
    (let ((flag (%stow-flag mode)))
      (%run `("stow"
              "--no-folding"
              ,(string-append "--dir=" %stow-dir)
              ,(string-append "--target=" home)
              ,@(if (string=? flag "") '() (list flag))
              ,pkg)))))

;; 枚举 stow/ 下所有直接子目录（包不能嵌套），过滤元目录，按字母序返回。
(define (%stow-list-packages)
  (sort
   (filter-map
    (lambda (name)
      (and (not (member name %stow-meta-names))
           (file-is-directory? (string-append %stow-dir "/" name))
           name))
    (or (scandir %stow-dir) '()))
   string<?))

;; 解析 stow/stow-all 的命令行参数。
;; 返回 alist：((mode . "adopt"|"restow"|"delete"|"stow") (packages . (...)))
;; 裸参数视为包名；--adopt/--restow/--delete 设置模式。
(define (parse-stow-args args)
  (let loop ((rest args) (mode "stow") (packages '()))
    (match rest
      (()
       `((mode . ,mode) (packages . ,packages)))
      (("--adopt" . rest)
       (loop rest "adopt" packages))
      (("--restow" . rest)
       (loop rest "restow" packages))
      (("--delete" . rest)
       (loop rest "delete" packages))
      ((pkg . rest)
       (loop rest mode (append packages (list pkg)))))))

;;; ============================================================
;;; §8  所有命令定义
;;; =================================================;;=========
;;;
;;; 每条命令用 define-command 定义，统一形态：
;;;   (define-command (xxx-command arguments)
;;;     ((invoke "xxx")           ; 命令名（blue xxx）
;;;      (category 'cat)          ; 分类（影响 blue list 归组）
;;;      (synopsis "...")         ; 一句话（blue list 用）
;;;      (help "..."))            ; 多行帮助（blue help xxx 用）
;;;     <body>)
;;;
;;; `arguments' 是命令行剩余参数列表。`(command-procedure foo-command)' 取
;;; 另一条命令的过程，用于复用（如 rebuild 先跑 clean-artifacts）。
;;; 命令顺序按类别聚簇，方便对照 §8 的清单。

;;; ---------- 帮助 ----------

;; blue list —— 列出本项目所有指令（覆盖框架默认的 help 风格）。
(define-command (list-command arguments)
  ((invoke "list")
   (category 'help)
   (synopsis "列出项目指令")
   (help "列出本项目可用指令及其用途。"))
  (print-command-list))

;;; ---------- 部署 ----------

;; blue rebuild —— 应用 Guix System 配置（需 sudo）。
;; 流程：先清编译产物 → tangle+括号检查 → system reconfigure → guix locate --update。
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
                #:after (lambda () (%guix '("locate" "--update")))))

;; blue home —— 应用 Guix Home 配置（不需 sudo，首选调试方式）。
;; 流程：先清编译产物 → tangle+括号检查 → home reconfigure。
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
  (let ((scm (prepare-config "%system")))
    (format #t "正在将系统安装到 /mnt~%")
    (%guix `("system" "init" ,scm "/mnt") #:sudo? #t)
    (false-if-exception (delete-file-recursively %tmp-dir))))

;;; ---------- 编辑 ----------

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
    ((name)
     (let* ((script (write-temp-elisp "block-show.el" block-extract-el))
            (out-file (string-append %tmp-dir "/block-" name ".scm"))
            (content (%run-elisp-script script (list name))))
       (call-with-output-file out-file
         (lambda (port) (display content port)))
       (format #t "~a~%" out-file)))
    (_ (error "usage: blue block-show BLOCK"))))

;; blue block-replace BLOCK BODY-FILE —— 用 BODY-FILE 替换 config.org 中的
;; BLOCK 块。若被替换的是 scheme 块，自动跑 tangle+括号检查验证；失败时
;; 提示用 git 还原 config.org。
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
            (output (%run-elisp-script script
                                       (list name body-file out-org)))
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

;;; ---------- Guix 频道 ----------

;; blue pull —— 用锁定的频道跑 guix pull（更新本机 guix 到 channel.lock 版本）。
(define-command (pull-command arguments)
  ((invoke "pull")
   (category 'guix)
   (synopsis "通过锁定频道执行 guix pull"))
  (%guix '("pull" "--allow-downgrades" "--fallback")))

;; blue update —— 用 channel.scm（可变分支）跑 guix describe，把结果写回
;; channel.lock（固定 commit），然后 git commit -S 锁定。
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

;;; ---------- 维护 ----------

;; blue clean-generations —— 删旧的 system/home generations（system 需 sudo）。
(define-command (clean-generations-command arguments)
  ((invoke "clean-generations")
   (category 'maintenance)
   (synopsis "删除旧的 Guix System/Home 世代")
   (help "删除旧 system 和 home 世代。删除 system 世代可能需要 sudo 权限。"))
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
     ((target type)
      (if (eq? type 'directory)
          (when (file-exists? target)
            (format #t "移除 ~a~%" target)
            (delete-file-recursively target))
          (%run `("find" ,%repo-root "-type" "f" "-name" ,target
                  "-not" "-path" "*/.git/*"
                  "-print" "-delete")))))
   `(("__pycache__" directory)
     ("*.elc" file)
     ("*.o" file)
     ("*.a" file)
     ("*.so" file)
     ("org-roam.db" file)
     (,(string-append %repo-root "/stow/emacs/.config/emacs/etc") directory)
     (,(string-append %repo-root "/stow/emacs/.config/emacs/var") directory))))

;; blue gc —— 一键大扫除：先 clean-generations，再 guix gc，最后删旧 EFI 文件。
(define-command (gc-command arguments)
  ((invoke "gc")
   (category 'maintenance)
   (synopsis "执行 Guix GC 并清理旧 Guix EFI 文件")
   (help "依次执行 clean-generations、guix gc 并删除 /boot/EFI/Guix/OLD-*.EFI。"))
  ((command-procedure clean-generations-command) '())
  (%run '("guix" "gc"))
  (%run '("sudo" "rm" "-rf" "/boot/EFI/Guix/OLD-*.EFI")))

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
;; 不带参数刷所有目标；带参数只刷指定 AGENTS.md。
;; 环境变量：ORG_STRUCTOR_DEPTH=N 控制深度（默认 4）；ORG_STRUCTOR_DRY=1 预览。
(define-command (structor-command arguments)
  ((invoke "structor")
   (category 'maintenance)
   (synopsis "刷新 AGENTS.md 中自动生成的目录树章节")
   (help "[TARGET] ...
刷新所有 structor 目标，或仅刷新指定的 AGENTS.md。
支持 ORG_STRUCTOR_DEPTH=N 和 ORG_STRUCTOR_DRY=1 环境变量。"))
  (let* ((depth (or (and=> (getenv "ORG_STRUCTOR_DEPTH") string->number) 4))
         (targets (if (null? arguments) (%structor-targets) arguments))
         (dry? (%env-set? "ORG_STRUCTOR_DRY")))
    (run-structor targets #:depth depth #:dry? dry?)))

;;; ---------- Nix 备用 ----------

;; blue nix —— 应用备用 Nix home-manager 配置（与 Guix 不互通，独立使用）。
(define-command (nix-command arguments)
  ((invoke "nix")
   (category 'nix)
   (synopsis "应用备用 Nix home-manager 配置"))
  (%run `(,(string-append %home-dir "/.nix-profile/bin/home-manager")
          "switch" "-b" "backup"
          "--flake" ,(string-append %nix-dir "/#Guix")
          "--extra-experimental-features" "nix-command"
          "--extra-experimental-features" "flakes")))

;; blue nix-init —— 初始化 Nix channel 并安装 home-manager（首次用）。
(define-command (nix-init-command arguments)
  ((invoke "nix-init")
   (category 'nix)
   (synopsis "初始化 Nix channel 并安装 home-manager"))
  (%run '("nix-channel" "--update"))
  (%run '("nix-shell" "<home-manager>" "-A" "install")))

;; blue nix-update —— 更新 Nix channel 和 flake.lock，并 git commit -S。
(define-command (nix-update-command arguments)
  ((invoke "nix-update")
   (category 'nix)
   (synopsis "更新 Nix channel 和 flake"))
  (%run '("nix-channel" "--update"))
  (%run `("nix" "flake" "update" "--flake" ,%nix-dir))
  (%run `("git" "commit" "-S" "-m"
          "UPDATE: (flake.lock) bump version."
          ,(string-append %nix-dir "/flake.lock"))))

;;; ---------- 校验 ----------

;; blue secret-scan [DIR] [PATTERN] ... —— 扫描文本配置里的疑似凭据。
;; DIR 默认 dotfiles/enable；后续裸参数作为额外正则。找到默认报错，
;; 设 GUIX_SECRET_SCAN_FAIL_ON_FIND=0 则仅警告。
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

;;; ---------- Stow ----------

;; blue stow [--adopt|--restow|--delete] PKG ... —— 用 GNU Stow 部署 stow/PKG。
;; 详见命令 help 文本（含忽略机制三层说明）。
(define-command (stow-command arguments)
  ((invoke "stow")
   (category 'stow)
   (synopsis "用 GNU Stow 管理频繁变动的 dotfiles")
   (help "[--adopt|--restow|--delete] PKG ...
GNU Stow 直链部署 stow/PKG/ 到 $HOME。改源即生效（无需 blue home）。

模式:
  blue stow PKG ...          从源部署（创建软链接）
  blue stow --adopt PKG ...  把 $HOME 下已有文件移动到源目录，再建软链接
  blue stow --restow PKG ... 强制重建所有软链接（先删除再重建）
  blue stow --delete PKG ... 删除软链接（$HOME 下变回实际文件）

--no-folding: 目标目录保持为真实目录，stow 只对单个文件建软链（由 stow/.stowrc
+ 命令行双重保证）。应用运行时产物（logs/、state.db、sessions/ 等）落到真实目
录而非源。批量操作所有包见 `blue stow-all`。

忽略机制（三层，优先级递减）:
  stow/.stowrc                全局（含 --no-folding）
  stow/<PKG>/.stow-local-ignore  每包 Perl 正则，逐行，# 注释允许
  --ignore=REGEX              命令行一次性

源目录布局: stow/PKG/.local/share/hermes/ -> ~/.local/share/hermes/
改后用 git commit 备份。配合 dotfiles/ 的 Guix stow（仅读源）使用。"))
  (let* ((parsed (parse-stow-args arguments))
         (mode (assq-ref parsed 'mode))
         (packages (assq-ref parsed 'packages))
         (home (or (getenv "HOME") "/root")))
    (when (null? packages)
      (error "stow: 至少需要一个包名（批量操作请用 blue stow-all）"))
    (unless (file-exists? %stow-dir)
      (error (format #f "stow 源目录不存在: ~a" %stow-dir)))
    (for-each (cut %stow-package <> mode home) packages)))

;; blue stow-all [--adopt|--restow|--delete] —— 对 stow/ 下所有包批量操作。
;; 裸参数作为包名过滤（为空则取全部）。逐一执行，遇错即停。
(define-command (stow-all-command arguments)
  ((invoke "stow-all")
   (category 'stow)
   (synopsis "对 stow/ 下所有包批量执行 stow 操作")
   (help "[--adopt|--restow|--delete]
枚举 stow/ 下所有直接子目录作为包，逐个执行（包不能嵌套）。默认为部署。

  blue stow-all              部署所有包
  blue stow-all --restow     重建所有软链接（最常用）
  blue stow-all --delete     撤销所有软链接（$HOME 下变回实际文件）
  blue stow-all --adopt      把 $HOME 下已有文件收养进各包源

逐一执行，遇错即停（与 blue stow 一致）。语义同 blue stow，见其帮助。"))
  (let* ((parsed (parse-stow-args arguments))
         (mode (assq-ref parsed 'mode))
         ;; --restow 等模式开关之外的裸参数视为包名过滤；为空则取全部。
         (only (assq-ref parsed 'packages))
         (home (or (getenv "HOME") "/root")))
    (unless (file-exists? %stow-dir)
      (error (format #f "stow 源目录不存在: ~a" %stow-dir)))
    (let ((packages
           (if (null? only)
               (%stow-list-packages)
               (filter (cut member <> only) (%stow-list-packages)))))
      (when (null? packages)
        (error "stow-all: stow/ 下无可用包（或指定的包不存在）"))
      (format #t "stow-all: 共 ~a 个包，模式=~a~%" (length packages) mode)
      (for-each (cut %stow-package <> mode home) packages))))

;;; ============================================================
;;; §9 入口点 —— 把上面定义的一切注册给 blue 框架
;;; =================================================;;=========
;;;
;;; buildables / testables 接进 `blue build` / `blue check`；
;;; commands 是 `blue <指令>` 能调到的全部自写命令（顺序仅影响源码可读性）。

(blueprint
 (buildables (list %config-buildable))
 (testables (list %config-check))
 (commands
  (list rebuild-command
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
        stow-command
        stow-all-command
        structor-command)))
