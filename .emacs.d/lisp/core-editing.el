;;; core-editing.el --- 编辑行为与代码可读性 -*- lexical-binding: t; -*-

;;; Code:

;; 通用编辑习惯：更接近现代 IDE 的默认体验。
(setq-default indent-tabs-mode nil
              tab-width 2
              fill-column 100
              truncate-lines t
              word-wrap nil)

(electric-pair-mode 1)
(show-paren-mode 1)
(delete-selection-mode 1)
(global-auto-revert-mode 1)

(use-package ws-butler
  :hook ((text-mode . ws-butler-mode)
         (prog-mode . ws-butler-mode)))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; 复刻 Zed 的 git gutter tracked_files。
(use-package diff-hl
  :hook ((prog-mode . diff-hl-mode)
         (text-mode . diff-hl-mode)
         (dired-mode . diff-hl-dired-mode))
  :config
  (global-diff-hl-mode 1))

;; 近似 Zed inline blame：按行弹出最近提交信息。
(use-package git-messenger
  :bind (("C-c g b" . git-messenger:popup-message))
  :custom
  (git-messenger:show-detail t)
  (git-messenger:use-magit-popup t))

;; 近似 Zed sticky scroll：显示当前函数头。
(use-package stickyfunc-enhance
  :hook (prog-mode . my/enable-stickyfunc-safely)
  :config
  (semantic-mode 1))

(defun my/stickyfunc-supported-mode-p ()
  "只在语义解析稳定的语言中启用 stickyfunc。"
  (derived-mode-p 'c-mode 'c-ts-mode
                  'c++-mode 'c++-ts-mode
                  'java-mode 'java-ts-mode
                  'python-mode 'python-ts-mode
                  'rust-mode 'rust-ts-mode
                  'emacs-lisp-mode))

(defun my/enable-stickyfunc-safely ()
  "安全启用 stickyfunc；不支持或出错时静默跳过。"
  (when (and (my/stickyfunc-supported-mode-p)
             (fboundp 'semantic-stickyfunc-mode))
    (ignore-errors
      (semantic-stickyfunc-mode 1))))

(provide 'core-editing)
;;; core-editing.el ends here
