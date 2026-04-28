;;; early-init.el --- Emacs early init for Guix -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0
;;; Commentary:
;; 在 GUI 初始化之前尽早执行：加速启动、减少闪屏、避免 package.el 介入。
;;
;; 优化说明：
;; 1. 禁用 package.el - 因为使用 Guix 管理包
;; 2. 提高 GC 阈值 - 启动时减少垃圾回收次数（启动后会被 gcmh 重置）
;; 3. 禁用双向文本 - 提升大文件性能
;; 4. 防止 frame 重绘 - 减少启动时的视觉闪烁
;; 5. 设置深色背景 - 避免白屏闪烁
;; 6. Native-comp 调优 - 增加编译速度，静默警告噪音
;; 7. IO 调优 - 禁用自适应缓冲，减少 LSP 通信卡顿
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

(setq load-prefer-newer t)

;; ═════════════════════════════════════════════════════════════════════════════
;; Native-compilation 优化（如果 Emacs 支持）
;; ═════════════════════════════════════════════════════════════════════════════

;; 启用延迟编译（不阻塞 Emacs 加载）
(when (boundp 'comp-deferred-compilation)
  (setq comp-deferred-compilation t))

;; 静默异步编译警告（减少 *Compile-Log* 噪音）
(when (boundp 'comp-async-report-warnings-errors)
  (setq comp-async-report-warnings-errors nil))

;; 异步编译函数（如果可用）
(when (fboundp 'native-compile-async)
  (setq native-comp-async-report-warnings-errors nil))

(defvar file-name-handler-alist-original)

(defvar custom--diag-early-init-start-time nil
  "debug-init 模式下 early-init 的开始时间。")

(when init-file-debug
  (setq custom--diag-early-init-start-time (current-time))
  (message "[init:phase] ═══ early-init 开始 ═══"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 包管理器设置
;; ═════════════════════════════════════════════════════════════════════════════

;; 禁用 package.el 自动初始化（使用 Guix 管理包）
(setq package-enable-at-startup nil)

;; ═════════════════════════════════════════════════════════════════════════════
;; 启动性能优化
;; ═════════════════════════════════════════════════════════════════════════════

;; 启动阶段放宽 GC 阈值，减少垃圾回收次数
;; 注意：启动完成后会被 gcmh 包重置为合理值
(setq gc-cons-threshold most-positive-fixnum  ; 最大值，启动时几乎不触发 GC
      gc-cons-percentage 0.6)                 ; GC 触发百分比

;; 降低文件处理器数量检查频率（提升启动速度）
(setq file-name-handler-alist-original file-name-handler-alist
      file-name-handler-alist nil)

;; ═════════════════════════════════════════════════════════════════════════════
;; 文本渲染优化
;; ═════════════════════════════════════════════════════════════════════════════

;; 禁用双向文本算法（提升大文件/长行性能）
;; 如果需要编辑阿拉伯语/希伯来语等从右到左的文本，可以注释掉这两行
(setq-default bidi-display-reordering 'left-to-right
              bidi-paragraph-direction 'left-to-right)

;; ═════════════════════════════════════════════════════════════════════════════
;; GUI 优化
;; ═════════════════════════════════════════════════════════════════════════════

;; 避免 GUI 启动时不必要的 frame 重绘
(setq frame-inhibit-implied-resize t      ; 禁止隐式调整 frame 大小
      inhibit-compacting-font-caches t    ; 禁止压缩字体缓存
      frame-resize-pixelwise t            ; 像素级 frame 调整（corfu childframe 需要）
      use-file-dialog nil                 ; 禁用文件选择对话框
      use-dialog-box nil)                 ; 禁用所有对话框弹窗

;; ═════════════════════════════════════════════════════════════════════════════
;; 启动防闪屏
;; ═════════════════════════════════════════════════════════════════════════════

;; 从颜色方案状态文件读取当前模式，设置对应的背景色
;; GUI 模式：设置背景/前景色以防闪屏
;; 终端模式：仅设置 background-mode，不覆盖终端配色和透明度
(let* ((state-file (expand-file-name "var/color-scheme-state.el" user-emacs-directory))
       (bg-color (if (file-exists-p state-file)
                     (condition-case nil
                         (with-temp-buffer
                           (insert-file-contents state-file)
                           (let ((content (buffer-string)))
                             (if (string-match
                                  "(setq[[:space:]\n]+custom/color-scheme-current-bg[[:space:]\n]+\"\\([^\"]+\\)\")"
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
  ;; daemon/client 架构下不要把占位色写入 `default-frame-alist'：
  ;; 它们会污染后续 emacsclient 创建的 GUI frame，使其继承早期保底颜色，
  ;; 而不是当前主题的真实配色。
  ;;
  ;; standalone GUI 冷启动仍保留初始帧占位色，以减少首帧闪屏。
  (when initial-window-system
    (add-to-list 'initial-frame-alist `(background-color . ,bg-color))
    (add-to-list 'initial-frame-alist `(foreground-color . ,fg-color))))

(when init-file-debug
  (message "[init:phase] ═══ early-init 完成 (%.3fs) ═══"
           (float-time (time-subtract (current-time)
                                      custom--diag-early-init-start-time))))

(provide 'early-init)
;;; early-init.el ends here
