;;; modules/90-startup.lisp — 启动行为与钩子登记
;;;
;;; 依赖：explorer（toggle-sidebar / heal）、terminal（vs-ensure-terminal-buffer
;;; / vs-open-terminal-panel）、welcome（vs-setup-welcome 重申欢迎页布局，
;;; 防 dashboard 扩展后加载覆盖默认鹦鹉页）。必须最后加载。

(in-package :lem-user)

;; VSCode 开箱布局：启动即展开 Explorer 侧栏 + 底部终端面板，焦点停在编辑区。
;; 注意：after-init 阶段创建的 side window + buffer 会被 display 层拒绘
;; （lem 2.3.0 实测恒空白；交互期同样代码显示正常），故挂 post-command
;; 首次触发——此时命令循环与重绘世界已就绪。一次性任务，首次执行后经
;; eval remove-hook 从 post-command 链摘除（remove-hook 是宏不可 funcall，
;; eval 构造调用即可，vs-hook-add 同款手法；旧标志位空转方案会永久占用
;; 每命令一次的钩子遍历）。
(defparameter *vs-startup-opened* nil)

;; 整体 ignore-errors：display 层操作（toggle/split）在边界场景可能抛错，
;; post-command 链上抛错会连累排在后面的 activate/heal 钩子（与
;; 40-explorer 的钩子同款防护）。中途抛错则 remove-hook 不执行、钩子
;; 残留，但标志位已置，此后每次触发只空转 no-op，无害。
(defun vs-open-workspace-on-startup ()
  (unless *vs-startup-opened*
    (setf *vs-startup-opened* t)
    (ignore-errors
      ;; 0) 欢迎页布局重申（85 load 期已覆盖首绘；此处防扩展后加载覆盖）
      (vs-setup-welcome)
      ;; 1) Explorer 侧栏（leftside 独立槽位，不影响主窗树）
      (vscode-toggle-sidebar)
      ;; 2) 底部终端面板（split 管线与顺序约束见 50-terminal 的
      ;;    vs-open-terminal-panel）；首键若已是 C-j（toggle 先开了面板），
      ;;    此处跳过 split，否则会叠加出第二个终端窗
      (let ((buf (vs-ensure-terminal-buffer)))
        (when buf
          (unless (find buf (window-list) :key #'window-buffer)
            (let ((main (vs-open-terminal-panel buf)))
              ;; 3) 焦点交还主编辑区（VSCode 启动语义）
              (setf (current-window) main)))))
      (vs-focus-main-window)
      ;; 4) 补建 frame-multiplexer 条（webview 下 after-init 期 vf 常缺）
      (vs-ensure-frame-multiplexer)
      (eval '(remove-hook *post-command-hook*
                          'vs-open-workspace-on-startup)))))

;; frame-multiplexer 的 vf header 条（顶部 "0: <buffer>" 行）在 webview 下
;; 常缺失：after-init 期 current-frame 尚未就绪，enable hook 里 make-virtual-frame
;; 抛错被吞（ncurses 同配置 hws=1、webview login views 无 header view 实测）。
;; 补救：首次命令（此时编辑线程与 frame 世界已就绪）off → init 幂等重建，
;; ncurses 探针 hws 1→0→1 验证。off 只 delete 既有 vf（缺失则 no-op）。
;; 仅 ncurses 补建：webview 下 tabbar（60 的文件 tab 条）是顶层标签条，
;; vf 的 "0: <buffer>" 单行与它重复，双重显示反而碍眼。
(defun vs-ensure-frame-multiplexer ()
  (ignore-errors
    (let ((off (vs$ :lem/frame-multiplexer "FRAME-MULTIPLEXER-OFF"))
          (init (vs$ :lem/frame-multiplexer "FRAME-MULTIPLEXER-INIT"))
          (impl-fn (vs$ :lem "IMPLEMENTATION"))
          (name-fn (vs$ :lem-core "IMPLEMENTATION-NAME"))
          (frontend (and (fboundp impl-fn) (fboundp name-fn)
                         (ignore-errors (funcall name-fn (funcall impl-fn))))))
      (when (and off init (eq frontend :ncurses))
        (funcall off)
        (funcall init)))))

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
