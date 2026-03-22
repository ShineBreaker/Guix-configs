;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; startup.el --- 启动与持久化 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置启动行为、GC 策略、持久化等。

;;; Code:

(require 'recentf)
(require 'desktop)

;; 优先加载较新的源文件
(setq load-prefer-newer t)

;; 启动后恢复 GC 策略
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 64 1024 1024)
                  gc-cons-percentage 0.1)
            (garbage-collect)))

;; LSP 通信优化
(setq read-process-output-max (* 3 1024 1024))

;; 基础启动体验
(setq inhibit-startup-screen t
      initial-scratch-message nil
      ring-bell-function 'ignore
      confirm-kill-emacs nil
      confirm-kill-processes nil)

;; no-littering（统一缓存目录）
(use-package no-littering
  :demand t
  :config
  (setq auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t)))
  (setq custom-file (no-littering-expand-etc-file-name "custom.el"))
  (when (file-exists-p custom-file)
    (load custom-file t)))

;; 持久化
(savehist-mode 1)
(recentf-mode 1)
(setq recentf-max-saved-items 300)

;; 失去焦点时自动保存
(add-function :after after-focus-change-function
              (lambda ()
                (unless (frame-focus-state)
                  (save-some-buffers t))))

;; 会话恢复
(desktop-save-mode 1)
(setq desktop-restore-eager 5
      desktop-save nil)

(provide 'startup)
;;; startup.el ends here
