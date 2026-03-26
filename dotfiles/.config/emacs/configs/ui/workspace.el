;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; workspace.el --- 工作区布局与文件树 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Treemacs 文件树和 VS Code 风格的工作区布局。
;;
;; 功能说明：
;; - Treemacs: 左侧文件树
;; - VS Code 布局: 左树+中代码+下终端+右侧栏
;; - 自动布局: 切换项目时自动应用布局
;;
;; 快捷键：
;; - F5: 手动触发工作区布局
;; - SPC t l: 通过 Leader 键触发布局

;;; Code:

(require 'seq)
(require 'cl-lib)

;; ═════════════════════════════════════════════════════════════════════════════
;; Treemacs 文件树
;; ═════════════════════════════════════════════════════════════════════════════

;; Treemacs 提供类似 VS Code 的文件树
;; :demand t 表示立即加载（因为布局功能依赖它）
(use-package treemacs
  :demand t
  :custom
  (treemacs-width 30)           ; 文件树宽度
  (treemacs-position 'left)     ; 显示在左侧
  :config
  (setq treemacs-git-mode 'simple)      ; 简单 Git 状态显示
  (treemacs-project-follow-mode 1)      ; 自动跟随项目
  (treemacs-follow-mode 1))             ; 自动跟随当前文件

;; Nerd Icons 主题（提供更好看的图标）
(use-package treemacs-nerd-icons
  :after treemacs
  :config
  (treemacs-load-theme "nerd-icons"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 辅助函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun my/find-code-window ()
  "查找代码编辑窗口。
排除特殊窗口（文件树、终端、仪表盘等）。"
  (seq-find
   (lambda (win)
     (with-selected-window win
       (and (not (window-parameter win 'window-side))
            (not (derived-mode-p 'treemacs-mode 'vterm-mode 'dashboard-mode)))))
   (window-list)))

;; ═════════════════════════════════════════════════════════════════════════════
;; VS Code 风格布局
;; ═════════════════════════════════════════════════════════════════════════════

(defun my/vscode-layout ()
  "重置为类似 VS Code 的布局。

布局结构：
  ┌─────────┬──────────────┬─────────┐
  │         │              │         │
  │ Treemacs│   编辑器     │ Minimap │
  │  (左)   │   (中间)     │  (右)   │
  │         ├──────────────┤         │
  │         │   终端(下)   │         │
  └─────────┴──────────────┴─────────┘

使用场景：
- 打开项目文件时自动触发
- 手动按 F5 或 SPC t l 触发"
  (interactive)
  (let* ((terminal-height 12)
         (code-win nil)
         (vterm-win
          (seq-find
           (lambda (win)
             (with-selected-window win
               (derived-mode-p 'vterm-mode)))
           (window-list))))
    ;; 1. 打开 Treemacs（如果未显示）
    (unless (and (fboundp 'treemacs-is-visible) (treemacs-is-visible))
      (treemacs))
    ;; 2. 获取代码窗口
    (setq code-win (or (my/find-code-window) (selected-window)))
    (select-window code-win)
    ;; 3. 创建底部终端（仅当不存在时）
    (unless (window-live-p vterm-win)
      (when (> (window-height) (+ terminal-height 5))
        (let ((term-win (split-window-below (- (window-height) terminal-height))))
          (select-window term-win)
          (if (fboundp 'my/vterm)
              (my/vterm)
            (if (fboundp 'vterm)
                (vterm)
              (shell)))
          (select-window code-win))))
    ;; 4. 显示 minimap（仅 GUI 模式）
    (when (and (display-graphic-p)
               (fboundp 'minimap-create)
               (not (get-buffer-window "*MINIMAP*")))
      (minimap-create))
    ;; 5. 显示右侧功能栏（仅 GUI 模式）
    (when (and (display-graphic-p)
               (fboundp 'my/sidebar-show))
      (my/sidebar-show))
    ;; 6. 焦点回到代码窗口
    (when (window-live-p code-win)
      (select-window code-win))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 自动布局触发
;; ═════════════════════════════════════════════════════════════════════════════

(defun my/should-auto-layout-p ()
  "判断当前是否应该自动触发 VSCode 布局。

触发条件：
- 当前缓冲区是文件（非特殊缓冲区）
- 不是 Org Mode 或 Org Agenda
- 在项目中或有版本控制"
  (and (buffer-file-name)
       (not (derived-mode-p 'org-mode 'org-agenda-mode))
       (not (string-match-p "\\*.*\\*" (buffer-name)))
       (or (and (fboundp 'projectile-project-p) (projectile-project-p))
           (vc-backend (buffer-file-name)))))

;; 跟踪当前项目（用于检测项目切换）
(defvar my/current-project nil
  "当前项目的根目录，用于检测项目切换。")

(defun my/auto-layout-on-file-open ()
  "打开文件时，如果切换到了新项目则自动应用布局。

工作原理：
- 检测项目根目录是否改变
- 如果切换到新项目，延迟 0.1 秒后应用布局
- 避免在同一项目内重复触发"
  (when (my/should-auto-layout-p)
    (let ((project-root (and (fboundp 'projectile-project-root)
                             (projectile-project-root))))
      (when (and project-root
                 (not (equal project-root my/current-project)))
        (setq my/current-project project-root)
        (run-with-idle-timer 0.1 nil #'my/vscode-layout)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 快捷键和 Hook
;; ═════════════════════════════════════════════════════════════════════════════

;; F5: 手动触发工作区布局
(global-set-key (kbd "<f5>") #'my/vscode-layout)

;; 打开文件时自动检测并应用布局
(add-hook 'find-file-hook #'my/auto-layout-on-file-open)

(provide 'workspace)
;;; workspace.el ends here
