;;; flycheck.el --- 代码诊断与错误检查 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 提供 IDE 风格的代码错误/警告诊断功能：
;; - 内联波浪线 + fringe 错误/警告图标
;; - 错误弹窗 (posframe, GUI 模式)
;; - 错误列表面板 (flycheck-list-errors)
;; - Mode-line 错误计数
;;
;; 依赖包（需通过 Guix 安装）：
;; - emacs-flycheck
;; - emacs-posframe
;;
;; 快捷键：
;; - `M-g n`        下一个错误
;; - `M-g p`        上一个错误
;; - `M-g l`        错误列表面板
;; - `C-c l t`      切换 flycheck 开关
;; - `C-c ] e`      下一个错误（补充别名）
;; - `C-c [ e`      上一个错误（补充别名）

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; Flycheck 核心
;; ═════════════════════════════════════════════════════════════════════════════

(use-package flycheck
  :defer 0.5
  :custom
  ;; 检查时机：保存后 + 正常空闲时
  (flycheck-check-syntax-automatically '(save idle-change mode-enabled))
  ;; 空闲多久后触发检查（秒）
  (flycheck-idle-change-delay 0.5)
  ;; 错误列表面板最低显示级别
  (flycheck-error-list-minimum-level 'warning)
  ;; fringe 图标样式
  (flycheck-indication-mode 'left-fringe)
  :config
  ;; 禁用 org-lint 检查器（Org 9.7.x 与 Emacs 30 的已知兼容性问题）
  ;; Wrong type argument: number-or-marker-p, #("643" 0 3 (org-lint-marker ...))
  ;; 参见：https://list.orgmode.org/87bjh7sk2a.fsf@localhost/T/
  ;; 同时从注册表移除并加入禁用列表，双重保险
  (setq flycheck-checkers (delq 'org-lint flycheck-checkers))
  (add-to-list 'flycheck-disabled-checkers 'org-lint)

  ;; 全局启用 flycheck（替代 flymake）
  (global-flycheck-mode 1)

  ;; ═══════════════════════════════════════════════════════════════════════════
  ;; 错误列表面板中支持方向键和 Vim 风格导航
  ;; ═══════════════════════════════════════════════════════════════════════════
  (with-eval-after-load 'flycheck-error-list
    (define-key flycheck-error-list-mode-map (kbd "j") #'flycheck-error-list-next-error)
    (define-key flycheck-error-list-mode-map (kbd "k") #'flycheck-error-list-previous-error)
    (define-key flycheck-error-list-mode-map (kbd "<down>") #'flycheck-error-list-next-error)
    (define-key flycheck-error-list-mode-map (kbd "<up>") #'flycheck-error-list-previous-error)
    (define-key flycheck-error-list-mode-map (kbd "q") #'quit-window)
    (define-key flycheck-error-list-mode-map (kbd "RET") #'flycheck-error-list-goto-error)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 错误弹窗（基于 posframe，GUI 模式）
;; ═════════════════════════════════════════════════════════════════════════════

;; 由于 emacs-flycheck-posframe 不在 Guix 仓库中，
;; 直接使用 posframe 实现类似功能。

(defvar custom/flycheck-posframe-buffer " *flycheck-posframe*"
  "用于显示 Flycheck 错误的 posframe 缓冲区名称。")

(defvar custom/flycheck-posframe--timer nil
  "用于自动隐藏 posframe 的计时器。")

(defun custom/flycheck-posframe-hide ()
  "隐藏 flycheck posframe 弹窗。"
  (when (and (fboundp 'posframe-hide)
             (buffer-live-p (get-buffer custom/flycheck-posframe-buffer)))
    (posframe-hide custom/flycheck-posframe-buffer)))

(defun custom/flycheck-posframe-show (errors)
  "使用 posframe 显示 ERRORS。"
  (when (and errors (display-graphic-p))
    (let ((buf (get-buffer-create custom/flycheck-posframe-buffer))
          (messages (mapcar #'flycheck-error-format-message-and-id errors)))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (string-join messages "\n"))))
      (when (require 'posframe nil t)
        (posframe-show buf
                       :position (point)
                       :poshandler 'posframe-poshandler-point-bottom-left-corner
                       :border-width 1
                       :border-color (face-attribute 'shadow :foreground nil t)
                       :internal-border-width 4
                       :min-width 30
                       :max-width 80
                       :height (min (length messages) 10))))))

(defun custom/flycheck-display-errors (errors)
  "根据环境选择错误显示方式。
GUI 模式使用 posframe 弹窗，终端模式使用 echo area。"
  (when errors
    (if (display-graphic-p)
        (custom/flycheck-posframe-show errors)
      ;; 终端回退：echo area 显示
      (let ((messages (mapcar #'flycheck-error-format-message-and-id errors)))
        (message "%s" (string-join messages "\n"))))))

;; 光标移动或命令执行后自动隐藏弹窗
(add-hook 'post-command-hook
          (lambda ()
            (when (and (display-graphic-p)
                       (not (memq this-command '(custom/flycheck-next-error
                                                  custom/flycheck-previous-error))))
              (custom/flycheck-posframe-hide))))

;; 设置 flycheck 使用自定义显示函数
(with-eval-after-load 'flycheck
  (setq flycheck-display-errors-function #'custom/flycheck-display-errors))

;; ═════════════════════════════════════════════════════════════════════════════
;; Fringe 图标自定义
;; ═════════════════════════════════════════════════════════════════════════════

(with-eval-after-load 'flycheck
  (define-fringe-bitmap 'custom/flycheck-fringe-bitmap-double-arrow
    [0 0 0 0 24 60 126 252 126 60 24 0 0 0 0])
  (flycheck-define-error-level 'error
    :severity 100
    :compilation-category 'error
    :overlay-category 'flycheck-error-overlay
    :fringe-bitmap 'custom/flycheck-fringe-bitmap-double-arrow
    :fringe-face 'flycheck-fringe-error)
  (flycheck-define-error-level 'warning
    :severity 50
    :compilation-category 'warning
    :overlay-category 'flycheck-warning-overlay
    :fringe-bitmap 'custom/flycheck-fringe-bitmap-double-arrow
    :fringe-face 'flycheck-fringe-warning)
  (flycheck-define-error-level 'info
    :severity 10
    :compilation-category 'note
    :overlay-category 'flycheck-info-overlay
    :fringe-bitmap 'custom/flycheck-fringe-bitmap-double-arrow
    :fringe-face 'flycheck-fringe-info))

;; ═════════════════════════════════════════════════════════════════════════════
;; Org Mode 集成
;; ═════════════════════════════════════════════════════════════════════════════

;; 在 org-src 编辑缓冲区（C-c ' 打开的代码编辑窗口）中启用 flycheck
(with-eval-after-load 'org-src
  (add-hook 'org-src-mode-hook
            (defun custom/flycheck-org-src-setup ()
              "在 org-src 编辑缓冲区中启用 flycheck。"
              (when (derived-mode-p 'prog-mode)
                (flycheck-mode 1)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Eglot 集成
;; ═════════════════════════════════════════════════════════════════════════════

;; Eglot 默认使用 flymake 显示诊断，禁用 flymake 后端以避免重复显示
(with-eval-after-load 'eglot
  (remove-hook 'flymake-diagnostic-functions 'eglot-flymake-backend t))

;; ═════════════════════════════════════════════════════════════════════════════
;; 错误导航辅助函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/flycheck-next-error ()
  "跳转到下一个错误。"
  (interactive)
  (flycheck-next-error 1 nil t))

(defun custom/flycheck-previous-error ()
  "跳转到上一个错误。"
  (interactive)
  (flycheck-previous-error 1 nil t))

(defun custom/flycheck-toggle ()
  "切换 flycheck 模式。"
  (interactive)
  (custom/diag "flycheck" "切换 Flycheck: %s" (if flycheck-mode "开启" "关闭"))
  (if flycheck-mode
      (progn
        (flycheck-mode -1)
        (message "Flycheck 已禁用"))
    (flycheck-mode 1)
    (message "Flycheck 已启用")))

(defun custom/flycheck-list-errors-dwim ()
  "打开/关闭错误列表面板。"
  (interactive)
  (let ((error-count (length (flycheck-overlay-get-all 'flycheck-error)))
        (warning-count (length (flycheck-overlay-get-all 'flycheck-warning))))
    (custom/diag "flycheck" "错误列表: errors=%d, warnings=%d" error-count warning-count))
  (if (get-buffer-window flycheck-error-list-buffer)
      (quit-window nil (get-buffer-window flycheck-error-list-buffer))
    (flycheck-list-errors)))

(provide 'config-flycheck)
;;; flycheck.el ends here
