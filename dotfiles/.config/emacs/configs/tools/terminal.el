;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; terminal.el --- 终端模拟器 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 vterm 终端模拟器。

;;; Code:

;; Vterm（高性能终端模拟器）
(use-package vterm
  :commands vterm
  :config
  ;; 让 vterm 颜色跟随主题
  (defun my/vterm-sync-colors ()
    "同步 vterm 颜色到当前主题"
    (setq vterm-color-black   (face-attribute 'term-color-black :foreground nil t)
          vterm-color-red     (face-attribute 'term-color-red :foreground nil t)
          vterm-color-green   (face-attribute 'term-color-green :foreground nil t)
          vterm-color-yellow  (face-attribute 'term-color-yellow :foreground nil t)
          vterm-color-blue    (face-attribute 'term-color-blue :foreground nil t)
          vterm-color-magenta (face-attribute 'term-color-magenta :foreground nil t)
          vterm-color-cyan    (face-attribute 'term-color-cyan :foreground nil t)
          vterm-color-white   (face-attribute 'term-color-white :foreground nil t)))

  (my/vterm-sync-colors)
  ;; 在加载主题后同步颜色
  (advice-add 'load-theme :after (lambda (&rest _) (my/vterm-sync-colors))))

(provide 'terminal)
;;; terminal.el ends here
