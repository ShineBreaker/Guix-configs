;;; navigation.el --- 代码阅读增强 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 提升代码阅读体验的功能模块：
;; - 面包屑导航（which-function-mode）：在顶部显示当前函数/类路径
;; - 符号高亮（symbol-overlay）：光标停留时高亮所有相同符号
;; - 彩虹括号（rainbow-delimiters）：用不同颜色区分嵌套层级
;; - 代码小地图（minimap）：右侧代码缩略图（仅 GUI）
;;
;; 性能优化：which-func 采用延迟加载，仅在 prog-mode 下激活，避免初始化开销。
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 面包屑导航 - 显示当前函数/类层级路径
;; ═════════════════════════════════════════════════════════════════════════════

;; which-function-mode 是 Emacs 内置功能，在 mode-line 显示当前函数名
;; 配合 Tree-sitter 和 LSP 可以准确识别函数/类/方法
(use-package which-func
  :defer t
  :custom
  (which-func-unknown "n/a")
  ;; 仅在编程模式中启用 which-func，避免在 dashboard/特殊 buffer 中触发 imenu 错误。
  (which-func-modes '(prog-mode))
  :config
  ;; which-function-mode 是全局模式，不能放在 prog-mode hook 中无参调用（会变成反复 toggle）。
  (which-function-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; 符号高亮 - 光标停留时高亮所有相同符号
;; ═════════════════════════════════════════════════════════════════════════════

;; 类似 JetBrains 的 Highlight Usages in File 功能
;; 光标在符号上停留 0.3 秒后自动高亮所有同名符号
(use-package symbol-overlay
  :defer t
  :hook (prog-mode . symbol-overlay-mode)
  :custom
  (symbol-overlay-idle-time 0.3)
  :config
  ;; 符号跳转快捷键（仅在 symbol-overlay-mode 下生效）
  (define-key symbol-overlay-mode-map (kbd "M-n") #'symbol-overlay-jump-next)
  (define-key symbol-overlay-mode-map (kbd "M-p") #'symbol-overlay-jump-prev))

;; ═════════════════════════════════════════════════════════════════════════════
;; 彩虹括号 - 不同颜色区分嵌套层级
;; ═════════════════════════════════════════════════════════════════════════════

;; 用不同颜色显示嵌套的括号，便于识别配对关系
;; 类似 JetBrains 的 Rainbow Brackets 插件
(use-package rainbow-delimiters
  :defer t
  :hook (prog-mode . rainbow-delimiters-mode))

(provide 'navigation)
;;; navigation.el ends here
