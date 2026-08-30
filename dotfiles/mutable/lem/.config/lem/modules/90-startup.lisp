;;; modules/90-startup.lisp — 启动行为与钩子登记
;;;
;;; 依赖：explorer（toggle-sidebar / heal）、terminal（vs-ensure-terminal-buffer
;;; / vs-open-terminal-panel）。必须最后加载。

(in-package :lem-user)

;; VSCode 开箱布局：启动即展开 Explorer 侧栏 + 底部终端面板，焦点停在编辑区。
;; 注意：after-init 阶段创建的 side window + buffer 会被 display 层拒绘
;; （lem 2.3.0 实测恒空白；交互期同样代码显示正常），故挂 post-command
;; 首次触发——此时命令循环与重绘世界已就绪。remove-hook 是宏不可 funcall，
;; 用标志位空转代替自摘除。
(defparameter *vs-startup-opened* nil)

(defun vs-open-workspace-on-startup ()
  (unless *vs-startup-opened*
    (setf *vs-startup-opened* t)
    ;; 1) Explorer 侧栏（leftside 独立槽位，不影响主窗树）
    (vscode-toggle-sidebar)
    ;; 2) 底部终端面板（vterm；split 管线与顺序约束见 50-terminal
    ;;    的 vs-open-terminal-panel）
    (let ((buf (vs-ensure-terminal-buffer)))
      (when buf
        (let ((main (vs-open-terminal-panel buf)))
          ;; 3) 焦点交还主编辑区（VSCode 启动语义）
          (setf (current-window) main))))
    (vs-focus-main-window)))

;; find-file 主通道（覆盖 prompt 确定等 post-command 盲区）+ 兜底。
;; *find-file-hook* 的 home 包是 lem/buffer/file（未 reexport 进 :lem，
;; vs$ :lem 解析必空），按仓库规范走 vs$ 动态解析；找不到只跳过挂载，
;; 还有 post-command 兜底。
(let ((hook (vs$ :lem/buffer/file "*FIND-FILE-HOOK*")))
  (when hook
    (add-hook (symbol-value hook) 'vs-explorer-on-find-file)))
(add-hook *post-command-hook* 'vs-open-workspace-on-startup)
(add-hook *post-command-hook* 'vs-explorer-maybe-activate)
(add-hook *post-command-hook* 'vs-maybe-heal)
(add-hook *window-size-change-functions* 'vs-resize-heal)
