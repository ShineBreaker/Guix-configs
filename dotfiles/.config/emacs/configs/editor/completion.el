;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; completion.el --- 补全与搜索框架 -*- lexical-binding: t; -*-

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

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; Vertico - 垂直补全界面
;; ═════════════════════════════════════════════════════════════════════════════

;; Vertico 提供简洁高效的垂直补全界面
;; 使用 :init 而非 :config 以确保立即启用
(use-package vertico
  :init
  (vertico-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Marginalia - 补全注释
;; ═════════════════════════════════════════════════════════════════════════════

;; 为补全候选项添加有用的注释信息
;; 例如：命令显示快捷键，文件显示大小和修改时间
(use-package marginalia
  :init
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
         ("C-s"   . consult-line)))      ; 当前文件搜索

;; ═════════════════════════════════════════════════════════════════════════════
;; Embark - 上下文操作
;; ═════════════════════════════════════════════════════════════════════════════

;; Embark 提供类似右键菜单的上下文操作
;; 可以对补全候选项执行各种操作
(use-package embark
  :defer t
  :bind (("C-." . embark-act)         ; 执行操作
         ("C-;" . embark-dwim)        ; 智能操作
         ("C-h B" . embark-bindings)) ; 显示所有绑定
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
  :custom
  (corfu-auto t)                      ; 自动补全
  (corfu-auto-prefix 2)               ; 输入 2 个字符后触发
  (corfu-quit-no-match 'separator)    ; 无匹配时保留输入
  (corfu-cycle t)                     ; 循环选择
  :init
  (global-corfu-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Kind-icon - 补全图标
;; ═════════════════════════════════════════════════════════════════════════════

;; 为补全候选项添加图标（仅 GUI 模式）
;; 图标可以直观显示候选项类型（函数、变量、类等）
(use-package kind-icon
  :after corfu
  :if (display-graphic-p)
  :custom
  (kind-icon-default-face 'corfu-default)
  :config
  (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

;; ═════════════════════════════════════════════════════════════════════════════
;; Ripgrep 集成
;; ═════════════════════════════════════════════════════════════════════════════

;; Ripgrep - 快速文本搜索工具
;; 需要通过 Guix 安装: guix install ripgrep
(use-package rg
  :commands rg)

(provide 'completion)
;;; completion.el ends here
