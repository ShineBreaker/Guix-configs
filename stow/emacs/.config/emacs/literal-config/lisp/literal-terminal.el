;;; literal-terminal.el --- ghostel 终端 + 智能打开 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai004@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; ghostel 终端模拟器（libghostty-vt 后端）配置。
;; - `literal/open-terminal'：底部 side-window（高度 1/3），自动 cd 项目根目录
;; - C-S-c 进入 copy-mode，C-S-v 从 kill-ring 粘贴
;; - C-h 在 ghostel 内重绑为发送原始 Ctrl+H（全局被 backward-char 占用）
;; - M-方向键 保持窗口切换
;;
;; 关键 hack：终端里的 `git commit' / `git rebase -i' 需要 EDITOR 返回。
;; ghostel 的 pre-spawn-hook 跑在进程创建 *之前*，`get-buffer-process' 返回 nil，
;; 故不能用 `with-editor-export-git-editor'（它会抛
;; "Cannot export environment variables in this buffer"）。
;; 必须直接调 `with-editor--setup'（内部 API），手动绑定 `with-editor--envvar'。

;;; Code:

(eval-when-compile
  (require 'with-editor nil t))

(declare-function literal/display-or-focus "literal-git" (buffer action &optional select))

;; agent-shell 后端标记的前向声明，避免 byte-compile free variable 警告
(defvar literal--agent-ghostel-p nil)

;; ═════════════════════════════════════════════════════════════════════════════
;; ghostel 配置
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/ghostel-export-git-editor ()
  "在 `ghostel-pre-spawn-hook' 里导出 GIT_EDITOR 到即将启动的 shell 进程。
等价于 `(with-editor \"GIT_EDITOR\")' 宏展开后的 setup 部分，但不带 body ——
只保留对当前动态绑定 `process-environment' 的副作用。"
  (when (fboundp 'with-editor--setup)
    (let ((with-editor--envvar "GIT_EDITOR"))
      (with-editor--setup))))

(defun literal/ghostel-send-ctrl-h ()
  "向 ghostel 发送 C-h（全局被 backward-char 占用，需显式重绑）。"
  (interactive)
  (ghostel-send-key "h" "ctrl"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 智能 ghostel：自动 cd 到项目根目录
;; ═════════════════════════════════════════════════════════════════════════════

(defconst literal:terminal-side-action
  '((display-buffer-in-side-window
     (side . bottom) (slot . 0) (window-height . 0.33)))
  "终端面板的 display-buffer action：底部 side-window，高度 1/3。")

(defun literal--terminal-existing-buffer ()
  "返回当前已存在的普通 ghostel buffer（非 agent 后端），无则 nil。"
  (cl-find-if
   (lambda (buf)
     (and (buffer-live-p buf)
          (with-current-buffer buf (derived-mode-p 'ghostel-mode))
          (not (buffer-local-value 'literal--agent-ghostel-p buf))))
   (buffer-list)))

(defun literal/open-terminal (&optional arg)
  "打开 ghostel 终端（底部 side-window，高度 1/3），自动切换到项目根目录。
如果不在项目中，则使用当前目录。
带前缀参数 ARG 时，使用当前文件所在目录。

有已显示的终端窗口则聚焦；有终端 buffer 但未显示则按
`literal:terminal-side-action' 显示到底部；无则新建。"
  (interactive "P")
  (let* ((project-root (when (and (fboundp 'projectile-project-root)
                                  (ignore-errors (projectile-project-p)))
                         (ignore-errors (projectile-project-root))))
         (shell (or shell-file-name
                    (getenv "SHELL")
                    "/bin/sh"))
         (default-directory
           (cond
            (arg default-directory)                  ; 前缀参数：当前文件目录
            (project-root project-root)              ; 在项目中：项目根目录
            (t default-directory))))                 ; 不在项目中：当前目录
    (setq shell-file-name shell)
    (let ((buf (or (literal--terminal-existing-buffer)
                   ;; 无现存普通 ghostel：用 save-window-excursion 隔离窗口副作用
                   (let ((before (buffer-list)))
                     (save-window-excursion (ghostel))
                     (cl-find-if
                      (lambda (b)
                        (with-current-buffer b (derived-mode-p 'ghostel-mode)))
                      (cl-set-difference (buffer-list) before))))))
      (when (buffer-live-p buf)
        (literal/display-or-focus buf literal:terminal-side-action t)))))

(provide 'literal-terminal)
;;; literal-terminal.el ends here
