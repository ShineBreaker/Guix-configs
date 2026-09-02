;;; modules/50-terminal.lisp — 终端面板（VSCode Ctrl+` / Ctrl+J toggle 语义）
;;;
;;; 依赖：utils、上游内置 lem-shell-mode/lem-process（nightly 全内置）、
;;; explorer（vs-project-root 与 vscode-toggle-sidebar）；被 keybindings
;;; （C-j / M-`）、startup（vs-ensure-terminal-buffer / vs-open-terminal-panel）
;;; 依赖。
;;;
;;; 面板实现为 shell-mode buffer。20260531 构建 vterm 通道（lem-terminal C
;;; 层）spawn 必现失败：strace 实证 terminal_new 从未 fork/exec shell，且
;;; 存活期间进程吃 SIGSEGV（→ GC 挂起死线程 ESRCH → fatal 闪退签名），
;;; 配置层不可修，弃用。shell-mode 的 async-process fork/exec 稳定，但其
;;; pty 无控制终端（O_NOCTTY）——经 script(1) -qec 包装（forkpty +
;;; TIOCSCTTY 标准流程）补全；shell 选 bash，理由见注入点注释。
;;; 显示 = 主窗底部切 1/3；隐藏 = 删窗不杀进程（重开续用同一会话）。
;;; shell 进程退出后 buffer 残留（mode 不变），重建前须清死 buffer。

(in-package :lem-user)

;; 面板默认 bash 而非 fish：async-process 的 pty 无应答终端，fish 4.x
;; 启动即发一串能力查询（kitty keyboard ?u / XTVERSION / OSC 11 / DCS
;; +q / DA1）并等超时，实测 ~30s 后才出提示符；bash 无查询依赖，提示符
;; 立现（pty 实测 0.01s）。script(1) 给子进程完整 pty + ctty——async-
;; process 的 pty 无控制终端（O_NOCTTY），fish/bash 直接 spawn 会被 fish
;; 拒启、bash 亦缺 job control。*default-shell-command* 是上游
;; run-shell-internal 的 spawn 命令注入点（nil 时退 $SHELL），运行时
;; 裸引用，须 vs-setglobal。
(vs-setglobal :lem-shell-mode "*DEFAULT-SHELL-COMMAND*"
              '("script" "-qec" "bash" "/dev/null"))

(defun vs-main-window ()
  "当前有效主窗（current-window 失效时退回首个窗口；面板 split 的宿主）。"
  (if (member (current-window) (window-list))
      (current-window)
      (car (window-list))))

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

(defun vs-ensure-terminal-buffer ()
  "取活 shell buffer；无则清死 buffer 后新建一个（工作目录 = lem 进程
cwd，spawn 后补一句 cd 到项目根）。返回 buffer 或 nil（依赖缺失）。"
  (or (vs-shell-buffer)
      (progn
        (vs-kill-dead-shell-buffers)
        (let ((run (vs$ :lem-shell-mode "RUN-SHELL-INTERNAL")))
          (let ((buf (and run (ignore-errors (funcall run)))))
            (when buf
              (let ((send (vs$ :lem-process "PROCESS-SEND-INPUT"))
                    (proc (vs-buffer-process buf))
                    (dir (ignore-errors (vs-project-root))))
                (when (and send proc dir)
                  (ignore-errors
                   (funcall send proc
                            (format nil "cd ~A~C" (namestring dir) #\Newline)))))
              buf))))))

(defun vs-open-terminal-panel (buffer)
  "在主窗底部切出下 1/3 显示 buffer；返回主编辑窗（供调用方交还
焦点）。startup 与 toggle 共用管线。注意：须在侧栏开启之后调用——
make-leftside-window 的 balance-windows 会把已 split 的窗树重新均分
（先 split 后侧栏实测比例失控）。"
  (let* ((before (window-list))
         (root (vs-main-window))
         (total (window-height root))
         (panel (max 6 (floor total 3))))
    (split-window-vertically root :height (max 2 (- total panel)))
    (let ((new (find-if-not (lambda (w) (member w before))
                            (window-list))))
      (when new
        (setf (current-window) new)
        (switch-to-buffer buffer)))
    root))

(defun vs-restore-panel-geometry ()
  "恢复面板 1/3 高度。heal 的侧栏重建走 make-leftside-window →
balance-windows，会把已有的上下 split 均分（1/3 → 1/2）。注意不能
用 (setf window-height) 修：它只写叶子窗对象，窗树节点的分割比例
会在下次 layout 时把数值洗回均分值（SDL2 实测，trace 为证）。这里
直接删窗重切——与 toggle 隐藏/重开同一条 vs-open-terminal-panel
管线，比例必然正确；healing 期 size-change 被抑制，无循环。"
  (let* ((buf (vs-shell-buffer))
         (win (and buf (find buf (window-list) :key #'window-buffer))))
    (when (and win (cdr (window-list)))
      (delete-window win)
      (let ((main (vs-open-terminal-panel buf)))
        (when main (setf (current-window) main))))))

(pushnew 'vs-restore-panel-geometry *vs-heal-hooks*)

(define-command vscode-toggle-terminal () ()
  "VSCode Ctrl+`：显示/隐藏底部终端面板（shell-mode 实现）。
隐藏只删窗不杀进程（重开续用同一会话）；重开走 vs-open-terminal-panel
（与启动相同管线）。shell 聚焦时 C-j / M-` 亦可隐藏面板（见尾部键位）。"
  (let* ((buf (vs-shell-buffer))
         (win (and buf (find buf (window-list) :key #'window-buffer))))
    (cond
      (win
       (if (cdr (window-list))
           (delete-window win)
           (message "最后一个窗口，不能隐藏终端")))
      (t (let ((b (vs-ensure-terminal-buffer)))
           (when b (vs-open-terminal-panel b)))))))

;; shell 面板聚焦时 C-j / M-` 关面板（与全局语义一致；listener 系 keymap
;; 若上游将来绑走这两个键，此处显式覆盖）。
(let ((km-sym (vs$ :lem-shell-mode "*RUN-SHELL-MODE-KEYMAP*")))
  (when (and km-sym (boundp km-sym) (symbol-value km-sym))
    (let ((km (symbol-value km-sym)))
      (define-key km "C-j" 'vscode-toggle-terminal)
      (define-key km "M-`" 'vscode-toggle-terminal))))
