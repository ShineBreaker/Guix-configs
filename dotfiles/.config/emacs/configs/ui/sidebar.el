;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; sidebar.el --- 右侧功能栏 -*- lexical-binding: t; -*-

;;; Commentary:
;; 类似 VS Code 的活动栏，显示常用功能的图标入口。

;;; Code:

(when (require 'nerd-icons nil t))

(defgroup my/sidebar nil
  "右侧功能栏配置。"
  :group 'ui)

(defcustom my/sidebar-width 4
  "侧边栏宽度（字符数）。"
  :type 'integer
  :group 'my/sidebar)

(defvar my/sidebar-buffer-name "*Sidebar*"
  "侧边栏 buffer 名称。")

(defvar my/sidebar-actions
  '(("󰊢" magit-status "Git 状态")
    ("" org-agenda "Org 议程")
    ("󰃭" calendar "日历")
    ("󰝰" projectile-switch-project "切换项目")
    ("󰋗" my/show-shortcuts-help "显示帮助"))
  "侧边栏功能列表：(图标 命令 描述)。")

(defun my/sidebar-create-buffer ()
  "创建侧边栏 buffer。"
  (let ((buf (get-buffer-create my/sidebar-buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (remove-overlays)
        (insert "\n")
        (dolist (action my/sidebar-actions)
          (let* ((icon (nth 0 action))
                 (cmd (nth 1 action))
                 (desc (nth 2 action))
                 (start (point))
                 (padding (/ (- my/sidebar-width 2) 2.0)))
            (when (> padding 0)
              (insert (propertize "" 'display `(space :width ,padding))))
            (insert (propertize icon 'face '(:height 1.5)))
            (insert "\n")
            (make-button start (1- (point))
                        'action `(lambda (_) (call-interactively ',cmd))
                        'help-echo desc
                        'follow-link t)))
        (special-mode)
        (setq-local cursor-type nil)
        (setq-local mode-line-format nil)
        (setq-local line-spacing 0.6)))
    buf))

(defun my/sidebar-show ()
  "显示侧边栏。"
  (interactive)
  (let ((buf (my/sidebar-create-buffer)))
    (display-buffer buf
                    `((display-buffer-in-side-window)
                      (side . right)
                      (slot . 1)
                      (window-width . ,my/sidebar-width)
                      (window-parameters . ((no-delete-other-windows . t)
                                           (no-other-window . t)))))))

(defun my/sidebar-toggle ()
  "切换侧边栏显示。"
  (interactive)
  (let ((win (get-buffer-window my/sidebar-buffer-name)))
    (if win
        (delete-window win)
      (my/sidebar-show))))

(provide 'sidebar)
;;; sidebar.el ends here
