;;; lsp.el --- LSP 客户端 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 Eglot（内置 LSP 客户端）和 Tree-sitter 语法解析。
;;
;; 设计原则：
;; - LSP 服务器必须先通过 Guix 安装（参考 languages.el 中的配置）
;; - 使用 custom/find-executable 检查可执行文件是否存在
;; - 找不到 LSP 服务器时发出警告而非静默失败
;;
;; LSP 服务器安装示例：
;; - Python: guix install python-lsp-server
;; - C/C++: guix install ccls
;; - Rust: guix install rust-analyzer
;; - Java: guix install jdtls-bin（需要 jeans 频道）
;;
;; Troubleshooting：
;; - LSP 无法启动 → 检查 emacs.scm 确保已安装对应服务器，用 which 验证 PATH
;; - 配合 flycheck.el 使用，统一处理诊断（禁用 flymake 后端）
;; - eglot-x 提供 LSP 协议扩展（snippet TextEdit、编码协商、额外引用方法等）

;;; Code:

(require 'json)

;; 这些变量由 languages.el 统一维护；此处仅声明，避免单独加载 lsp.el 时出现警告。
(defvar custom:language-treesit-remaps nil)
(defvar custom:language-eglot-auto-modes nil)
(defvar custom:language-eglot-server-programs nil)

(defun custom/eglot-server-available-p (mode)
  "判断 MODE 对应的 Eglot server 当前是否可用。"
  (let* ((lookup (ignore-errors (eglot--lookup-mode mode)))
         (contact (cdr-safe lookup)))
    (cond
     ((null contact) nil)
     ;; GDScript 通过 Godot 提供的 TCP 语言服务器接入，不依赖额外 CLI。
     ((eq mode 'gdscript-mode) t)
     ((functionp contact)
      (condition-case nil
          (progn
            (funcall contact nil nil)
            t)
        (error nil)))
     ((and (consp contact)
           (stringp (car contact))
           (numberp (cadr contact)))
      t)
     ((and (consp contact)
           (stringp (car contact)))
      (or (file-executable-p (car contact))
          (executable-find (car contact))))
     (t t))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Tree-sitter 配置
;; ═════════════════════════════════════════════════════════════════════════════

;; Tree-sitter 提供更准确的语法高亮和代码分析
(when (file-directory-p custom:tree-sitter-lib-dir)
  (setq treesit-extra-load-path (list custom:tree-sitter-lib-dir)))

;; 启用 tree-sitter 模式映射（自动使用 *-ts-mode）
;; 语言覆盖优先：只要目标 *-ts-mode 在当前 Emacs 中可用，就注册 remap。
(defun custom/register-major-mode-remap (source target)
  "当 TARGET 可用时，将 SOURCE 自动 remap 到 TARGET。"
  (when (fboundp target)
    (add-to-list 'major-mode-remap-alist (cons source target))))

(dolist (mapping custom:language-treesit-remaps)
  (custom/register-major-mode-remap (car mapping) (cdr mapping)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Eldoc 配置
;; ═════════════════════════════════════════════════════════════════════════════

;; Eldoc 在 minibuffer 显示函数签名和文档
(setq eldoc-echo-area-use-multiline-p nil) ; 单行显示

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
  :custom
  (eglot-autoshutdown t)
  (eglot-workspace-configuration
   `((:pylsp . (:plugins
                (:black (:enabled t)
                 :pylsp_mypy (:enabled t :live_mode nil)
                 :rope (:enabled t)
                 :pycodestyle (:enabled ,json-false)
                 :mccabe (:enabled ,json-false)
                 :pyflakes (:enabled ,json-false))))
     ;; Java jdtls 配置：JAVA_HOME 通过 env.el 的 custom/detect-java-home 检测
     ;; jdtls 期望 workspace/didChangeConfiguration 中 settings.java.home
     ;; 参考：https://github.com/eclipse-jdtls/eclipse.jdt.ls/issues/3430
     ,@(when-let ((java-home (and (require 'env nil t)
                                   (fboundp 'custom/detect-java-home)
                                   (custom/detect-java-home))))
         (list (cons :java (list :home java-home))))))
  :config
  ;; 配置 LSP 服务器命令
  ;; 注意：eglot 已内置 java-mode/java-ts-mode 的 jdtls 专用支持，
  ;; 包含工作区目录等必要设置。
  ;;
  ;; jdtls 增强：通过 advice 在 eglot 内置的 initializationOptions 基础上
  ;; 追加 Java 专属选项。保留 eglot-alternatives 动态检测和工作区目录推断，
  ;; 同时启用 class 文件内容支持（查看依赖库反编译源码）。
  ;; 参考：https://github.com/eclipse-jdtls/eclipse.jdt.ls
  (defun custom/eglot-java-init-options (orig-fn server)
    "为 jdtls 追加 extendedClientCapabilities。
仅对 java-mode/java-ts-mode buffer 生效，其他语言透传。"
    (let ((base (funcall orig-fn server)))
      (if (derived-mode-p 'java-mode 'java-ts-mode)
          (append base
                  `(:extendedClientCapabilities
                    (:classFileContentsSupport t
                     :overrideMethodsPromptEnabled t)))
        base)))
  (advice-add 'eglot-initialization-options :around
              #'custom/eglot-java-init-options)
  (dolist (prog custom:language-eglot-server-programs)
    (let ((modes (car prog))
          (cmd (cdr prog)))
      (custom/diag "lsp" "LSP 服务器检测: %s=%s"
                   (if (listp modes) (car modes) modes)
                   (executable-find (car cmd)))
      (add-to-list 'eglot-server-programs prog)))

  ;; 自动启用 LSP 的 major mode 由 languages.el 集中维护。
  ;; 仅在本机能解析到可用 server 时才注册 hook，避免无意义报错。
  (dolist (mode custom:language-eglot-auto-modes)
    (if (custom/eglot-server-available-p mode)
        (progn
          (custom/diag "lsp" "启用 Eglot 自动接入: %s" mode)
          (add-hook (intern (format "%s-hook" mode)) #'eglot-ensure))
      (custom/diag "lsp" "跳过 Eglot 自动接入（未检测到 server）: %s" mode)))

  ;; 启用 inlay hints（内联提示）
  (add-hook 'eglot-managed-mode-hook
            (lambda ()
              (custom/diag "lsp" "Eglot 模式激活: server=%s, buffer=%s"
                           (and (eglot-current-server) (eglot-project (eglot-current-server)))
                           (current-buffer))
              (when (fboundp 'eglot-inlay-hints-mode)
                (eglot-inlay-hints-mode 1))))

  ;; LSP 服务器初始化完成
  (add-hook 'eglot-server-initialized-hook
            (lambda (server)
              (custom/diag "lsp" "LSP 服务器已连接: %s" server))))

;; ═════════════════════════════════════════════════════════════════════════════
;; eglot-x — LSP 协议扩展
;; ═════════════════════════════════════════════════════════════════════════════

;; eglot-x 为 Eglot 添加非标准 LSP 协议扩展支持：
;; - snippet TextEdit：支持代码操作中的占位符替换
;; - 编码协商：与服务器协商最优位置编码（utf-32/utf-16）
;; - 额外引用方法：跳转到声明/实现/类型定义（C-c l x d/i/t）
;; - 服务器状态：在 mode-line 显示 LSP 服务器状态
;; - hover 动作：Eldoc 文档中显示可点击操作
;; - 彩色诊断：诊断消息中显示 ANSI 颜色
;; 所有扩展默认启用，可通过 M-x customize-group RET eglot-x RET 调整
(with-eval-after-load 'eglot
  (when (require 'eglot-x nil t)
    (eglot-x-setup)
    (custom/diag "lsp" "eglot-x 协议扩展已启用")))

(provide 'lsp)
;;; lsp.el ends here
