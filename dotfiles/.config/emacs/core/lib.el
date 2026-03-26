;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; lib.el --- 工具函数库 -*- lexical-binding: t; -*-

;;; Commentary:
;; 提供通用的工具函数，供其他模块使用。
;;
;; 这个文件定义了配置系统的核心工具函数，包括：
;; - 配置文件加载函数
;; - 可执行文件检查函数

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 配置加载函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun my/load-config (category filename)
  "从 CATEGORY 目录加载 FILENAME 配置文件。

参数：
  CATEGORY - 配置类别（如 \"ui\", \"editor\", \"coding\" 等）
  FILENAME - 配置文件名（如 \"appearance.el\"）

示例：
  (my/load-config \"ui\" \"appearance.el\")
  会加载 ~/.config/emacs/configs/ui/appearance.el

如果文件不存在，会静默跳过（不报错）。"
  (let ((file (expand-file-name
               (concat category "/" filename)
               my/configs-dir)))
    (when (file-exists-p file)
      (load file nil t))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 可执行文件检查
;; ═════════════════════════════════════════════════════════════════════════════

(defun my/executable-find-required (command)
  "检查 COMMAND 是否存在，不存在时给出友好提示。

参数：
  COMMAND - 要检查的命令名（字符串）

返回值：
  如果命令存在，返回命令的完整路径
  如果命令不存在，返回 nil 并显示警告消息

使用场景：
  在配置 LSP 服务器或外部工具前，先检查是否已安装

示例：
  (when (my/executable-find-required \"rust-analyzer\")
    (setq lsp-rust-analyzer-server-command \"rust-analyzer\"))"
  (or (executable-find command)
      (progn
        (warn "未找到可执行文件: %s，请通过 Guix 安装" command)
        nil)))

(provide 'lib)
;;; lib.el ends here
