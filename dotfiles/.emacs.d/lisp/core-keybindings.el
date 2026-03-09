;;; core-keybindings.el --- 按键体系与帮助系统 -*- lexical-binding: t; -*-

;;; Code:

;; 提前声明 Evil 选项，避免字节编译告警。
(defvar evil-want-keybinding)
(defvar evil-want-integration)
(defvar evil-undo-system)
(defvar evil-want-C-u-scroll)
(declare-function evil-emacs-state "evil")
(declare-function evil-normal-state "evil")

(defgroup my/keymap nil
  "个人按键与编辑模式。"
  :group 'convenience)

(defcustom my/enable-vim-mode t
  "是否启用 Evil（默认开启，提供 Vim/Emacs 双编辑状态切换）。"
  :type 'boolean
  :group 'my/keymap)

(eval-and-compile
  (setq evil-want-keybinding nil
        evil-want-integration t
        evil-undo-system 'undo-redo
        evil-want-C-u-scroll t))

(use-package evil
  :if my/enable-vim-mode
  :demand t
  :config
  (evil-mode 1)
  ;; Vim/Emacs 双状态切换：
  ;; C-c v e -> Emacs 编辑状态，C-c v v -> Vim 普通状态。
  (global-set-key (kbd "C-c v e") #'evil-emacs-state)
  (global-set-key (kbd "C-c v v") #'evil-normal-state))

(use-package evil-collection
  :if my/enable-vim-mode
  :after evil
  :config
  (evil-collection-init))

(use-package which-key
  :demand t
  :config
  (which-key-mode 1)
  (setq which-key-idle-delay 0.3))

(use-package helpful
  :bind (([remap describe-function] . helpful-callable)
         ([remap describe-command]  . helpful-command)
         ([remap describe-variable] . helpful-variable)
         ([remap describe-key]      . helpful-key)))

(defun my/copy-dwim ()
  "智能复制：有选区复制选区，无选区复制当前行。"
  (interactive)
  (if (use-region-p)
      (kill-ring-save (region-beginning) (region-end))
    (kill-ring-save (line-beginning-position)
                    (line-beginning-position 2))
    (message "已复制当前行")))

;; 贴近 VSCode 的常用快捷键习惯。
(global-set-key (kbd "C-p") #'project-find-file)
(global-set-key (kbd "C-S-f") #'consult-ripgrep)
(global-set-key (kbd "C-S-b") #'consult-buffer)
(global-set-key (kbd "C-S-c") #'my/copy-dwim)
(global-set-key (kbd "C-S-v") #'yank)

(provide 'core-keybindings)
;;; core-keybindings.el ends here
