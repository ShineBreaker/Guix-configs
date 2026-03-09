;;; core-workspace.el --- 项目布局与终端工作流 -*- lexical-binding: t; -*-

;;; Code:

(require 'seq)
(require 'project)
(declare-function treemacs-follow-mode "ext:treemacs")
(declare-function treemacs-project-follow-mode "ext:treemacs")
(declare-function treemacs-load-theme "ext:treemacs")

(use-package treemacs
  :bind (("C-c t" . treemacs))
  :custom
  (treemacs-width 30)
  (treemacs-position 'left)
  (treemacs-git-mode 'simple)
  :config
  (treemacs-project-follow-mode 1)
  (treemacs-follow-mode 1))

;; 使用 nerd-icons 风格，贴近 Zed 图标体验。
(use-package treemacs-nerd-icons
  :after treemacs
  :config
  (treemacs-load-theme "nerd-icons"))

(defun my/project-root-or-default ()
  "尽可能获取项目根目录。"
  (or (and (fboundp 'projectile-project-root)
           (ignore-errors (projectile-project-root)))
      (when-let ((pr (project-current nil)))
        (project-root pr))
      (and buffer-file-name (file-name-directory buffer-file-name))
      default-directory))

(defun my/find-code-window ()
  "在当前 frame 内找到代码窗口。"
  (seq-find
   (lambda (win)
     (with-selected-window win
       (and (not (derived-mode-p 'treemacs-mode 'vterm-mode))
            (not (string-match-p "\\*vterm\\*" (buffer-name))))))
   (window-list)))

(defun my/vscode-layout ()
  "重置为类似 VS Code 的布局：左侧文件树、右侧代码、下方终端。"
  (interactive)
  (let* ((project-root (my/project-root-or-default))
         (terminal-height 12)
         (vterm-win
          (seq-find
           (lambda (win)
             (with-selected-window win
               (derived-mode-p 'vterm-mode)))
           (window-list))))
    (unless (and (fboundp 'treemacs-is-visible) (treemacs-is-visible))
      (treemacs))
    (when (fboundp 'treemacs-add-and-display-current-project-exclusively)
      (ignore-errors (treemacs-add-and-display-current-project-exclusively)))
    (let ((code-win (or (my/find-code-window) (selected-window))))
      (select-window code-win)
      (unless (window-live-p vterm-win)
        (when (> (window-height) (+ terminal-height 5))
          (split-window-below (- (window-height) terminal-height))
          (other-window 1)
          (let ((default-directory project-root))
            (condition-case nil
                (vterm (generate-new-buffer-name "*vterm*"))
              (error
               (condition-case nil
                   (ansi-term (getenv "SHELL"))
                 (error (shell))))))
          (other-window -1))))))

(global-set-key (kbd "<f9>") #'my/vscode-layout)
(add-hook 'emacs-startup-hook #'my/vscode-layout)

(provide 'core-workspace)
;;; core-workspace.el ends here
