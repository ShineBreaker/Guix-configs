;;; early-init.el --- literal-config 启动期优化 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai004@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 在 GUI 初始化之前尽早执行：加速启动、减少闪屏、避免 package.el 介入。
;;
;; 本文件独立维护，不由 emacs.org tangle 生成（避免防闪屏逻辑被 tangle 影响）。
;; 优化项：
;; 1. 禁用 package.el - 使用 Guix 管理包
;; 2. 提高 GC 阈值 - 启动时减少垃圾回收次数（启动后由 gcmh 重置）
;; 3. 防止 frame 重绘 - 减少启动时视觉闪烁
;; 4. frame-background-mode 引导 - 让 daemon 启动期选对 face 变体（dark/light）
;; 5. Native-comp 调优 - 静默警告噪音
;; 6. exec-path 前置 - 让外部命令可由 PATH 解析

;;; Code:

;; 优先加载 .elc
(setq load-prefer-newer nil)

;; ═════════════════════════════════════════════════════════════════════════════
;; Native-compilation 优化
;; ═════════════════════════════════════════════════════════════════════════════
(when (boundp 'comp-deferred-compilation)
  (setq comp-deferred-compilation t))
(when (boundp 'native-comp-async-warnings-errors-kind)
  (setq native-comp-async-warnings-errors-kind 'important))
(when (boundp 'comp-async-report-warnings-errors)
  (setq comp-async-report-warnings-errors nil))

;; ═════════════════════════════════════════════════════════════════════════════
;; 禁用 package.el 自动初始化（使用 Guix 管理包）
;; ═════════════════════════════════════════════════════════════════════════════
(setq package-enable-at-startup nil)

;; ═════════════════════════════════════════════════════════════════════════════
;; exec-path 前置（必须在 literal-bootstrap.el 的 executable-* 缓存 defvar 之前）
;; ═════════════════════════════════════════════════════════════════════════════
;;
;; literal-bootstrap.el 在 init.el 加载早期 require，其 `defconst literal:executable-*'
;; 在求值瞬间调用 `executable-find'。若此时 `~/.local/bin'（agenote/godot/dot 等
;; 用户工具）或 Guix profile bin 尚未加入 exec-path，缓存会得到 nil，导致运行
;; 时所有依赖这些工具的调用失效。
(let* ((guix-profile (or (getenv "GUIX_PROFILE")
                         (expand-file-name "~/.guix-profile")))
       (guix-bin (expand-file-name "bin" guix-profile))
       (local-bin (expand-file-name "~/.local/bin")))
  (when (file-directory-p guix-bin)
    (add-to-list 'exec-path guix-bin))
  (when (file-directory-p local-bin)
    (add-to-list 'exec-path local-bin)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 启动性能优化
;; ═════════════════════════════════════════════════════════════════════════════
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; 保留 Emacs 31 默认的 file-name-handler 与 bidi 行为。daemon 冷启动不是目标，
;; 且生活应用需要压缩文件、TRAMP 与 RTL 文本始终正确。
(setq auto-mode-case-fold nil)

;; ═════════════════════════════════════════════════════════════════════════════
;; GUI 优化
;; ═════════════════════════════════════════════════════════════════════════════
(setq frame-inhibit-implied-resize t
      inhibit-compacting-font-caches t
      frame-resize-pixelwise t
      use-file-dialog nil
      use-dialog-box nil)

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
