;;; terminal.el --- 终端模拟器 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 vterm 终端模拟器。

;;; Code:

;; Vterm（高性能终端模拟器）
(use-package vterm
  :commands (vterm custom/open-terminal)
  :config
  ;; ═══════════════════════════════════════════════════════════════════════════
  ;; 环境变量：让终端中的 EDITOR 指向当前 Emacs 会话
  ;; ═══════════════════════════════════════════════════════════════════════════
  ;; emacsclient 阻塞模式：终端会等待编辑完成。
  ;; 终端应用里调用编辑器时，仍由 `server-edit` 负责结束阻塞客户端。
  (with-eval-after-load 'server
    (when (server-running-p)
      (add-to-list 'vterm-environment "EDITOR=emacsclient")
      (add-to-list 'vterm-environment "VISUAL=emacsclient")))

  ;; ═══════════════════════════════════════════════════════════════════════════
  ;; Ctrl+hjkl 与 vterm 原生输入兼容
  ;; ═══════════════════════════════════════════════════════════════════════════
  ;; 全局把 C-h/j/k/l 改成了光标移动；进入 vterm 后需要把这些组合键重新发给终端，
  ;; 这样 shell、fzf、lazygit、终端内 Vim/TUI 不会丢失控制键输入。
  (defun custom/vterm-send-ctrl-h ()
    "向 vterm 发送 C-h。"
    (interactive)
    (vterm-send-key "h" nil nil t))

  (defun custom/vterm-send-ctrl-j ()
    "向 vterm 发送 C-j。"
    (interactive)
    (vterm-send-key "j" nil nil t))

  (defun custom/vterm-send-ctrl-k ()
    "向 vterm 发送 C-k。"
    (interactive)
    (vterm-send-key "k" nil nil t))

  (defun custom/vterm-send-ctrl-l ()
    "向 vterm 发送 C-l。"
    (interactive)
    (vterm-send-key "l" nil nil t))

  (define-key vterm-mode-map (kbd "C-h") #'custom/vterm-send-ctrl-h)
  (define-key vterm-mode-map (kbd "C-j") #'custom/vterm-send-ctrl-j)
  (define-key vterm-mode-map (kbd "C-k") #'custom/vterm-send-ctrl-k)
  (define-key vterm-mode-map (kbd "C-l") #'custom/vterm-send-ctrl-l)

  ;; 让 vterm 颜色跟随主题
  (defun custom/open-terminal-sync-colors ()
    "同步 vterm 颜色到当前主题"
    (setq vterm-color-black   (face-attribute 'term-color-black :foreground nil t)
          vterm-color-red     (face-attribute 'term-color-red :foreground nil t)
          vterm-color-green   (face-attribute 'term-color-green :foreground nil t)
          vterm-color-yellow  (face-attribute 'term-color-yellow :foreground nil t)
          vterm-color-blue    (face-attribute 'term-color-blue :foreground nil t)
          vterm-color-magenta (face-attribute 'term-color-magenta :foreground nil t)
          vterm-color-cyan    (face-attribute 'term-color-cyan :foreground nil t)
          vterm-color-white   (face-attribute 'term-color-white :foreground nil t)))

  (custom/open-terminal-sync-colors)
  ;; 在加载主题后同步颜色
  (advice-add 'load-theme :after (lambda (&rest _) (custom/open-terminal-sync-colors))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 智能 vterm：自动 cd 到项目根目录
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/open-terminal (&optional arg)
  "打开 vterm 终端，自动切换到项目根目录。
如果不在项目中，则使用当前目录。
带前缀参数 ARG 时，使用当前文件所在目录。"
  (interactive "P")
  (custom/diag "terminal" "打开终端: shell=%s, dir=%s" shell-file-name default-directory)
  (let* ((project-root (when (and (fboundp 'projectile-project-root)
                                  (ignore-errors (projectile-project-p)))
                         (ignore-errors (projectile-project-root))))
         (shell (or shell-file-name
                    (getenv "SHELL")
                    "/bin/sh"))
         (default-directory
           (cond
            ;; 前缀参数：使用当前文件目录
            (arg default-directory)
            ;; 在项目中：使用项目根目录
            (project-root project-root)
            ;; 不在项目中：使用当前目录
            (t default-directory))))
    (setq shell-file-name shell)
    (vterm)))

(provide 'terminal)
;;; terminal.el ends here
