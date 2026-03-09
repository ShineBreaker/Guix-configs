;;; core-ui.el --- 界面与可视化体验 -*- lexical-binding: t; -*-

;;; Code:

(require 'display-line-numbers)

;; 减少干扰，保留核心信息密度。
(when (fboundp 'menu-bar-mode) (menu-bar-mode -1))
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))

(setq display-line-numbers-type 'relative)

;; 行号策略：
;; 1) 全局开启，保证编辑区稳定显示
;; 2) 在终端/文件树/仪表盘等辅助窗口豁免
(setq display-line-numbers-exempt-modes
      '(vterm-mode
        term-mode
        eshell-mode
        treemacs-mode
        dashboard-mode
        shell-mode))
(global-display-line-numbers-mode 1)

(defun my/line-number-exempt-buffer-p ()
  "判断当前 buffer 是否应该关闭行号。"
  (or (minibufferp)
      (derived-mode-p 'vterm-mode
                      'term-mode
                      'eshell-mode
                      'shell-mode
                      'treemacs-mode
                      'dashboard-mode
                      'special-mode)))

(defun my/refresh-line-number-state ()
  "根据当前 buffer 类型强制刷新行号状态。"
  (if (my/line-number-exempt-buffer-p)
      (display-line-numbers-mode -1)
    (when (or buffer-file-name
              (derived-mode-p 'prog-mode 'text-mode))
      (display-line-numbers-mode 1))))

;; 在 major-mode 变化后兜底刷新，避免被 minor mode（如你看到的 wk）覆盖。
(add-hook 'after-change-major-mode-hook #'my/refresh-line-number-state)
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

;; 不强制设定字体大小，回退到系统/原始 Emacs 字号。

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
