;;; core-ui.el --- 界面与可视化体验 -*- lexical-binding: t; -*-

;;; Code:

(require 'display-line-numbers)

;; 减少干扰，保留核心信息密度。
(when (fboundp 'menu-bar-mode) (menu-bar-mode -1))
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))

(global-display-line-numbers-mode 1)
(setq display-line-numbers-type 'relative)
(tab-bar-mode 1)
(setq tab-bar-show 1)

;; 终端可用鼠标与上下文菜单。
(xterm-mouse-mode 1)
(context-menu-mode 1)

;; 复刻 Zed 的光标与当前行高亮风格。
(setq-default cursor-type 'bar)
(global-hl-line-mode 1)

;; 视觉分隔更接近 Zed pane 边界。
(setq window-divider-default-right-width 2
      window-divider-default-bottom-width 1)
(window-divider-mode 1)

;; GUI 下尽量贴近 zed.json 的字号设置。
(when (display-graphic-p)
  (set-face-attribute 'default nil :height 140 :weight 'normal)
  (set-face-attribute 'mode-line nil :height 150 :weight 'medium)
  (set-face-attribute 'mode-line-inactive nil :height 150 :weight 'medium))

;; 主题加载。
(add-to-list 'custom-theme-load-path (expand-file-name "themes" user-emacs-directory))
(load-theme 'noctalia t)

;; 更现代、信息清晰的 mode-line。
(use-package doom-modeline
  :hook (after-init . doom-modeline-mode)
  :custom
  (doom-modeline-height 26)
  (doom-modeline-buffer-file-name-style 'truncate-upto-project)
  (doom-modeline-project-detection 'project))

(use-package dashboard
  :custom
  (dashboard-startup-banner 'official)
  (dashboard-set-navigator t)
  (dashboard-items '((recents   . 10)
                     (projects  . 8)
                     (bookmarks . 8)))
  :config
  (dashboard-setup-startup-hook))

;; 复刻 Zed minimap（F8 开关）。
(use-package minimap
  :commands (minimap-mode)
  :bind (("<f8>" . minimap-mode)))

(provide 'core-ui)
;;; core-ui.el ends here
