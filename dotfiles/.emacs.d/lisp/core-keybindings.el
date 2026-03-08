;;; core-keybindings.el --- 按键体系与帮助系统 -*- lexical-binding: t; -*-

;;; Code:

;; 提前声明 Evil 选项，避免字节编译告警。
(defvar evil-want-keybinding)
(defvar evil-want-integration)
(defvar evil-undo-system)
(defvar evil-want-C-u-scroll)

(defgroup my/keymap nil
  "个人按键与编辑模式。"
  :group 'convenience)

(defcustom my/enable-vim-mode nil
  "是否启用 Evil（复刻 zed.json 的 `vim_mode: false`，默认关闭）。"
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
  (evil-mode 1))

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

;; 贴近 VSCode 的常用快捷键习惯。
(global-set-key (kbd "C-p") #'project-find-file)
(global-set-key (kbd "C-S-f") #'consult-ripgrep)
(global-set-key (kbd "C-S-b") #'consult-buffer)

(provide 'core-keybindings)
;;; core-keybindings.el ends here
