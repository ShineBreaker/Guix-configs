;;; modules/50-terminal.lisp — 终端面板（VSCode Ctrl+` / Ctrl+J toggle 语义）
;;;
;;; 依赖：utils、上游内置 lem-terminal（nightly 镜像扩展全内置，无需补载）、
;;; explorer（vs-project-root 与 vscode-toggle-sidebar 进 bypass 表）；被
;;; keybindings（C-j / M-`）、startup（vs-ensure-terminal-buffer /
;;; vs-open-terminal-panel）依赖。
;;;
;;; 面板实现为 vterm（lem terminal 扩展：libvterm + forkpty 全语义终端）。
;;; 曾用 shell-mode（lem-process/async-process），2026-08-30 弃用：
;;; async-process 的 C 层开 pty 从不设控制终端（open 用 O_NOCTTY 且子进程
;;; setsid 后无 TIOCSCTTY），fish 4.7.1 检测无 ctty 直接 exit 1（bash 5.2
;;; 容忍无 ctty），面板遂成「有窗无 shell」空壳；vterm 的 forkpty 标准流程
;;; 实测 fish 正常。当年弃 vterm 的理由（C 层 forkpty 在 SBCL 多线程下随机
;;; 失败）在新内核/新构建下未复现。
;;; 显示 = 主窗底部切 1/3；隐藏 = 删窗不杀 buffer（终端进程保活）。
;;; vterm 终端退出后 *terminals* 表移除但 buffer 残留（mode 不变），
;;; 重建前须清死 buffer，否则 find-terminal-buffer 永远 nil 而死 buffer
;;; 反复复用。

(in-package :lem-user)

(defun vs-main-window ()
  "当前有效主窗（current-window 失效时退回首个窗口；面板 split 的宿主）。"
  (if (member (current-window) (window-list))
      (current-window)
      (car (window-list))))

(defun vs-terminal-buffer ()
  "当前会话的 vterm 面板 buffer（上游 find-terminal-buffer 只认活终端；
无则 nil）。"
  (let ((fn (vs$ :lem-terminal/terminal "FIND-TERMINAL-BUFFER")))
    (and fn (funcall fn))))

(defun vs-kill-dead-terminal-buffers ()
  "清理残留的死 vterm buffer（终端退出后 mode 仍是 terminal-mode）。
kill-buffer 会走上游 on-kill-buffer → terminal:destroy，资源安全。"
  (let ((mode (vs$ :lem-terminal/terminal-mode "TERMINAL-MODE")))
    (when mode
      (dolist (b (remove-if-not (lambda (b) (eq (buffer-major-mode b) mode))
                                (buffer-list)))
        (ignore-errors (kill-buffer b))))))

(defun vs-ensure-terminal-buffer ()
  "取活终端 buffer；无则清死 buffer 后新建一个（工作目录 = 项目根，
退回 ~）。返回 buffer 或 nil（依赖缺失）。"
  (or (vs-terminal-buffer)
      (let ((make (vs$ :lem-terminal/terminal-mode "MAKE-TERMINAL-BUFFER")))
        (when make
          (vs-kill-dead-terminal-buffers)
          (let ((dir (or (ignore-errors (vs-project-root))
                         (user-homedir-pathname))))
            (funcall make (namestring dir)))))))

(defun vs-resize-terminal-in (buffer window)
  "按 window 实际尺寸同步 vterm（上游 create 固定 80x24，不 resize
会在 1/3 高的面板里只占一角）。"
  (let ((bt (vs$ :lem-terminal/terminal-mode "BUFFER-TERMINAL"))
        (rt (vs$ :lem-terminal/terminal-mode "RESIZE-TERMINAL")))
    (let ((terminal (and bt (funcall bt buffer))))
      (when (and terminal rt)
        (funcall rt terminal window)))))

(defun vs-open-terminal-panel (buffer)
  "在主窗底部切出下 1/3 显示 vterm buffer；返回主编辑窗（供调用方交还
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
        (switch-to-buffer buffer)
        (vs-resize-terminal-in buffer new)))
    root))

(defun vs-restore-panel-geometry ()
  "恢复面板 1/3 高度。heal 的侧栏重建走 make-leftside-window →
balance-windows，会把已有的上下 split 均分（1/3 → 1/2）。注意不能
用 (setf window-height) 修：它只写叶子窗对象，窗树节点的分割比例
会在下次 layout 时把数值洗回均分值（SDL2 实测，trace 为证）。这里
直接删窗重切——与 toggle 隐藏/重开同一条 vs-open-terminal-panel
管线，比例必然正确；healing 期 size-change 被抑制，无循环。"
  (let* ((buf (vs-terminal-buffer))
         (win (and buf (find buf (window-list) :key #'window-buffer))))
    (when (and win (cdr (window-list)))
      (delete-window win)
      (let ((main (vs-open-terminal-panel buf)))
        ;; resplit 会把焦点带进面板，交还主编辑区（与启动语义一致）
        (when main (setf (current-window) main))))))

(pushnew 'vs-restore-panel-geometry *vs-heal-hooks*)

(define-command vscode-toggle-terminal () ()
  "VSCode Ctrl+`：显示/隐藏底部终端面板（vterm 实现）。
隐藏只删窗不杀 buffer（终端进程保活，重开续用同一会话）；重开走
vs-open-terminal-panel（与启动相同管线）。终端聚焦时 M-` 亦可隐藏
面板（terminal-mode-keymap 显式绑定；C-j 见 70-keybindings 注释）。"
  (let* ((buf (vs-terminal-buffer))
         (win (and buf (find buf (window-list) :key #'window-buffer))))
    (cond
      (win
       (if (cdr (window-list))
           (delete-window win)
           (message "最后一个窗口，不能隐藏终端")))
      (t (let ((b (vs-ensure-terminal-buffer)))
           (when b (vs-open-terminal-panel b)))))))

;; vterm 旁路表修复（终端聚焦时仍生效的编辑区命令，
;; VSCode commandsToSkipShell 对应物）：
;; execute 泛型的 command 参数是命令类实例（define-command 为每个命令
;; 生成同名类，defcommand.lisp class-name 默认=name），旁路表的符号是
;; 类名，匹配必须用 typep（上游语义正确）；当年误判 typep 必炸改 eq，
;; 实测 eq 对实例永假 → 面板内一切 bypass 键静默漏进终端。typep 只对
;; 无同名类的符号会炸 unknown type specifier，用 find-class 存在性防御。
(let ((execute-sym (vs$ :lem "EXECUTE"))
      (mode-sym (vs$ :lem-terminal/terminal-mode "TERMINAL-MODE"))
      (input-sym (vs$ :lem-terminal/terminal-mode "TERMINAL-INPUT"))
      (bypass-sym (vs$ :lem-terminal/terminal-mode "*BYPASS-COMMANDS*")))
  (when (and execute-sym mode-sym input-sym bypass-sym)
    (eval
     `(sb-ext:without-package-locks
        (defmethod ,execute-sym ((mode ,mode-sym) command argument)
          (declare (ignore argument))
          (if (loop :for sym :in (symbol-value ',bypass-sym)
                    :thereis (and (ignore-errors (find-class sym nil))
                                  (typep command sym)))
              (call-next-method)
              (,input-sym)))))
    (dolist (cmd (list 'vscode-toggle-terminal
                       'vscode-toggle-sidebar
                       (vs$ :lem "FIND-FILE-RECURSIVELY")
                       (vs$ :lem "SAVE-BUFFER")
                       (vs$ :lem "SPLIT-ACTIVE-WINDOW-HORIZONTALLY")
                       (vs$ :lem "NEXT-WINDOW")
                       (vs$ :lem/legit "LEGIT-STATUS")
                       (vs$ :lem/grep "PROJECT-GREP")))
      (when cmd
        (pushnew cmd (symbol-value bypass-sym))))))
;; NEXT-WINDOW（C-x o）入表理由：终端聚焦时 M-`/C-`/C-j 在 legacy 终端
;; 输入协议下不可达（M-` 被拆 Escape、C-j 同码 Return、C-` 即反引号），
;; C-x o 是 ncurses 侧唯一的窗间逃生通道；SDL2 前端无此约束。
