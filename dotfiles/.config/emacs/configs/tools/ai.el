;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; core-ai.el --- AI 终端面板配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 简化的 AI 工具集成：直接在右侧打开 vterm 终端。
;; 方便运行 Claude Code、Aider 等 CLI 工具。

;;; Code:

(declare-function vterm "vterm")
(declare-function vterm-send-string "vterm")
(declare-function vterm-send-return "vterm")

(defgroup my/ai nil
  "AI 终端面板配置。"
  :group 'tools)

(defcustom my/ai-side-window-width 30
  "右侧 AI 面板宽度；默认 30 列，与左侧 Treemacs 一致。"
  :type '(choice float integer)
  :group 'my/ai)

(defun my/ai-open-panel ()
  "在右侧打开 AI 终端（vterm）。"
  (interactive)
  (let ((buf (get-buffer "*AI-Terminal*")))
    (unless (and buf (buffer-live-p buf) (get-buffer-process buf))
      ;; 使用 save-window-excursion 防止 vterm 改变窗口布局
      (save-window-excursion
        (setq buf (if (fboundp 'vterm)
                      (vterm "*AI-Terminal*")
                    (get-buffer-create "*AI-Terminal*"))))
      (with-current-buffer buf
        (unless (derived-mode-p 'vterm-mode)
          (shell buf))
        ;; 设置自动换行
        (setq-local truncate-lines nil)
        (setq-local word-wrap t)
        (visual-line-mode 1)))
    (display-buffer buf
                    `((display-buffer-in-side-window)
                      (side . right)
                      (slot . 2)
                      (window-width . ,my/ai-side-window-width)
                      (window-parameters . ((no-delete-other-windows . t)
                                            (no-other-window . nil)))))))

(provide 'core-ai)
;;; ai.el ends here
