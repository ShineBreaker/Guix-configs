;;; core-dev.el --- 编程语言与工具链支持 -*- lexical-binding: t; -*-

;;; Code:

;; 编译期函数声明，减少告警。
(declare-function eglot-format-buffer "eglot")
(require 'json)

(defgroup my/dev nil
  "个人开发体验相关设置。"
  :group 'tools)

;; 复刻 Zed 自动签名提示体验。
(setq eldoc-idle-delay 0.2
      eldoc-echo-area-use-multiline-p nil)

;; Guix Home 常见 tree-sitter 动态库路径。
(let ((ts-dir (expand-file-name "~/.guix-home/profile/lib/tree-sitter")))
  (when (file-directory-p ts-dir)
    (setq treesit-extra-load-path (list ts-dir))))

(setq major-mode-remap-alist
      '((c-mode      . c-ts-mode)
        (c++-mode    . c++-ts-mode)
        (python-mode . python-ts-mode)
        (rust-mode   . rust-ts-mode)
        (java-mode   . java-ts-mode)))

(defun my/eglot-managed-mode-setup ()
  "Eglot 管理 buffer 的统一体验设置。"
  (when (fboundp 'eglot-inlay-hints-mode)
    (eglot-inlay-hints-mode 1))
  (when (fboundp 'flymake-show-diagnostics-at-end-of-line-mode)
    (flymake-show-diagnostics-at-end-of-line-mode 1)))

(use-package eglot
  :hook ((c-ts-mode . eglot-ensure)
         (c++-ts-mode . eglot-ensure)
         (python-ts-mode . eglot-ensure)
         (rust-ts-mode . eglot-ensure))
  :custom
  ;; 关闭最后一个受管 buffer 后自动回收 LSP 进程。
  (eglot-autoshutdown t)
  ;; Python LSP：启用 black / mypy，关闭重复或噪声较高的检查器。
  (eglot-workspace-configuration
   `((:pylsp . (:plugins
                (:black (:enabled t)
                 :pylsp_mypy (:enabled t :live_mode nil)
                 :rope (:enabled t)
                 :pycodestyle (:enabled ,json-false)
                 :mccabe (:enabled ,json-false)
                 :pyflakes (:enabled ,json-false))))))
  :config
  (add-to-list 'eglot-server-programs '((c-ts-mode c++-ts-mode c-mode c++-mode) . ("ccls")))
  (add-to-list 'eglot-server-programs '(python-ts-mode . ("pylsp")))
  (add-to-list 'eglot-server-programs '((rust-ts-mode rust-mode) . ("rust-analyzer")))
  (add-hook 'eglot-managed-mode-hook #'my/eglot-managed-mode-setup))

(defcustom my/format-on-save-modes
  '(python-ts-mode python-mode
    c-ts-mode c++-ts-mode c-mode c++-mode
    rust-ts-mode rust-mode)
  "保存时执行自动格式化的主模式列表。"
  :type '(repeat symbol)
  :group 'my/dev)

(defun my/eglot-managed-buffer-p ()
  "判断当前 buffer 是否被 Eglot 管理。"
  (and (boundp 'eglot--managed-mode)
       eglot--managed-mode))

(defun my/format-buffer-with-command (program args)
  "使用 PROGRAM 和 ARGS 对当前 buffer 做整缓冲区格式化。"
  (when (executable-find program)
    (let ((err-buf (get-buffer-create "*format-errors*"))
          (point-pos (point)))
      (with-current-buffer err-buf
        (erase-buffer))
      (if (zerop (apply #'call-process-region
                        (point-min) (point-max)
                        program
                        t
                        (list t err-buf)
                        nil
                        args))
          (progn
            (goto-char (min point-pos (point-max)))
            t)
        (message "[format] %s 失败，详情见 %s" program (buffer-name err-buf))
        nil))))

(defun my/format-current-buffer ()
  "按语言选择已安装工具进行格式化。"
  (cond
   ((derived-mode-p 'python-ts-mode 'python-mode)
    (or (and (my/eglot-managed-buffer-p)
             (ignore-errors (eglot-format-buffer) t))
        (my/format-buffer-with-command
         "black"
         (list "-q"
               "--stdin-filename" (or buffer-file-name "stdin.py")
               "-"))))
   ((derived-mode-p 'c-ts-mode 'c++-ts-mode 'c-mode 'c++-mode 'java-ts-mode 'java-mode)
    (my/format-buffer-with-command
     "clang-format"
     (list "--style=file"
           (format "--assume-filename=%s" (or buffer-file-name "stdin.cpp")))))
   ((derived-mode-p 'json-ts-mode 'json-mode 'js-json-mode)
    (my/format-buffer-with-command "js-beautify" '("--stdin" "--indent-size" "2" "-")))
   ((derived-mode-p 'rust-ts-mode 'rust-mode)
    (my/format-buffer-with-command "rustfmt" '("--emit" "stdout")))))

(defun my/format-buffer-on-save ()
  "在支持的语言模式中保存自动格式化。"
  (when (apply #'derived-mode-p my/format-on-save-modes)
    (my/format-current-buffer)))

(add-hook 'before-save-hook #'my/format-buffer-on-save)

(use-package geiser
  :custom
  (geiser-active-implementations '(guile))
  :hook (scheme-mode . geiser-mode))

(use-package sly
  :custom
  (inferior-lisp-program "sbcl"))

(provide 'core-dev)
;;; core-dev.el ends here
