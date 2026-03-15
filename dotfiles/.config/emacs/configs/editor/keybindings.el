;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; keybindings.el --- 键位绑定与 Evil 模式 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Evil（Vim 模拟）和全局键位绑定。
;; 保留 Emacs 原生操作的学习价值，提供 Vim/Emacs 双模式切换。
;;
;; 键位设计：
;; - 主要使用 Leader 键（SPC）减少 Ctrl 键依赖（见 leader.el）
;; - 保留部分常用 Ctrl 快捷键作为备选（兼容 Emacs 状态）

;;; Code:

;; 启用 CUA 模式
(cua-mode 1)

;; 禁用选中即替换行为
(setq cua-delete-selection nil)

;; Evil 预配置（必须在加载前设置）
(eval-and-compile
  (setq evil-want-keybinding nil      ; 由 evil-collection 接管
        evil-want-integration t
        evil-undo-system 'undo-redo   ; 使用 Emacs 28+ 的 undo-redo
        evil-want-C-u-scroll t))      ; C-u 向上滚动

;; Evil 模式（Vim 模拟）
(use-package evil
  :demand t
  :config
  (evil-mode 1)
  ;; Vim/Emacs 双状态切换
  ;; C-c v e -> Emacs 状态，C-c v v -> Vim 普通状态
  (global-set-key (kbd "C-c v e") #'evil-emacs-state)
  (global-set-key (kbd "C-c v v") #'evil-normal-state))

;; Evil Collection（为各种模式提供 Evil 键绑定）
(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

;; Which-key（键位提示）
(use-package which-key
  :demand t
  :config
  (which-key-mode 1)
  (setq which-key-idle-delay 0.3))

;; Helpful（更好的帮助系统）
(use-package helpful
  :bind (([remap describe-function] . helpful-callable)
         ([remap describe-command]  . helpful-command)
         ([remap describe-variable] . helpful-variable)
         ([remap describe-key]      . helpful-key)))

;; 智能复制：有选区复制选区，无选区复制当前行
(defun my/copy-dwim ()
  "智能复制。"
  (interactive)
  (if (use-region-p)
      (kill-ring-save (region-beginning) (region-end))
    (kill-ring-save (line-beginning-position) (line-beginning-position 2))
    (message "已复制当前行")))

;; 类 VS Code 快捷键
(global-set-key (kbd "C-p") #'project-find-file)       ; 项目内查找文件
(global-set-key (kbd "C-S-f") #'consult-ripgrep)       ; 全文搜索
(global-set-key (kbd "C-S-b") #'consult-buffer)        ; 切换缓冲区
(global-set-key (kbd "C-S-c") #'my/copy-dwim)          ; 智能复制
(global-set-key (kbd "C-S-v") #'yank)                  ; 粘贴

;; 覆盖 Emacs 默认快捷键
;; C-s 原本是 isearch-forward，现在改为保存文件
(global-set-key (kbd "C-s") #'save-buffer)
;; C-f 原本是 forward-char，现在改为查找当前文件
(global-set-key (kbd "C-f") #'consult-line)

;; Alt + 方向键切换窗口（覆盖可能的其他绑定）
(windmove-default-keybindings 'meta)

;; 确保 Evil 模式下也能使用这些快捷键
(with-eval-after-load 'evil
  ;; 在插入状态下也能使用 C-s 保存
  (define-key evil-insert-state-map (kbd "C-s") #'save-buffer)
  (define-key evil-insert-state-map (kbd "C-f") #'consult-line)
  ;; 在普通状态下也能使用（覆盖 Evil 默认的 C-f）
  (define-key evil-normal-state-map (kbd "C-s") #'save-buffer)
  (define-key evil-normal-state-map (kbd "C-f") #'consult-line))

(provide 'keybindings)
;;; keybindings.el ends here
