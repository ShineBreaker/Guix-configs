;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

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

;; 加载主题
(use-package ef-themes
  :init
  ;; This makes the Modus commands listed below consider only the Ef
  ;; themes.  For an alternative that includes Modus and all
  ;; derivative themes (like Ef), enable the
  ;; `modus-themes-include-derivatives-mode' instead.  The manual of
  ;; the Ef themes has a section that explains all the possibilities:
  ;;
  ;; - Evaluate `(info "(ef-themes) Working with other Modus themes or taking over Modus")'
  ;; - Visit <https://protesilaos.com/emacs/ef-themes#h:6585235a-5219-4f78-9dd5-6a64d87d1b6e>
  (ef-themes-take-over-modus-themes-mode 1)
  :bind
  (("<f6>" . modus-themes-rotate)
   ("C-<f6>" . modus-themes-select)
   ("M-<f6>" . modus-themes-load-random))
  :config
  ;; All customisations here.
  (setq modus-themes-mixed-fonts t)
  (setq modus-themes-italic-constructs t)

  ;; Finally, load your theme of choice (or a random one with
  ;; `modus-themes-load-random', `modus-themes-load-random-dark',
  ;; `modus-themes-load-random-light').
  (modus-themes-load-theme 'ef-owl))

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
