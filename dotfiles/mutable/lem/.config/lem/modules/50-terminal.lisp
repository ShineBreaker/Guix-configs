;;; modules/50-terminal.lisp — 终端面板（VSCode Ctrl+` / C-j toggle 语义）
;;;
;;; 依赖：utils（vs$/vs-call/vs-setglobal）、上游内置 lem-terminal /
;;; lem-shell-mode / lem-process（nightly 全内置）、explorer（vs-project-root）；
;;; 被 keybindings（全局 C-j / C-` / M-`）、startup（vs-ensure-terminal-buffer
;;; / vs-open-terminal-panel）依赖。
;;;
;;; 双通道，vs-vterm-p 运行时判定：
;;; - vterm（lem-terminal，libvterm 真终端）：完整 ANSI/256 色、winsize 同步、
;;;   TUI 程序、fish 能力查询应答（kitty ?u / XTVERSION / OSC 11 / DA1 由
;;;   libvterm 回答）——日常 kitty+fish 体验的对齐通道。shell 固定 fish，
;;;   经 SHELL 环境变量注入（上游 terminal-new 唯一的 shell 选择入口）。
;;; - shell-mode（行式 buffer）：退化通道。fish 在其哑管道下能力查询无
;;;   应答，实测 0.13s 发出查询包后阻塞、~30s 才出提示符，故只能 bash，
;;;   且需 script(1) 补控制终端（async-process 的 pty 无 ctty）。
;;; vterm 构建门槛：AppImage 打包（lem-next-bin-<日期>）在 2026-06-05 前的
;;; nightly 有 I/O 线程数据竞争（上游 #2209/#2211 修复），spawn 成功后主进程
;;; 随机 SIGSEGV fatal，按路径构建日期探测；git 源码构建（lem-next-<版本>-
;;; <hash>）默认信任。判定不通过时自动退化（见 vs-vterm-p）。
;;; 显示 = 主窗底部切 1/3；隐藏 = 删窗不杀进程（重开续用同一会话）。
;;; shell-mode 的 shell 进程退出后 buffer 残留（mode 不变），该通道重建前
;;; 清死 buffer（vterm 通道无死活探针，退出态由用户 kill-buffer 收尾）。

(in-package :lem-user)

(defparameter *vs-terminal-vterm* :auto
  "终端通道：:auto 按构建日期探测（默认） / :on 强制 vterm / :off 强制
shell-mode。:on 在 < 20260605 构建上会随机闪退，勿用。")

(defparameter *vs-terminal-shell* "/run/current-system/profile/bin/fish"
  "vterm 通道 shell。上游拼接 $SHELL -c \"cd <dir>; $SHELL\" 无转义，
路径须无空格；系统 profile 链接在 Guix 世代更新间保持稳定。")

(defun vs-lem-runtime-path ()
  "lem 可执行真实路径（sb-impl 变量；被镜像剥离时返回 nil）。"
  (ignore-errors
   (let ((sym (find-symbol "*RUNTIME-PATHNAME*" :sb-impl)))
     (and sym (boundp sym)
          (namestring (symbol-value sym))))))

(defun vs-lem-build-date ()
  "解析 AppImage 打包路径里的构建日期 yyyymmdd（…/lem-next-bin-20260531-0400/…）；
git 源码构建（…/lem-next-2.3.0-68e85e0/…）无日期位，返回 nil。"
  (let* ((exe (vs-lem-runtime-path))
         (mark "lem-next-bin-")
         (pos (and exe (search mark exe))))
    (when (and pos (>= (length exe) (+ pos (length mark) 8)))
      (let ((digits (subseq exe (+ pos (length mark)) (+ pos (length mark) 8))))
        (when (every #'digit-char-p digits)
          (parse-integer digits :junk-allowed nil))))))

(defun vs-vterm-p ()
  "是否走 vterm 通道：开关设定 + terminal 包在 core 内 + 构建安全。
AppImage 打包（lem-next-bin-<日期>）按日期门槛：< 20260605 有 I/O 线程
数据竞争（上游 #2209/#2211 修复前）；git 源码构建（lem-next-<版本>-<hash>，
如 lem-next-2.3.0-68e85e0）无日期位，默认信任（构建者对检出的 commit
负责，排查旧 commit 时可临时设 :off）。其余路径保守退化。"
  (let ((exe (vs-lem-runtime-path)))
    (and (find-package :lem-terminal/terminal)
         (find-package :lem-terminal/terminal-mode)
         (cond ((eq *vs-terminal-vterm* :on) t)
               ((eq *vs-terminal-vterm* :off) nil)
               ((null exe) nil)
               ((search "lem-next-bin-" exe)
                (let ((date (vs-lem-build-date)))
                  (and date (>= date 20260605))))
               ((search "lem-next-" exe) t)
               (t nil)))))

;; 上游 terminal-new 读 (uiop:getenv "SHELL") 选 shell（无 Lisp 覆盖点），
;; 且 lem 可能从非 fish 会话启动（$SHELL 漂移成 bash），这里无条件钉死。
(when (vs-vterm-p)
  (vs-call :sb-posix "SETENV" "SHELL" *vs-terminal-shell* 1))

;; --- vterm 通道 ---

(defun vs-vterm-buffer ()
  "活 vterm 终端 buffer（上游注册表首个 terminal 的 buffer；无则 nil）。"
  (vs-call :lem-terminal/terminal "FIND-TERMINAL-BUFFER"))

(defun vs-ensure-vterm-buffer ()
  "新建 vterm 终端 buffer。上游 make-terminal-buffer 一次完成 ffi create
（forkpty + $SHELL）与 terminal-mode 挂载，不弹窗——窗口布局交给
vs-open-terminal-panel。工作目录 = 项目根（spawn 命令原生 cd）。"
  (let ((make (vs$ :lem-terminal/terminal-mode "MAKE-TERMINAL-BUFFER"))
        (dir (or (ignore-errors (namestring (vs-project-root)))
                 (namestring (uiop:getcwd)))))
    (and make (ignore-errors (funcall make dir)))))

(defun vs-vterm-sync-size (buffer)
  "面板落位后显式同步一次 winsize（上游已挂全局 size-change 钩子，
但 split 落位与钩子触发的时序无保证，兜底一次）。"
  (let* ((bterm (vs$ :lem-terminal/terminal-mode "BUFFER-TERMINAL"))
         (rsize (vs$ :lem-terminal/terminal-mode "RESIZE-TERMINAL"))
         (win (and bterm rsize
                   (find buffer (window-list) :key #'window-buffer))))
    (when win
      (ignore-errors (funcall rsize (funcall bterm buffer) win)))))

;; --- shell-mode 退化通道 ---
;; *default-shell-command* 是上游 run-shell-internal 的 spawn 命令注入点
;; （nil 时退 $SHELL），运行时裸引用，须 vs-setglobal。script(1) 的
;; forkpty + TIOCSCTTY 补全无 ctty 的 pty，bash 才有 job control。
(vs-setglobal :lem-shell-mode "*DEFAULT-SHELL-COMMAND*"
              '("script" "-qec" "bash" "/dev/null"))

(defun vs-shell-buffer ()
  "当前会话的 shell 面板 buffer（按 run-shell-mode 判定；无则 nil）。"
  (let ((mode (vs$ :lem-shell-mode "RUN-SHELL-MODE")))
    (and mode
         (find-if (lambda (b) (eq (buffer-major-mode b) mode))
                  (buffer-list)))))

(defun vs-buffer-process (buffer)
  "buffer 对应的 shell 进程对象（上游 internal accessor；无则 nil）。"
  (let ((fn (vs$ :lem-shell-mode "BUFFER-PROCESS")))
    (and fn (ignore-errors (funcall fn buffer)))))

(defun vs-process-dead-p (process)
  (let ((alive (vs$ :lem-process "PROCESS-ALIVE-P")))
    (not (and alive process (ignore-errors (funcall alive process))))))

(defun vs-kill-dead-shell-buffers ()
  "清理 shell 进程已退出的残留 buffer（mode 不变导致复用僵死）；
kill-buffer 会走上游 on-kill-buffer hook 删进程，资源安全。"
  (let ((mode (vs$ :lem-shell-mode "RUN-SHELL-MODE")))
    (when mode
      (dolist (b (remove-if-not (lambda (b) (eq (buffer-major-mode b) mode))
                                (buffer-list)))
        (when (vs-process-dead-p (vs-buffer-process b))
          (ignore-errors (kill-buffer b)))))))

;; --- 面板管线（双通道共用） ---

(defun vs-main-window ()
  "当前有效主窗（current-window 失效时退回首个窗口；面板 split 的宿主）。"
  (if (member (current-window) (window-list))
      (current-window)
      (car (window-list))))

(defun vs-terminal-buffer ()
  "当前会话终端 buffer（通道无关判定；无则 nil）。"
  (if (vs-vterm-p)
      (vs-vterm-buffer)
      (vs-shell-buffer)))

(defun vs-ensure-terminal-buffer ()
  "取活终端 buffer；无则新建。vterm：目录=项目根（spawn 原生 cd）；
shell-mode：清死 buffer 后新建并补发 cd 项目根。返回 buffer 或 nil。"
  (if (vs-vterm-p)
      (or (vs-vterm-buffer) (vs-ensure-vterm-buffer))
      (or (vs-shell-buffer)
          (progn
            (vs-kill-dead-shell-buffers)
            (let ((run (vs$ :lem-shell-mode "RUN-SHELL-INTERNAL")))
              (let ((buf (and run (ignore-errors (funcall run)))))
                (when buf
                  (message "vterm 构建不可用（<20260605），终端退回 bash 面板")
                  (let ((send (vs$ :lem-process "PROCESS-SEND-INPUT"))
                        (proc (vs-buffer-process buf))
                        (dir (ignore-errors (vs-project-root))))
                    (when (and send proc dir)
                      (ignore-errors
                       (funcall send proc
                                (format nil "cd ~A~C" (namestring dir) #\Newline)))))
                  buf)))))))

(defun vs-open-terminal-panel (buffer)
  "在主窗底部切出下 1/3 显示 buffer；返回主编辑窗（供调用方交还
焦点）。startup 与 toggle 共用管线。注意：须在侧栏开启之后调用——
make-leftside-window 的 balance-windows 会把已 split 的窗树重新均分
（先 split 后侧栏实测比例失控）。vterm buffer 落位后补一次 winsize
同步。"
  (let* ((before (window-list))
         (root (vs-main-window))
         (total (window-height root))
         (panel (max 6 (floor total 3))))
    (split-window-vertically root :height (max 2 (- total panel)))
    (let ((new (find-if-not (lambda (w) (member w before))
                            (window-list))))
      (when new
        (setf (current-window) new)
        (switch-to-buffer buffer)
        (when (vs-vterm-p) (vs-vterm-sync-size buffer))))
    root))

(defun vs-restore-panel-geometry ()
  "恢复面板 1/3 高度。heal 的侧栏重建走 make-leftside-window →
balance-windows，会把已有的上下 split 均分（1/3 → 1/2）。不能
用 (setf window-height) 修：窗树节点的分割比例会在下次 layout 时
把数值洗回均分值。直接删窗重切——与 toggle 隐藏/重开同一条
vs-open-terminal-panel 管线，比例必然正确；healing 期 size-change
被抑制，无循环。"
  (let* ((buf (vs-terminal-buffer))
         (win (and buf (find buf (window-list) :key #'window-buffer))))
    (when (and win (cdr (window-list)))
      (delete-window win)
      (let ((main (vs-open-terminal-panel buf)))
        (when main (setf (current-window) main))))))

(pushnew 'vs-restore-panel-geometry *vs-heal-hooks*)

(define-command vscode-toggle-terminal () ()
  "VSCode Ctrl+`：显示/隐藏底部终端面板。隐藏只删窗不杀进程（重开
续用同一会话）；重开走 vs-open-terminal-panel（与启动相同管线）。"
  (let* ((buf (vs-terminal-buffer))
         (win (and buf (find buf (window-list) :key #'window-buffer))))
    (cond
      (win
       (if (cdr (window-list))
           (delete-window win)
           (message "最后一个窗口，不能隐藏终端")))
      (t (let ((b (vs-ensure-terminal-buffer)))
           (when b (vs-open-terminal-panel b)))))))

;; 终端聚焦时局部键覆盖：terminal-mode 的 undefined-key 兜底透传会拦下
;; 一切键，全局绑定在终端 buffer 内不可达，须在 mode keymap 显式落键。
;; C-j 不绑（vterm 内与 Return 同码 0x0A，保留多行输入换行语义）；
;; C-` 为 kitty 扩展序列，仅 webview 前端可达。
(let ((tkm (vs$ :lem-terminal/terminal-mode "*TERMINAL-MODE-KEYMAP*")))
  (when (and tkm (boundp tkm) (symbol-value tkm))
    (dolist (k '("M-`" "C-`"))
      (define-key (symbol-value tkm) k 'vscode-toggle-terminal))))
(vs-help-note "ui" "M-`" "终端聚焦时隐藏面板（terminal-mode 内）")
(vs-help-note "ui" "C-`" "终端聚焦时隐藏面板（terminal-mode 内，kitty 协议）")
;; shell-mode 退化通道：行式输入无换行需求，C-j / M-` 关面板
;; （与全局语义一致；上游将来若绑走这两个键，此处显式覆盖）。
(let ((km-sym (vs$ :lem-shell-mode "*RUN-SHELL-MODE-KEYMAP*")))
  (when (and km-sym (boundp km-sym) (symbol-value km-sym))
    (let ((km (symbol-value km-sym)))
      (define-key km "C-j" 'vscode-toggle-terminal)
      (define-key km "M-`" 'vscode-toggle-terminal))))
