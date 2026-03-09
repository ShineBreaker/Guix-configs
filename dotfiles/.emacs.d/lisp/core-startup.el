;;; core-startup.el --- 基础启动与路径配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 负责最早期的运行时行为：GC 恢复、缓存目录、基础内建功能开关。

;;; Code:

(require 'use-package)
(require 'recentf)
(require 'desktop)
(setq use-package-always-ensure nil) ; 只使用 Guix 提供的包

;; 启动结束后恢复更平衡的 GC 策略。
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 64 1024 1024)
                  gc-cons-percentage 0.1)
            (garbage-collect)))

;; 与 LSP/外部进程通信时的吞吐优化。
(setq read-process-output-max (* 3 1024 1024))

;; 基础启动体验。
(setq inhibit-startup-screen t
      initial-scratch-message nil
      ring-bell-function 'ignore
      confirm-kill-emacs nil
      confirm-kill-processes nil)

;; 统一缓存与杂项文件目录。
(use-package no-littering
  :demand t
  :config
  (setq auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t)))
  (setq custom-file (no-littering-expand-etc-file-name "custom.el"))
  (when (file-exists-p custom-file)
    (load custom-file t)))

;; 内建持久化能力。
(savehist-mode 1)
(recentf-mode 1)
(setq recentf-max-saved-items 300)

;; 复刻 Zed 的 `autosave: on_focus_change`：切出 Emacs 时自动保存。
(defun my/save-on-focus-change ()
  "当 Emacs 失去焦点时自动保存全部文件。"
  (unless (frame-focus-state)
    (save-some-buffers t)))

(add-function :after after-focus-change-function #'my/save-on-focus-change)

;; 复刻 `restore_on_startup: last_session`。
(desktop-save-mode 1)
(setq desktop-restore-eager 5)
(setq desktop-save nil)

(provide 'core-startup)
;;; core-startup.el ends here
