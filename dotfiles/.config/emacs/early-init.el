;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; early-init.el --- Emacs early init for Guix -*- lexical-binding: t; -*-
;;; Commentary:
;; 在 GUI 初始化之前尽早执行：加速启动、减少闪屏、避免 package.el 介入。
;;
;; 优化说明：
;; 1. 禁用 package.el - 因为使用 Guix 管理包
;; 2. 提高 GC 阈值 - 启动时减少垃圾回收次数（启动后会被 gcmh 重置）
;; 3. 禁用双向文本 - 提升大文件性能
;; 4. 防止 frame 重绘 - 减少启动时的视觉闪烁
;; 5. 设置深色背景 - 避免白屏闪烁

;;; Code:

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
      inhibit-compacting-font-caches t)   ; 禁止压缩字体缓存

;; ═════════════════════════════════════════════════════════════════════════════
;; 启动防闪屏
;; ═════════════════════════════════════════════════════════════════════════════

;; 在主题加载前设置深色背景，避免白屏闪烁
;; 这些设置会被后续加载的主题覆盖
(setq frame-background-mode 'dark)
(dolist (entry '((background-mode . dark)
                 (background-color . "#0a0a0a")
                 (foreground-color . "#d0d0d0")))
  (add-to-list 'default-frame-alist entry)
  (add-to-list 'initial-frame-alist entry))

(provide 'early-init)
;;; early-init.el ends here
