;;; completion.el --- 补全与搜索框架 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Vertico、Consult、Corfu 等现代补全框架。

;;; Code:

;; Vertico（垂直补全界面）
(use-package vertico
  :demand t
  :init
  (vertico-mode 1))

;; Marginalia（补全注释）
(use-package marginalia
  :after vertico
  :init
  (marginalia-mode 1))

;; Orderless（无序补全）
(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

;; Consult（搜索与导航）
(use-package consult
  :bind (("C-x b" . consult-buffer)
         ("M-y"   . consult-yank-pop)
         ("M-s r" . consult-ripgrep)
         ("C-s"   . consult-line)))

;; Embark（上下文操作）
(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)
         ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :after (embark consult))

;; Corfu（区域补全）
(use-package corfu
  :custom
  (corfu-auto t)
  (corfu-auto-prefix 2)
  (corfu-quit-no-match 'separator)
  (corfu-cycle t)
  :init
  (global-corfu-mode 1))

;; Kind-icon（补全图标）
(use-package kind-icon
  :after corfu
  :if (display-graphic-p)
  :custom
  (kind-icon-default-face 'corfu-default)
  :config
  (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

;; Ripgrep 集成
(use-package rg
  :commands rg)

(provide 'completion)
;;; completion.el ends here
