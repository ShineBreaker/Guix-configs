;;; lsp-server-degradation.el --- 外部依赖缺失时的降级策略 -*- lexical-binding: t -*-
;;; Commentary:
;; 当 ripgrep/LSP/vterm 等外部工具缺失时,Emacs 不应崩溃,应该降级使用替代。
;; 这里汇总了 doom 和 spacemacs 的真实降级模式。

;;; Code:


;;
;; 1. ripgrep → ag → ack → grep 降级链
;;

;; spacemacs `dotspacemacs-search-tools` 范式
(defvar +my-search-tools '("rg" "ag" "ack" "grep")
  "Ordered list of search tools to try. First found wins.")

(defun +my-find-search-tool ()
  "Return the first available search tool from `+my-search-tools'."
  (or (cl-find-if #'executable-find +my-search-tools)
      (user-error "No search tool found. Install ripgrep, ag, or ack.")))

(defun +my/search-project (query)
  "Search project for QUERY using the best available tool."
  (interactive "sSearch: ")
  (let* ((tool (+my-find-search-tool))
         (default-directory (or (project-root (project-current))
                                default-directory))
         (cmd (pcase tool
               ("rg"   (format "rg --no-heading --line-number --color never %s" (shell-quote-argument query)))
               ("ag"   (format "ag --nogroup --noheading %s" (shell-quote-argument query)))
               ("ack"  (format "ack --nogroup --noheading %s" (shell-quote-argument query)))
               ("grep" (format "grep -RIn %s ." (shell-quote-argument query))))))
    (compilation-start cmd)))


;;
;; 2. exec-path 修复(doom env 范式)
;;

;; 简单版: 在 init 阶段补几个常见路径
(setq exec-path (append exec-path
                          '("/opt/homebrew/bin"
                            "/usr/local/bin"
                            (expand-file-name "~/.local/bin"))))

;; 完整版: 用 doom env(从用户 shell 抓所有环境变量,缓存到文件)
;; (doom env | head -20)

;; 纯 elisp 版: exec-path-from-shell(启动时调 shell,慢 100ms+)
;; 安装: use-package exec-path-from-shell
;; (when (memq window-system '(mac ns))
;;   (exec-path-from-shell-initialize))


;;
;; 3. vterm 降级(动态模块不可用)
;;

(cond
 ((and (fboundp 'module-load)
       (module-load (expand-file-name "vterm-module.so" ...)))
  ;; 用 vterm
  (use-package vterm
    :commands vterm-mode))
 (t
  ;; 退到 term/ansi-term
  (use-package term
    :commands term-mode)))


;;
;; 4. LSP server 二进制降级(doom 范式)
;;

;; doom `+lsp-optimization-mode` 范式: 启动时缓存原值,启 LSP 时调高阈值
(defvar +lsp--default-read-process-output-max nil
  "Cached value of `read-process-output-max' before LSP optimization.")
(defvar +lsp--default-gcmh-high-cons-threshold nil)
(defvar +lsp--optimization-init-p nil)

(define-minor-mode +lsp-optimization-mode
  "Deploys universal GC and IPC optimizations for `lsp-mode' and `eglot'."
  :global t
  (if +lsp-optimization-mode
      (unless +lsp--optimization-init-p
        (setq +lsp--default-read-process-output-max
              (default-value 'read-process-output-max))
        (setq-default read-process-output-max (* 1024 1024))
        (unless (fboundp 'igc-info)  ; Emacs 31+ 用 igc,旧版用 gcmh
          (setq +lsp--default-gcmh-high-cons-threshold
                (default-value 'gcmh-high-cons-threshold))
          (setq-default gcmh-high-cons-threshold
                        (* 2 +lsp--default-gcmh-high-cons-threshold))
          (when (bound-and-true-p gcmh-mode)
            (gcmh-set-high-threshold)))
        (setq +lsp--optimization-init-p t))
    (when +lsp--optimization-init-p
      (setq-default read-process-output-max +lsp--default-read-process-output-max
                    +lsp--optimization-init-p nil)
      (unless (fboundp 'igc-info)
        (setq-default gcmh-high-cons-threshold +lsp--default-gcmh-high-cons-threshold)))))


;; 客户端缺失时的硬错误检查(doom `helm/autoload/helm.el:42-73` 范式)
(defun +my/require-ripgrep ()
  "Error if ripgrep is not in PATH."
  (unless (executable-find "rg")
    (user-error "Couldn't find ripgrep in your PATH. Install via brew/apt/guix.")))


;;
;; 5. tree-sitter 四档降级(doom `set-tree-sitter!` 范式)
;;

;; 优先级: Emacs 29+ 内置 > treesit-auto > 手工 mode-hook
(cond
 ;; Emacs 29+ 内置
 ((fboundp 'treesit-available-p)
  (require 'treesit)
  (add-to-list 'treesit-language-source-alist
               '(rust "https://github.com/tree-sitter/tree-sitter-rust"))
  (add-to-list 'treesit-major-mode-remap-alist
               '(rust-mode . rust-ts-mode)))

 ;; 第三方 treesit-auto
 ((require 'treesit-auto nil t)
  (treesit-auto-install-all))

 ;; 退到 regex-based highlighting
 (t
  (use-package highlight-parentheses
    :hook (prog-mode . highlight-parentheses-mode))))


;;
;; 6. magit 不跟 global-auto-revert-mode 混用
;;

;; doom `+magit-auto-revert` 范式:
(setq +magit-auto-revert 'local  ; 't, 'local, 'nil, 或 predicate
  "Auto-revert associated buffers after Git operations.")


;;
;; 7. 整体降级函数工厂
;;

;; 范式: define一个 `+try-X` 模式,有就用,没有就降级
(defmacro +try-use (preferred fallback &rest args)
  "Try PREFERRED package; if not available, use FALLBACK."
  (declare (indent 2))
  `(condition-case nil
       (require ',preferred)
     (error
      (message "%s not available, falling back to %s"
               ',preferred ',fallback)
      (require ',fallback))))

;; 用法:
;; (defun my-completion ()
;;   (interactive)
;;   (+try-use vertico company)
;;   ...)

;;; lsp-server-degradation.el ends here
