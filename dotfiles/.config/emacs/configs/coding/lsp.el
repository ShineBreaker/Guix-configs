;;; lsp.el --- LSP 与代码格式化 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Eglot（内置 LSP 客户端）和代码格式化工具。

;;; Code:

(require 'json)

;; Guix Home 的 tree-sitter 动态库路径
(let ((ts-dir (expand-file-name "~/.guix-home/profile/lib/tree-sitter")))
  (when (file-directory-p ts-dir)
    (setq treesit-extra-load-path (list ts-dir))))

;; 启用 tree-sitter 模式映射
(setq major-mode-remap-alist
      '((c-mode      . c-ts-mode)
        (c++-mode    . c++-ts-mode)
        (python-mode . python-ts-mode)
        (rust-mode   . rust-ts-mode)
        (java-mode   . java-ts-mode)))

;; Eldoc 配置（签名提示）
(setq eldoc-idle-delay 0.2
      eldoc-echo-area-use-multiline-p nil)

;; Eglot LSP 客户端
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
  (add-to-list 'eglot-server-programs '((c-ts-mode c++-ts-mode) . ("ccls")))
  (add-to-list 'eglot-server-programs '(python-ts-mode . ("pylsp")))
  (add-to-list 'eglot-server-programs '(rust-ts-mode . ("rust-analyzer")))
  (add-hook 'eglot-managed-mode-hook
            (lambda ()
              (when (fboundp 'eglot-inlay-hints-mode)
                (eglot-inlay-hints-mode 1)))))

;; 保存时自动格式化
(defun my/format-buffer ()
  "格式化当前缓冲区。"
  (cond
   ((derived-mode-p 'python-ts-mode 'python-mode)
    (when (executable-find "black")
      (call-process-region (point-min) (point-max) "black" t t nil "-q" "-")))
   ((derived-mode-p 'rust-ts-mode 'rust-mode)
    (when (executable-find "rustfmt")
      (call-process-region (point-min) (point-max) "rustfmt" t t nil "--emit" "stdout")))))

(add-hook 'before-save-hook
          (lambda ()
            (when (derived-mode-p 'python-ts-mode 'rust-ts-mode)
              (my/format-buffer))))

(provide 'lsp)
;;; lsp.el ends here
