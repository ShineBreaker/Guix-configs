;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; workspace.el --- 工作区布局与文件树 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Treemacs 文件树和 VS Code 风格的工作区布局。

;;; Code:

(require 'seq)
(require 'cl-lib)

;; Treemacs 文件树
(use-package treemacs
  :demand t
  :custom
  (treemacs-width 30)
  (treemacs-position 'left)
  :config
  (setq treemacs-git-mode 'simple)
  (treemacs-project-follow-mode 1)
  (treemacs-follow-mode 1))

;; Nerd Icons 主题
(use-package treemacs-nerd-icons
  :after treemacs
  :config
  (treemacs-load-theme "nerd-icons"))

;; 辅助函数
(defun my/find-code-window ()
  "查找代码编辑窗口。"
  (seq-find
   (lambda (win)
     (with-selected-window win
       (and (not (window-parameter win 'window-side))
            (not (derived-mode-p 'treemacs-mode 'vterm-mode 'dashboard-mode)))))
   (window-list)))

;; VS Code 风格布局：左树+中代码+下终端+右AI
(defun my/vscode-layout ()
  "重置为类似 VS Code 的布局。"
  (interactive)
  (let* ((terminal-height 12)
         (code-win nil)
         (vterm-win
          (seq-find
           (lambda (win)
             (with-selected-window win
               (derived-mode-p 'vterm-mode)))
           (window-list))))
    ;; 打开 Treemacs
    (unless (and (fboundp 'treemacs-is-visible) (treemacs-is-visible))
      (treemacs))
    ;; 获取代码窗口
    (setq code-win (or (my/find-code-window) (selected-window)))
    (select-window code-win)
    ;; 创建底部终端（仅当不存在时）
    (unless (window-live-p vterm-win)
      (when (> (window-height) (+ terminal-height 5))
        (let ((term-win (split-window-below (- (window-height) terminal-height))))
          (select-window term-win)
          (if (fboundp 'my/vterm)
              (my/vterm)
            (if (fboundp 'vterm)
                (vterm)
              (shell)))
          ;; 返回代码窗口
          (select-window code-win))))
    ;; 显示 minimap（仅在 GUI 模式下）
    (when (and (display-graphic-p)
               (fboundp 'minimap-create)
               (not (get-buffer-window "*MINIMAP*")))
      (minimap-create))
    ;; 显示右侧功能栏（仅 GUI 模式）
    (when (and (display-graphic-p)
               (fboundp 'my/sidebar-show))
      (my/sidebar-show))
    ;; 焦点回到代码窗口
    (when (window-live-p code-win)
      (select-window code-win))))

;; 判断是否应该自动触发布局
(defun my/should-auto-layout-p ()
  "判断当前是否应该自动触发 VSCode 布局。"
  (and (buffer-file-name)
       (not (derived-mode-p 'org-mode 'org-agenda-mode))
       (not (string-match-p "\\*.*\\*" (buffer-name)))
       (or (and (fboundp 'projectile-project-p) (projectile-project-p))
           (vc-backend (buffer-file-name)))))

;; 跟踪当前项目
(defvar my/current-project nil
  "当前项目的根目录，用于检测项目切换。")

;; 打开项目文件时自动应用布局
(defun my/auto-layout-on-file-open ()
  "打开文件时，如果切换到了新项目则自动应用布局。"
  (when (my/should-auto-layout-p)
    (let ((project-root (and (fboundp 'projectile-project-root)
                             (projectile-project-root))))
      (when (and project-root
                 (not (equal project-root my/current-project)))
        (setq my/current-project project-root)
        (run-with-idle-timer 0.1 nil #'my/vscode-layout)))))

;; 快捷键绑定
(global-set-key (kbd "<f5>") #'my/vscode-layout)
(add-hook 'find-file-hook #'my/auto-layout-on-file-open)

(provide 'workspace)
;;; workspace.el ends here
