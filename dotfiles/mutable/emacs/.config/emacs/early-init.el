;;; early-init.el --- literal-config 启动期优化 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai004@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 在 GUI 初始化之前尽早执行：加速启动、减少闪屏、避免 package.el 介入。
;;
;; 本文件独立维护，不由 emacs.org tangle 生成（避免防闪屏逻辑被 tangle 影响）。
;; chemacs2 的引导层（dotfiles/mutable/emacs/.config/emacs/early-init.el）会自动加载
;; 本目录的 early-init.el。
;;
;; 优化项：
;; 1. 禁用 package.el - 使用 Guix 管理包
;; 2. 提高 GC 阈值 - 启动时减少垃圾回收次数（启动后由 gcmh 重置）
;; 3. 禁用双向文本 - 提升大文件性能
;; 4. 防止 frame 重绘 - 减少启动时视觉闪烁
;; 5. 设置深色背景 - 避免白屏闪烁
;; 6. Native-comp 调优 - 静默警告噪音
;; 7. exec-path 前置 - 确保 lib.el 的 executable-* 缓存命中

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

(defvar literal--file-name-handler-alist-original file-name-handler-alist
  "启动前的 file-name-handler-alist,启动完成后恢复。
Phase 7.1 决策:file-name-handler-alist 的完整 save/clear/restore 生命周期
**只在 early-init.el 中做一次**。早期 main.el 也做了一遍 defvar,但那时变量
早已被清空,导致 emacs-startup-hook 把 nil 写回——用户失去 jka-compr/gz/el.gz
自动解压 + tramp handler。现在 main.el 不再重复。")
(setq file-name-handler-alist nil)

;; 启动完成后恢复 file-name-handler-alist。early-init.el 独占整个生命周期,
;; 因此 restore hook 也必须在这里注册(原先在 main.el 中注册,捕获到的 original
;; 已是 nil,等于把 jka-compr/tramp handler 永久关掉)。
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist
                  literal--file-name-handler-alist-original)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 文本渲染优化
;; ═════════════════════════════════════════════════════════════════════════════
;;
;; Phase 7.1 决策(保留):强制 LTR(左到右)显示方向。 bidi 重新排序在
;; 大文件 / 长行渲染上开销显著(Emacs 30+ 已优化但仍有可测量差异),强制 LTR
;; 让中文/英文/代码这种主流 LTR 内容受益。
;;
;; 风险:Arabic / Hebrew / RTL 自然语言文本会被错误显示为 LTR。本配置作者主要
;; 用中文/英文/代码,不处理 RTL 自然语言文本,故可接受。若未来需要 RTL 支持,
;; 删除下面三行 + 在 prog-mode-hook / text-mode-hook 内按需局部放开即可。
(setq-default bidi-display-reordering 'left-to-right
              bidi-paragraph-direction 'left-to-right)
(when (boundp 'bidi-inhibit-bpa)
  (setq bidi-inhibit-bpa t))
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
;; 启动防闪屏（从颜色方案状态文件读取当前模式）
;; ═════════════════════════════════════════════════════════════════════════════
(let* ((state-file (expand-file-name "var/color-scheme-state.el" user-emacs-directory))
       (bg-color (if (file-exists-p state-file)
                     (condition-case nil
                         (with-temp-buffer
                           (insert-file-contents state-file)
                           (let ((content (buffer-string)))
                             (if (string-match
                                  "(setq[[:space:]\n]+literal/color-scheme-current-bg[[:space:]\n]+\"\\([^\"]+\\)\")"
                                  content)
                                 (match-string 1 content)
                               "#0a0a0a")))
                       (error "#0a0a0a"))
                   "#0a0a0a"))
       (fg-color (if (string= bg-color "#0a0a0a") "#d0d0d0" "#303030"))
       (mode (if (string= bg-color "#0a0a0a") 'dark 'light)))
  (setq frame-background-mode mode)
  (add-to-list 'default-frame-alist `(background-mode . ,mode))
  (add-to-list 'initial-frame-alist `(background-mode . ,mode))
  (when initial-window-system
    (add-to-list 'initial-frame-alist `(background-color . ,bg-color))
    (add-to-list 'initial-frame-alist `(foreground-color . ,fg-color))))

(provide 'early-init)
;;; early-init.el ends here
