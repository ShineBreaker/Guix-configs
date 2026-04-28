;;; lib.el --- 工具函数库 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 提供通用的工具函数，供其他模块使用。
;;
;; 这个文件定义了配置系统的核心工具函数，包括：
;; - 配置文件加载函数
;; - 可执行文件检查函数
;; - daemon/client 共用的 frame hook 注册函数

;;; Code:

(eval-when-compile
  (when (locate-library "diagnostic")
    (require 'diagnostic)))

(defvar custom:configs-dir)

;; ═════════════════════════════════════════════════════════════════════════════
;; Daemon frame hook
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/register-daemon-frame-hook (function)
  "在 daemon 模式下为 FUNCTION 同时注册 frame 初始化 hook。

保留 `after-make-frame-functions' 作为通用 fallback，并在 `server'
加载后同步注册到 `server-after-make-frame-hook'，覆盖
`emacs --fg-daemon' + `emacsclient' 的常见路径。非 daemon 模式下不做事。"
  (when (daemonp)
    (add-hook 'after-make-frame-functions function)
    (with-eval-after-load 'server
      (when (boundp 'server-after-make-frame-hook)
        (add-hook 'server-after-make-frame-hook function)))))

(defun custom/unregister-daemon-frame-hook (function)
  "在 daemon 模式下移除 FUNCTION 的 frame 初始化 hook。"
  (when (daemonp)
    (remove-hook 'after-make-frame-functions function)
    (with-eval-after-load 'server
      (remove-hook 'server-after-make-frame-hook function))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 配置加载函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/load-config (category filename)
  "从 CATEGORY 目录加载 FILENAME 配置文件。

参数：
  CATEGORY - 配置类别（如 \"ui\", \"editor\", \"coding\" 等）
  FILENAME - 配置文件名（如 \"appearance.el\"）

示例：
  (custom/load-config \"ui\" \"appearance.el\")
  会加载 ~/.config/emacs/configs/ui/appearance.el"
  (let* ((module (concat category "/" filename))
         (file (expand-file-name module custom:configs-dir)))
    (if (not (file-exists-p file))
        (custom/diag "load" "跳过（文件不存在）: %s/%s" category filename)
      (custom/diag-with-context 'module module
        (custom/diag "load" "加载中：%s" module)
        (condition-case-unless-debug err
            (progn
              (load file nil t)
              (custom/diag "load" "✓ 加载成功：%s" module))
          (error
           (message "[init:load] ✗ 加载失败：%s — %s"
                    module (error-message-string err))))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 可执行文件检查
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/find-executable (command)
  "检查 COMMAND 是否存在，不存在时给出友好提示。

参数：
  COMMAND - 要检查的命令名（字符串）

返回值：
  如果命令存在，返回命令的完整路径；否则返回 nil 并显示警告

示例：
  (when (custom/find-executable \"rust-analyzer\")
    (setq lsp-rust-analyzer-server-command \"rust-analyzer\"))"
  (or (executable-find command)
      (progn
        (warn "未找到可执行文件: %s，请通过 Guix 安装" command)
        nil)))

(provide 'lib)
;;; lib.el ends here
