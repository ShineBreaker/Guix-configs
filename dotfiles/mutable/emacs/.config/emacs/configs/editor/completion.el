;;; completion.el --- 补全与搜索框架 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 Vertico、Consult、Corfu 等现代补全框架。
;;
;; 补全系统架构：
;; - Vertico: 垂直补全界面（替代 Ivy/Helm）
;; - Marginalia: 为补全项添加注释信息
;; - Orderless: 无序模糊匹配
;; - Consult: 增强的搜索和导航命令
;; - Embark: 上下文操作菜单
;; - Corfu: 代码补全弹窗（替代 Company）
;; - Cape: 为 CAPF 体系补充路径补全等额外来源
;; - corfu-doc: 补全弹窗中显示候选文档
;; - consult-eglot: 通过 Consult 搜索 Eglot 符号
;; - consult-flycheck: 通过 Consult 浏览 Flycheck 错误
;;
;; Per-frame 初始化策略：
;; 为适配 daemon/client 架构，所有 display-dependent（图标、childframe 修复）
;; 设置均通过 `custom/setup-completion-display` 在新 frame 创建时应用。
;;
;; 快捷键约定：
;; - `C-s` 保留为保存，更贴近 Windows / IDE 常见习惯
;; - `C-f` 用于当前缓冲区搜索
;; - `M-s` 保留给搜索分组前缀
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; Vertico - 垂直补全界面
;; ═════════════════════════════════════════════════════════════════════════════

;; Vertico 提供简洁高效的垂直补全界面
;; 使用 :config，确保包加载后再启用 minor mode
(use-package vertico
  :config
  (vertico-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Marginalia - 补全注释
;; ═════════════════════════════════════════════════════════════════════════════

;; 为补全候选项添加有用的注释信息
;; 例如：命令显示快捷键，文件显示大小和修改时间
(use-package marginalia
  :config
  (marginalia-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Orderless - 无序补全
;; ═════════════════════════════════════════════════════════════════════════════

;; 支持空格分隔的无序模糊匹配
;; 例如：输入 "buf swi" 可以匹配 "switch-to-buffer"
(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Consult - 搜索与导航增强
;; ═════════════════════════════════════════════════════════════════════════════

;; Consult 提供增强的搜索、导航和预览功能
;; 延迟加载，通过快捷键触发
(use-package consult
  :defer t
  :bind (("C-x b" . consult-buffer)      ; 切换缓冲区（带预览）
         ("M-y"   . consult-yank-pop)    ; 粘贴历史
         ("M-s r" . consult-ripgrep)     ; 项目搜索
         ("C-f"   . consult-line)))      ; 当前文件搜索

;; ═════════════════════════════════════════════════════════════════════════════
;; Embark - 上下文操作
;; ═════════════════════════════════════════════════════════════════════════════

;; Embark 提供类似右键菜单的上下文操作
;; 可以对补全候选项执行各种操作
;; 由于 `C-h` 已被保留给左移，Embark 绑定列表改挂到 `C-c h B`。
(use-package embark
  :defer t
  :bind (("C-." . embark-act)         ; 执行操作
         ("C-;" . embark-dwim)        ; 智能操作
         ("C-c h B" . embark-bindings)) ; 显示当前上下文绑定
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

;; Embark 与 Consult 集成
(use-package embark-consult
  :after (embark consult)
  :defer t)

;; ═════════════════════════════════════════════════════════════════════════════
;; Corfu - 代码补全弹窗
;; ═════════════════════════════════════════════════════════════════════════════

;; Corfu 提供轻量级的代码补全界面
;; 延迟 0.2 秒加载以加速启动
;;
;; 配置说明：
;; - corfu-auto: 自动弹出补全
;; - corfu-auto-prefix: 输入几个字符后触发补全
;; - corfu-quit-no-match: 无匹配时的行为
;; - corfu-cycle: 循环选择候选项
(use-package corfu
  :defer 0.2
  :bind (:map corfu-map
              ("TAB" . corfu-insert)
              ("<tab>" . corfu-insert))
  :custom
  (corfu-auto t)                      ; 自动补全
  (corfu-auto-prefix 2)               ; 输入 2 个字符后触发
  (corfu-quit-no-match 'separator)    ; 无匹配时保留输入
  (corfu-cycle t)                     ; 循环选择
  :config
  (global-corfu-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Cape - 为 CAPF 增强路径补全
;; ═════════════════════════════════════════════════════════════════════════════

;; 使用 `cape-file' 为字符串中的路径提供补全，保持与 Corfu/Eglot 的 CAPF 架构一致。
;; 通过 buffer-local 方式追加到 `completion-at-point-functions'，尽量不干扰已有
;; LSP / major-mode CAPF，只在它们给不出候选时兜底。
(use-package cape
  :defer t
  :commands (cape-file))

(defun custom/setup-path-completion ()
  "为当前缓冲区追加路径补全 CAPF。"
  (when (fboundp 'cape-file)
    (add-hook 'completion-at-point-functions #'cape-file t t)))

(add-hook 'prog-mode-hook #'custom/setup-path-completion)
(add-hook 'conf-mode-hook #'custom/setup-path-completion)

(with-eval-after-load 'eglot
  (add-hook 'eglot-managed-mode-hook #'custom/setup-path-completion))

;; ═════════════════════════════════════════════════════════════════════════════
;; Corfu 文档预览 - 在补全弹窗旁边显示候选文档
;; ═════════════════════════════════════════════════════════════════════════════

;; corfu-popupinfo 在补全弹窗旁显示文档详细信息
;; 默认不自动显示文档；仅通过显式动作（如 M-d / 右键菜单）打开
(use-package corfu-popupinfo
  :after corfu
  :bind (:map corfu-map
              ("M-d" . corfu-popupinfo-toggle))
  :custom
  (corfu-popupinfo-delay 0.5)
  :config
  ;; JetBrains 风格：默认仅显示候选列表，文档按需手动打开
  (corfu-popupinfo-mode -1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Kind-icon - 补全图标
;; ═════════════════════════════════════════════════════════════════════════════

;; 为补全候选项添加图标（仅 GUI 模式）
;; 图标可以直观显示候选项类型（函数、变量、类等）
(use-package kind-icon
  :commands (kind-icon-margin-formatter)
  :init
  (setq kind-icon-default-face 'corfu-default))

;; 终端模式下使用 Nerd Font 文字图标作为补全类型标记
;; 定义部分（无 display 依赖，可安全放在顶层）
(defvar custom--corfu-terminal-kind-icons
  '((file . "󰈔") (folder . "󰉋") (function . "󰊕") (variable . "󰀫")
    (module . "󰏗") (interface . "󰡧") (keyword . "󰌋") (method . "󰊕")
    (property . "󰜢") (unit . "󰑘") (value . "󰎠") (enum . "󰕘")
    (operator . "󰆕") (class . "󰌗") (struct . "󰌗") (type-parameter . "󰊄")
    (snippet . "󰘍") (color . "󰏘") (reference . "󰈇") (text . "󰉿")
    (event . "󰉁") (constant . "󰏿") (enum-member . "󰀬")
    (t . "󰀫"))
  "补全类型到 Nerd Font 图标的映射表。")

(defun custom--corfu-terminal-margin-formatter (metadata)
  "终端模式下使用 Nerd Font 图标格式化 Corfu 边距。"
  (let* ((kind (or (completion-metadata-get metadata 'company-kind)
                   (completion-metadata-get metadata 'kind)))
         (icons custom--corfu-terminal-kind-icons))
    (lambda (candidate)
      (let* ((kind-sym (and kind (funcall kind candidate)))
             (kind-item (or kind-sym t))
             (icon (or (cdr (assq kind-item icons)) (cdr (assq t icons)))))
        (propertize (concat " " icon " ") 'face 'corfu-default)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Per-frame 补全显示设置（daemon 安全）
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/setup-completion-display (&optional frame)
  "根据 FRAME 的 display 类型设置补全框架的显示相关配置。
GUI 模式：应用 PGTK childframe 修复。
终端模式：启用 corfu-terminal 和 Nerd Font 图标。"
  (with-selected-frame (or frame (selected-frame))
    (with-eval-after-load 'corfu
      (if (display-graphic-p)
          (progn
            ;; GUI: PGTK/Wayland 修复——childframe 位置偏移
            (when (boundp 'x-gtk-resize-child-frames)
              (setq x-gtk-resize-child-frames 'resize-mode))
            (when (bound-and-true-p corfu-terminal-mode)
              (corfu-terminal-mode -1))
            (setq corfu-margin-formatters
                  (when (and (locate-library "kind-icon")
                             (require 'kind-icon nil t))
                    '(kind-icon-margin-formatter))))
        ;; 终端: corfu-terminal + Nerd Font 图标
        (when (require 'corfu-terminal nil t)
          (corfu-terminal-mode 1))
        (setq corfu-margin-formatters
              '(custom--corfu-terminal-margin-formatter))))))

;; standalone 模式下直接初始化（daemon 模式由 frame hook 触发）
(unless (daemonp)
  (custom/setup-completion-display))

(custom/register-daemon-frame-hook #'custom/setup-completion-display)

;; ═════════════════════════════════════════════════════════════════════════════
;; 诊断工具（调试用，使用 diagnostic.el 框架）
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/debug-completion ()
  "诊断补全系统状态，使用 diagnostic.el 框架输出报告。"
  (interactive)
  (if (fboundp 'custom/diag-report)
      (let ((items
             (list
              ;; 环境
              (cons "display-graphic-p" (display-graphic-p))
              (cons "window-system" window-system)
              (cons "Emacs version" emacs-version)
              ;; Corfu 状态
              (cons "global-corfu-mode" global-corfu-mode)
              (cons "corfu-auto" corfu-auto)
              (cons "corfu-auto-prefix" corfu-auto-prefix)
              (cons "corfu-cycle" corfu-cycle)
              (cons "corfu-quit-no-match" corfu-quit-no-match)
              (cons "corfu-min-width" corfu-min-width)
              (cons "corfu-max-width" corfu-max-width)
              (cons "corfu-count" corfu-count)
              (cons "corfu-scroll-margin" corfu-scroll-margin)
              (cons "corfu-terminal-mode" (if (boundp 'corfu-terminal-mode)
                                              corfu-terminal-mode "not bound"))
              ;; 当前缓冲区
              (cons "major-mode" major-mode)
              (cons "buffer-file-name" (or buffer-file-name "nil"))
              ;; Eglot 状态
              (cons "eglot--managed-mode" (if (boundp 'eglot--managed-mode)
                                              eglot--managed-mode "not bound"))
              ;; 补全风格
              (cons "completion-styles" completion-styles))))
        (custom/diag-report "Completion" items)
        ;; 额外输出 capf 测试结果到 Messages
        (let* ((capf-result (completion-at-point))
               (has-capf (and capf-result (not (eq capf-result t)))))
          (if has-capf
              (message "[diag:completion] capf 测试: 有补全数据")
            (message "[diag:completion] capf 测试: 无补全数据"))))
    (message "custom/diag-report 不可用，请先加载 diagnostic.el")))

;; ═════════════════════════════════════════════════════════════════════════════
;; Corfu-doc - 补全文档弹窗
;; ═════════════════════════════════════════════════════════════════════════════

;; 在 Corfu 补全弹窗旁显示当前候选的文档字符串
;; GUI 模式使用 corfu-doc childframe，终端使用 corfu-doc-terminal
(use-package corfu-doc
  :after corfu
  :defer t
  :commands (corfu-doc-mode corfu-doc-toggle)
  :bind (:map corfu-map
              ("M-d" . corfu-doc-toggle)
              ("C-M-n" . corfu-doc-scroll-up)
              ("C-M-p" . corfu-doc-scroll-down))
  :custom
  (corfu-doc-max-width 70)
  (corfu-doc-max-height 20)
  :config
  ;; 默认关闭，按 M-d 手动切换（JetBrains 风格）
  (corfu-doc-mode -1))

;; 终端下 corfu-doc 的适配层
(use-package corfu-doc-terminal
  :after corfu-doc
  :defer t)

;; ═════════════════════════════════════════════════════════════════════════════
;; Consult-eglot - Eglot 符号搜索
;; ═════════════════════════════════════════════════════════════════════════════

;; 通过 Consult 界面搜索 Eglot/LSP 管理的项目符号
(use-package consult-eglot
  :after (consult eglot)
  :defer t
  :commands (consult-eglot-symbols)
  :bind (("M-s e" . consult-eglot-symbols)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Consult-flycheck - Flycheck 错误浏览
;; ═════════════════════════════════════════════════════════════════════════════

;; 通过 Consult 界面浏览和跳转 Flycheck 诊断
(use-package consult-flycheck
  :after (consult flycheck)
  :defer t
  :commands (consult-flycheck)
  :bind (("M-s f" . consult-flycheck)))

(provide 'completion)
;;; completion.el ends here
