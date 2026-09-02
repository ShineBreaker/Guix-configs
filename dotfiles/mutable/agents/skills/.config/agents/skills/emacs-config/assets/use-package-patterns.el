;;; use-package-patterns.el --- 12 种常见 use-package 模式 -*- lexical-binding: t -*-
;;; Commentary:
;; 从 doom 和 spacemacs 真实代码中提炼的 use-package 模式库。
;; 每种模式都给出"何时用 / 范例 / 注意事项"。
;;
;; 用法: 复制对应块到你的 init.el 或 lisp/*.el 中。

;;; Code:


;; 模式 1: 基础懒加载(:defer t)
;; 适用: 任何"打开 Emacs 不需要立即用"的包
;; 注意: 一定要有触发器让包能"被加载",纯 :defer 而不指定 :commands 等会导致 never-loaded
(use-package rainbow-delimiters
  :defer t
  :hook (prog-mode-hook . rainbow-delimiters-mode))


;; 模式 2: 命令触发(:commands)
;; 适用: 任何 M-x 调用的命令所属的包
;; 注意: 一旦 M-x 触发命令,整个包被加载
(use-package magit
  :commands (magit-status magit-blame)
  :bind (("C-x g" . magit-status)))


;; 模式 3: 模式 hook(:hook)
;; 适用: minor-mode 所属的包
;; 注意: 必须在 hook 第一次跑的时候才加载包
(use-package hl-todo
  :hook (prog-mode . hl-todo-mode))


;; 模式 4: 文件扩展名(:mode)
;; 适用: 任何绑定到特定文件类型的包
;; 注意: 一旦打开 .org 文件就加载
(use-package markdown-mode
  :mode (("\\.md\\'" . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)))


;; 模式 5: 魔数首行(:magic)
;; 适用: 脚本文件首行匹配(如 #!/usr/bin/env python)
(use-package python-ts-mode
  :magic (".+\\.py\\'" . "python")
  :config
  (setq python-indent-offset 4))


;; 模式 6: 键位触发(:bind)
;; 适用: 任何"按某键才需要"的包
;; 注意: 第一次按该键时加载包(doom `map!` 也支持)
(use-package which-key
  :bind (("C-c h" . which-key-show-top-level))
  :config
  (which-key-mode 1))


;; 模式 7: 自定义变量(:custom)
;; 适用: 包的 defcustom 变量很多时
;; 注意: 比散落 `setq` 更可读
(use-package lsp-mode
  :custom
  (lsp-keymap-prefix "C-c l")
  (lsp-log-io nil)
  (lsp-idle-delay 0.5))


;; 模式 8: 条件加载(:when)
;; 适用: 依赖外部程序、平台、Emacs 版本、其他模块启用状态
(use-package vterm
  :when (bound-and-true-p module-file-suffix)  ; 动态模块可用
  :commands vterm-mode)


;; 模式 9: 加载后链式触发(:after)
;; 适用: 包 B 依赖包 A 的设置
;; 注意: 这是声明式的依赖,不是强制 require
(use-package lsp-ui
  :after lsp-mode
  :hook (lsp-mode . lsp-ui-mode))


;; 模式 10: prelude/init vs config 分离
;; 适用: 任何需要严格区分"包加载前/后"的场景
;; 注意: 真正"懒"的关键: 加载包内函数调用必须在 :config
(use-package counsel
  :init
  (setq counsel-find-file-ignore-regexp "\\.git/")
  :config
  (counsel-mode 1))  ; ← 这行要求包已加载,所以必须 :config


;; 模式 11: 包裹初始化(:preface)
;; 适用: 需要在 use-package 块前定义 helper 变量/函数
;; 注意: 这是 doom 扩展,vanilla use-package 没这关键字
(use-package! vertico
  :preface
  (defvar +my-vertico-crm-indicator t
    "Show CRM indicator in minibuffer prompt.")
  :init
  (when +my-vertico-crm-indicator
    (add-hook 'minibuffer-setup-hook #'vertico--add-indicator))
  :config
  (vertico-mode 1))


;; 模式 12: 自定义 defun 模式 (doom `:defun` / `:defun-when`)
;; 适用: 包提供"启用函数"而非 minor-mode
;; 注意: vanilla use-package 没这关键字,doom 扩展
(use-package! persp-mode
  :hook (doom-init-ui . persp-mode))  ; 启动期不在 init 加载,等 doom-init-ui 触发


;;; 常见错误

;; ❌ 错误 1: :init 里调用包内函数,导致 lazy 失效
(use-package projectile
  :init
  (projectile-mode 1)   ; ❌ 启动期 require 了 projectile
  :config
  (setq projectile-project-search-path '("~/projects")))

;; ✅ 正确:
(use-package projectile
  :config
  (projectile-mode 1)
  (setq projectile-project-search-path '("~/projects")))

;; ❌ 错误 2: :defer t 但没触发器
(use-package some-package
  :defer t
  :config
  (some-package-mode 1))   ; ❌ 永远不跑,因为 some-package 永远不被加载

;; ✅ 正确:
(use-package some-package
  :defer t
  :hook (after-init . some-package-mode)
  :config
  (some-package-mode 1))


;; ❌ 错误 3: 在 :init 里 require
(use-package magit
  :init
  (require 'magit-blame))   ; ❌ 强制加载

;; ✅ 正确:
(use-package magit
  :after magit
  :config
  (require 'magit-blame))   ; :config 包已加载,可 require 内部子文件

;;; use-package-patterns.el ends here
