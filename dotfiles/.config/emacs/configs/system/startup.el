;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; startup.el --- 启动与持久化 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置启动行为、GC 策略、持久化等。

;;; Code:

;; 优先加载较新的源文件
(setq load-prefer-newer t)

;; GCMH - 智能垃圾回收优化
(use-package gcmh
  :demand t
  :custom
  (gcmh-idle-delay 'auto)
  (gcmh-auto-idle-delay-factor 10)
  (gcmh-high-cons-threshold (* 64 1024 1024))
  :config
  (gcmh-mode 1))

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

;; 持久化（延迟加载）
(use-package savehist
  :defer 0.5
  :config
  (savehist-mode 1))

(use-package recentf
  :defer 1
  :config
  (recentf-mode 1)
  (setq recentf-max-saved-items 300))

;; 失去焦点时自动保存
(add-function :after after-focus-change-function
              (lambda ()
                (unless (frame-focus-state)
                  (save-some-buffers t))))

;; 会话恢复（延迟加载）
(use-package desktop
  :defer 1
  :config
  (desktop-save-mode 1)
  (setq desktop-restore-eager 5
        desktop-save nil))

(provide 'startup)
;;; startup.el ends here
