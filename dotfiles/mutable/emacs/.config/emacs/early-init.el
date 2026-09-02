;;; early-init.el --- custom-config 启动期优化 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai004@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 在 GUI 初始化之前尽早执行：加速启动、减少闪屏、避免 package.el 介入。
;;
;; 本文件独立维护，不由 emacs.org tangle 生成（避免防闪屏逻辑被 tangle 影响）。
;; 只保留必须早于 main.el 生效的行为；其余优化与偏好设置在 emacs.org 的
;; startup / core-behavior 域：
;; 1. 禁用 package.el - 使用 Guix 管理包
;; 2. 提高 GC 阈值 - 启动时减少垃圾回收次数（startup-gc 域与 main.el 入口有
;;    刻意重复，供 batch-load main.el 场景；启动后由 gcmh 重置）
;; 3. 防止 frame 重绘 / 像素级 resize - standalone 首帧在 init.el 之前创建，
;;    frame 几何行为必须在此设置
;; 4. TTY frame 初始参数 - 注入 window-system-default-frame-alist 的 t 条目，
;;    避免启动阶段显示 Emacs 默认有色 face
;; 5. frame-background-mode 引导 - 让 daemon 启动期选对 face 变体（dark/light）

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 禁用 package.el 自动初始化（使用 Guix 管理包）
;; ═════════════════════════════════════════════════════════════════════════════
(setq package-enable-at-startup nil)

;; ═════════════════════════════════════════════════════════════════════════════
;; 启动性能优化
;; ═════════════════════════════════════════════════════════════════════════════
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; ═════════════════════════════════════════════════════════════════════════════
;; GUI frame 几何（standalone 首帧先于 init.el 创建，必须在此设置）
;; ═════════════════════════════════════════════════════════════════════════════
(setq frame-inhibit-implied-resize t
      frame-resize-pixelwise t)

;; TTY frame 必须在 main.el 加载前就继承终端默认前景/背景，否则 daemon
;; client 和 standalone 启动阶段会短暂显示 Emacs 的有色默认 face。
(let ((tty-parameters '((background-color . "unspecified-bg")
                        (foreground-color . "unspecified-fg")
                        (menu-bar-lines . 0)
                        (tool-bar-lines . 0)
                        (vertical-scroll-bars . nil)
                        (horizontal-scroll-bars . nil))))
  (if-let* ((entry (assq t window-system-default-frame-alist)))
      (dolist (parameter tty-parameters)
        (setf (alist-get (car parameter) (cdr entry)) (cdr parameter)))
    (push (cons t tty-parameters) window-system-default-frame-alist)))

;; ═════════════════════════════════════════════════════════════════════════════
;; frame-background-mode 引导（从颜色方案状态文件读取当前模式）
;; ═════════════════════════════════════════════════════════════════════════════
;;
;; Emacs 以 `emacs --fg-daemon' 启动，frame 由 client 按需创建（瞬时），
;; 无 standalone 冷启动的 1 秒空白期，故无需防闪屏颜色注入。这里只设置
;; `frame-background-mode'：它指导 daemon 启动期的 face 变体选择（dark/light），
;; 避免在首个 GUI frame 创建前 ef-themes 还未加载时，Emacs 误选 light 变体
;; 导致短暂闪烁。状态文件由颜色方案模块在主题切换时写入。
(let ((state-file (expand-file-name "var/color-scheme-state.el" user-emacs-directory))
      (mode 'dark))
  (when (file-exists-p state-file)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents state-file)
          (when (string-match-p "light" (buffer-string))
            (setq mode 'light)))
      (error nil)))
  (setq frame-background-mode mode)
  (add-to-list 'default-frame-alist `(background-mode . ,mode))
  (add-to-list 'initial-frame-alist `(background-mode . ,mode)))

(provide 'early-init)
;;; early-init.el ends here
