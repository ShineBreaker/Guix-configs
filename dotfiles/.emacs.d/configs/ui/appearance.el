;;; appearance.el --- 界面外观配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置主题、字体、行号、模式行等视觉元素。

;;; Code:

(require 'display-line-numbers)

;; 减少干扰，保留核心信息
(when (fboundp 'menu-bar-mode) (menu-bar-mode -1))
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))

;; 相对行号
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

;; 行号豁免模式：终端、文件树、仪表盘等
(dolist (mode '(vterm-mode term-mode eshell-mode shell-mode
                treemacs-mode dashboard-mode special-mode))
  (add-hook (intern (concat (symbol-name mode) "-hook"))
            (lambda () (display-line-numbers-mode -1))))

;; 标签栏
(tab-bar-mode 1)
(setq tab-bar-show 1)

;; 终端鼠标与上下文菜单
(xterm-mouse-mode 1)
(context-menu-mode 1)

;; 光标与当前行高亮（类似 Zed）
(setq-default cursor-type 'bar)
(global-hl-line-mode 1)

;; 字体大小（1/10 pt，110=11pt）
(defcustom my/default-font-height 110
  "默认字体大小。"
  :type 'integer
  :group 'faces)

(set-face-attribute 'default nil :height my/default-font-height)

;; 窗口分割线
(setq window-divider-default-right-width 1
      window-divider-default-bottom-width 0)
(window-divider-mode 1)

;; 加载主题（themes/目录由其他应用管理）
(add-to-list 'custom-theme-load-path (expand-file-name "themes" user-emacs-directory))
(load-theme 'noctalia t)

;; 现代模式行
(use-package doom-modeline
  :hook (after-init . doom-modeline-mode)
  :custom
  (doom-modeline-height 26)
  (doom-modeline-buffer-file-name-style 'truncate-upto-project)
  (doom-modeline-project-detection 'project))

;; 迷你地图（F8 开关）
(use-package minimap
  :commands minimap-mode
  :bind ("<f8>" . minimap-mode))

(provide 'appearance)
;;; appearance.el ends here
