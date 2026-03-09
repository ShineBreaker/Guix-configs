;;; early-init.el --- Emacs early init for Guix -*- lexical-binding: t; -*-
;;; Commentary:
;; 在 GUI 初始化之前尽早执行：加速启动、减少闪屏、避免 package.el 介入。

;;; Code:

;; Guix + use-package 工作流：由系统包管理，禁用 package.el 自动初始化。
(setq package-enable-at-startup nil)

;; 启动阶段放宽 GC，提升初始加载速度。
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; 降低双向文本算法开销（常见于大文件/长行场景）。
(setq-default bidi-display-reordering 'left-to-right
              bidi-paragraph-direction 'left-to-right)

;; GUI 启动时避免不必要的 frame 重绘。
(setq frame-inhibit-implied-resize t
      inhibit-compacting-font-caches t)

;; 启动防闪屏：
;; 在主题真正加载前，先给初始 frame 一个深色兜底，避免出现白底闪烁。
;; 颜色与 noctalia 主题默认背景/前景保持一致。
(setq frame-background-mode 'dark)
(dolist (entry '((background-color . "#151313")
                 (foreground-color . "#e8e1e1")
                 (background-mode . dark)))
  (add-to-list 'default-frame-alist entry)
  (add-to-list 'initial-frame-alist entry))

(provide 'early-init)
;;; early-init.el ends here
