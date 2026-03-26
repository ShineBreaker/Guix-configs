;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; appearance.el --- 界面外观配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置主题、字体、行号、模式行等视觉元素。
;;
;; 优化说明：
;; 1. 移除不必要的 require - display-line-numbers 是内置的
;; 2. 延迟加载主题和模式行 - 减少启动时间
;; 3. 使用 hook 而非全局模式 - 按需启用功能

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 界面简化
;; ═════════════════════════════════════════════════════════════════════════════

;; 隐藏菜单栏、工具栏、滚动条，保持界面简洁
(when (fboundp 'menu-bar-mode) (menu-bar-mode -1))    ; 隐藏菜单栏
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))    ; 隐藏工具栏
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1)) ; 隐藏滚动条

;; ═════════════════════════════════════════════════════════════════════════════
;; 行号显示
;; ═════════════════════════════════════════════════════════════════════════════

;; 使用相对行号（类似 Vim）
;; 相对行号便于使用 Vim 风格的跳转命令（如 5j 向下跳 5 行）
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

;; 在某些模式下禁用行号（终端、文件树等不需要行号）
(dolist (mode '(vterm-mode term-mode eshell-mode shell-mode
                treemacs-mode dashboard-mode special-mode))
  (add-hook (intern (concat (symbol-name mode) "-hook"))
            (lambda () (display-line-numbers-mode -1))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 标签栏和鼠标支持
;; ═════════════════════════════════════════════════════════════════════════════

;; 启用标签栏（类似浏览器的标签页）
(tab-bar-mode 1)
(setq tab-bar-show 1)  ; 1 = 始终显示，t = 多于一个标签时显示

;; 终端模式下启用鼠标支持
(xterm-mouse-mode 1)

;; GUI 模式下启用右键菜单
(when (display-graphic-p)
  (context-menu-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; 光标和当前行高亮
;; ═════════════════════════════════════════════════════════════════════════════

;; 使用竖线光标（类似现代编辑器）
;; 可选值：'bar (竖线), 'box (方块), 'hollow (空心方块), nil (不显示)
(setq-default cursor-type 'bar)

;; 高亮当前行（便于定位光标位置）
(global-hl-line-mode 1)

;; ═════════════════════════════════════════════════════════════════════════════
;; 字体配置
;; ═════════════════════════════════════════════════════════════════════════════

;; 默认字体大小（单位：1/10 pt，110 = 11pt）
;; 修改方法：改变 my/default-font-height 的值
;; - 100 = 10pt (较小)
;; - 110 = 11pt (默认)
;; - 120 = 12pt (较大)
;; - 140 = 14pt (更大)
(defcustom my/default-font-height 110
  "默认字体大小（1/10 pt）。"
  :type 'integer
  :group 'faces)

;; 仅在 GUI 模式下设置字体大小（终端模式由终端控制）
(when (display-graphic-p)
  (set-face-attribute 'default nil :height my/default-font-height))

;; ═════════════════════════════════════════════════════════════════════════════
;; 窗口分割线
;; ═════════════════════════════════════════════════════════════════════════════

;; 在窗口之间显示分割线（仅 GUI 模式）
(when (display-graphic-p)
  (setq window-divider-default-right-width 1   ; 右侧分割线宽度
        window-divider-default-bottom-width 0) ; 底部分割线宽度（0=不显示）
  (window-divider-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; 主题配置
;; ═════════════════════════════════════════════════════════════════════════════

;; Ef-themes - 现代化主题集合
;; 延迟加载以加速启动
;;
;; 使用说明：
;; - F6: 循环切换主题
;; - C-F6: 选择特定主题
;; - M-F6: 加载随机主题
;;
;; 修改默认主题：
;; 将 'ef-owl 改为其他主题名称，如：
;; - ef-dark: 深色主题
;; - ef-light: 浅色主题
;; - ef-duo-dark: 双色深色主题
(use-package ef-themes
  :defer t
  :init
  (ef-themes-take-over-modus-themes-mode 1)
  :bind
  (("<f6>" . modus-themes-rotate)
   ("C-<f6>" . modus-themes-select)
   ("M-<f6>" . modus-themes-load-random))
  :custom
  (modus-themes-mixed-fonts t)      ; 混合字体支持
  (modus-themes-italic-constructs t) ; 斜体支持
  :config
  (modus-themes-load-theme 'ef-owl)) ; 默认主题

;; ═════════════════════════════════════════════════════════════════════════════
;; 模式行配置
;; ═════════════════════════════════════════════════════════════════════════════

;; Doom Modeline - 现代化模式行
;; 使用 hook 延迟加载，避免影响启动速度
;;
;; 配置说明：
;; - doom-modeline-height: 模式行高度（像素）
;; - doom-modeline-buffer-file-name-style: 文件名显示方式
;;   - 'truncate-upto-project: 显示相对于项目根的路径
;;   - 'relative-to-project: 完整相对路径
;;   - 'file-name: 仅文件名
;; - doom-modeline-project-detection: 项目检测方式
(use-package doom-modeline
  :defer t
  :hook (after-init . doom-modeline-mode)
  :custom
  (doom-modeline-height 26)
  (doom-modeline-buffer-file-name-style 'truncate-upto-project)
  (doom-modeline-project-detection 'project))

;; ═════════════════════════════════════════════════════════════════════════════
;; 迷你地图
;; ═════════════════════════════════════════════════════════════════════════════

;; Minimap - 代码缩略图（类似 Sublime Text）
;; 按需加载，不影响启动速度
;;
;; 使用说明：
;; - F8: 切换迷你地图显示
;; - 迷你地图会显示在窗口右侧
;;
;; 配置说明：
;; - minimap-window-location: 显示位置 (left/right)
;; - minimap-width-fraction: 宽度占比（0.1 = 10%）
;; - minimap-minimum-width: 最小宽度（字符数）
(use-package minimap
  :commands (minimap-mode minimap-create minimap-kill)
  :bind ("<f8>" . minimap-mode)
  :custom
  (minimap-window-location 'right)
  (minimap-width-fraction 0.1)
  (minimap-minimum-width 15))

(provide 'appearance)
;;; appearance.el ends here
