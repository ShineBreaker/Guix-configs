;;; format.el --- 代码格式化配置（apheleia） -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 使用 apheleia 框架配置保存时自动格式化。
;;
;; 语言对应关系由 `languages.el' 集中维护，本文件只负责消费：
;; - `custom:language-apheleia-formatters'
;; - `custom:language-apheleia-mode-alist'
;;
;; 当前已接入的 formatter（基于 Guix 验证）：
;; - C / C++: clang-format
;; - Fish: fish_indent
;; - GDScript: gdscript-mode 内置 formatter（走 prefix-keymaps.el 的专属命令分发）
;; - Go: gofmt
;; - JSON / TypeScript: js-beautify
;; - Markdown / GFM: pandoc
;; - Nix: nixfmt
;; - Python: black
;; - Rust: rustfmt
;; - Shell / Bash: shfmt
;; - YAML: yq
;; - Zig: zig fmt
;;
;; 注意：apheleia 会自动检测 PATH 中的格式化器，不存在则静默跳过。
;;
;; 快捷键：
;; - `C-c t F`   切换保存时格式化开关
;; - `C-c f f`   交互式格式化（apheleia → eglot → indent-region 级联）

;;; Code:

(defvar custom:language-apheleia-formatters nil)
(defvar custom:language-apheleia-mode-alist nil)

;; ═════════════════════════════════════════════════════════════════════════════
;; apheleia 格式化框架
;; ═════════════════════════════════════════════════════════════════════════════

;; 全局格式化开关（默认开启）
(defcustom custom/format-on-save-enabled t
  "是否启用保存时自动格式化。"
  :type 'boolean
  :group 'custom)

;; 切换格式化开关
(defun custom/format-on-save-toggle ()
  "切换保存时自动格式化开关。"
  (interactive)
  (custom/diag "format" "切换保存时格式化: %s" (if custom/format-on-save-enabled "开启" "关闭"))
  (setq custom/format-on-save-enabled (not custom/format-on-save-enabled))
  ;; 更新 apheleia-mode 状态
  (if custom/format-on-save-enabled
      (apheleia-global-mode 1)
    (apheleia-global-mode -1))
  (message "保存时格式化已%s" (if custom/format-on-save-enabled "启用" "禁用")))

(use-package apheleia
  :defer t
  :config
  ;; 启用全局格式化模式
  (when custom/format-on-save-enabled
    (custom/diag "format" "启用 apheleia 全局格式化")
    (apheleia-global-mode 1))

  ;; `languages.el' 中定义的 formatter 以集中表覆盖到 Apheleia。
  (dolist (formatter custom:language-apheleia-formatters)
    (setf (alist-get (car formatter) apheleia-formatters)
          (cdr formatter)))

  (dolist (mapping custom:language-apheleia-mode-alist)
    (setf (alist-get (car mapping) apheleia-mode-alist)
          (cdr mapping))))

(provide 'format)
;;; format.el ends here
