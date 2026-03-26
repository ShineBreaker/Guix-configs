;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; lsp.el --- LSP 与代码格式化 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Eglot（内置 LSP 客户端）和代码格式化工具。
;;
;; LSP 服务器安装：
;; - Python: guix install python-lsp-server
;; - C/C++: guix install ccls
;; - Rust: guix install rust-analyzer
;;
;; 格式化工具安装：
;; - Python: guix install python-black
;; - Rust: rustfmt (随 Rust 工具链安装)

;;; Code:

(require 'json)

;; ═════════════════════════════════════════════════════════════════════════════
;; Tree-sitter 配置
;; ═════════════════════════════════════════════════════════════════════════════

;; Tree-sitter 提供更准确的语法高亮和代码分析
;; Guix Home 的 tree-sitter 动态库路径
(let ((ts-dir (expand-file-name "~/.guix-home/profile/lib/tree-sitter")))
  (when (file-directory-p ts-dir)
    (setq treesit-extra-load-path (list ts-dir))))

;; 启用 tree-sitter 模式映射（自动使用 *-ts-mode）
(setq major-mode-remap-alist
      '((c-mode      . c-ts-mode)
        (c++-mode    . c++-ts-mode)
        (python-mode . python-ts-mode)
        (rust-mode   . rust-ts-mode)
        (java-mode   . java-ts-mode)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Eldoc 配置
;; ═════════════════════════════════════════════════════════════════════════════

;; Eldoc 在 minibuffer 显示函数签名和文档
(setq eldoc-idle-delay 0.2              ; 延迟 0.2 秒显示
      eldoc-echo-area-use-multiline-p nil) ; 单行显示

;; ═════════════════════════════════════════════════════════════════════════════
;; Eglot LSP 客户端
;; ═════════════════════════════════════════════════════════════════════════════

;; Eglot 是 Emacs 内置的 LSP 客户端（Emacs 29+）
;; 使用 hook 自动启动 LSP 服务器
;;
;; 配置说明：
;; - eglot-autoshutdown: 关闭最后一个缓冲区时自动关闭 LSP 服务器
;; - eglot-workspace-configuration: LSP 服务器特定配置
(use-package eglot
  :hook ((c-ts-mode . eglot-ensure)
         (c++-ts-mode . eglot-ensure)
         (python-ts-mode . eglot-ensure)
         (rust-ts-mode . eglot-ensure))
  :custom
  (eglot-autoshutdown t)
  (eglot-workspace-configuration
   `((:pylsp . (:plugins
                (:black (:enabled t)
                 :pylsp_mypy (:enabled t :live_mode nil)
                 :rope (:enabled t)
                 :pycodestyle (:enabled ,json-false)
                 :mccabe (:enabled ,json-false)
                 :pyflakes (:enabled ,json-false))))))
  :config
  ;; 配置 LSP 服务器命令
  (add-to-list 'eglot-server-programs '((c-ts-mode c++-ts-mode) . ("ccls")))
  (add-to-list 'eglot-server-programs '(python-ts-mode . ("pylsp")))
  (add-to-list 'eglot-server-programs '(rust-ts-mode . ("rust-analyzer")))

  ;; 启用 inlay hints（内联提示）
  (add-hook 'eglot-managed-mode-hook
            (lambda ()
              (when (fboundp 'eglot-inlay-hints-mode)
                (eglot-inlay-hints-mode 1)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 代码格式化
;; ═════════════════════════════════════════════════════════════════════════════

;; 保存时自动格式化代码
;; 支持 Python (black) 和 Rust (rustfmt)
;;
;; 使用说明：
;; - Python: 需要安装 black (guix install python-black)
;; - Rust: rustfmt 随 Rust 工具链自动安装
(defun my/format-buffer ()
  "格式化当前缓冲区。
根据当前模式选择合适的格式化工具。"
  (cond
   ((derived-mode-p 'python-ts-mode 'python-mode)
    (when (executable-find "black")
      (call-process-region (point-min) (point-max) "black" t t nil "-q" "-")))
   ((derived-mode-p 'rust-ts-mode 'rust-mode)
    (when (executable-find "rustfmt")
      (call-process-region (point-min) (point-max) "rustfmt" t t nil "--emit" "stdout")))))

;; 保存前自动格式化
(add-hook 'before-save-hook
          (lambda ()
            (when (derived-mode-p 'python-ts-mode 'rust-ts-mode)
              (my/format-buffer))))

(provide 'lsp)
;;; lsp.el ends here
