;;; modules/50-terminal.lisp — 终端面板（VSCode Ctrl+` / Ctrl+J toggle 语义）
;;;
;;; 依赖：utils、extensions（terminal 三件套 + shell-mode）、
;;; explorer（vscode-toggle-sidebar 进 bypass 表）；
;;; 被 keybindings（C-j / M-`）、startup（vs-open-shell-panel）依赖。
;;;
;;; 面板实现为 shell-mode buffer（纯 Lisp spawn 稳定；vterm 的 C 层
;;; forkpty 在 SBCL 多线程下随机失败，详见 10-extensions 注释）。
;;; 显示 = 主窗底部切 1/3；隐藏 = 删窗不杀 buffer（shell 进程保活）。
;;; vterm 仍可经 M-x terminal 手动呼出，其 bypass 修复保留在文件尾部。

(in-package :lem-user)

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

(defun vs-open-shell-panel (buffer)
  "在主窗底部切出下 1/3 显示 buffer；返回主编辑窗（供调用方交还焦点）。
startup 与 toggle 共用管线。注意：须在侧栏开启之后调用——
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

(define-command vscode-toggle-terminal () ()
  "VSCode Ctrl+`：显示/隐藏底部终端面板（shell-mode 实现）。
隐藏只删窗不杀 buffer（shell 进程保活，重开续用同一会话）；
重开走 vs-open-shell-panel（与启动相同管线）。listener-mode 不绑
C-j，面板聚焦时按 C-j 亦可隐藏面板（vterm 无此待遇，见模块头）。"
  (let* ((buf (vs-shell-buffer))
         (win (and buf (find buf (window-list) :key #'window-buffer))))
    (cond
      (win
       (if (cdr (window-list))
           (delete-window win)
           (message "最后一个窗口，不能隐藏终端")))
      (buf (vs-open-shell-panel buf))
      (t (let ((new (vs-call :lem-shell-mode "RUN-SHELL-INTERNAL")))
           (when new (vs-open-shell-panel new)))))))

;; vterm 旁路表修复（终端聚焦时仍生效的编辑区命令，
;; VSCode commandsToSkipShell 对应物）：
;; 上游 *bypass-commands* 的消费处用 (member ... :test #'typep) 把命令符号
;; 当类型指示符，SBCL 对非类符号直接炸 unknown type specifier（潜伏 bug，
;; 终端内执行任何 bypass 命令必触发）。这里重定义 execute 方法改用 eq，
;; 原生 bypass 列表与下述追加项一并修复。
(let ((execute-sym (vs$ :lem "EXECUTE"))
      (mode-sym (vs$ :lem-terminal/terminal-mode "TERMINAL-MODE"))
      (input-sym (vs$ :lem-terminal/terminal-mode "TERMINAL-INPUT"))
      (bypass-sym (vs$ :lem-terminal/terminal-mode "*BYPASS-COMMANDS*")))
  (when (and execute-sym mode-sym input-sym bypass-sym)
    (eval
     `(sb-ext:without-package-locks
        (defmethod ,execute-sym ((mode ,mode-sym) command argument)
          (declare (ignore argument))
          (if (member command (symbol-value ',bypass-sym) :test #'eq)
              (call-next-method)
              (,input-sym)))))
    (dolist (cmd (list 'vscode-toggle-terminal
                       'vscode-toggle-sidebar
                       (vs$ :lem "FIND-FILE-RECURSIVELY")
                       (vs$ :lem "SAVE-BUFFER")
                       (vs$ :lem "SPLIT-ACTIVE-WINDOW-HORIZONTALLY")
                       (vs$ :lem/legit "LEGIT-STATUS")
                       (vs$ :lem/grep "PROJECT-GREP")))
      (when cmd
        (pushnew cmd (symbol-value bypass-sym))))))
