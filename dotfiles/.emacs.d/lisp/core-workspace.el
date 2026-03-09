;;; core-workspace.el --- 项目布局与终端工作流 -*- lexical-binding: t; -*-

;;; Code:

(require 'seq)
(require 'project)
(declare-function treemacs-follow-mode "ext:treemacs")
(declare-function treemacs-project-follow-mode "ext:treemacs")
(declare-function treemacs-load-theme "ext:treemacs")
(declare-function my/ai-open-panel "core-ai")

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

(define-derived-mode my/workspace-help-mode special-mode "Workspace-Help"
  "中间编辑区启动帮助模式。")

(defun my/workspace-center-help-window (&optional window)
  "将帮助页在 WINDOW 中居中显示。"
  (let ((win (or window (selected-window))))
    (when (and (window-live-p win)
               (buffer-live-p (window-buffer win)))
      (with-current-buffer (window-buffer win)
        (when (derived-mode-p 'my/workspace-help-mode)
          (let* ((content-width
                  (max 1
                       (save-excursion
                         (goto-char (point-min))
                         (let ((mx 1))
                           (while (not (eobp))
                             (setq mx (max mx (string-width
                                               (buffer-substring-no-properties
                                                (line-beginning-position)
                                                (line-end-position)))))
                             (forward-line 1))
                           mx))))
                 (win-width (window-body-width win))
                 (spare (max 0 (- win-width content-width)))
                 (left (/ spare 2))
                 (right (- spare left)))
            (set-window-margins win left right)))))))

(defun my/workspace-recenter-help-windows (_frame)
  "窗口尺寸变化后重算帮助页居中。"
  (dolist (win (window-list nil 'nomini))
    (my/workspace-center-help-window win)))

(defun my/workspace-open-help-buffer (&optional window)
  "在 WINDOW（默认当前窗口）打开简短帮助文档。"
  (let ((buf (get-buffer-create "*Workspace-Help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/workspace-help-mode)
        (insert "Emacs 工作区快速帮助\n\n")
        (insert "常用功能：\n")
        (insert "  <f9>      重新应用 VS Code 风格布局\n")
        (insert "  C-c t     打开/聚焦 Treemacs 文件树\n")
        (insert "  C-c a a   打开/聚焦右侧 AI 面板\n")
        (insert "  C-c a q   询问当前选区（无选区则整个文件）\n")
        (insert "  C-c a e   按要求改写代码\n")
        (insert "  C-c a i   补写代码\n")
        (insert "  C-c a c   直接发起问答\n")
        (insert "  C-p       按项目快速找文件\n")
        (insert "  C-x C-f   打开任意文件\n")
        (insert "  C-x d     打开目录（Dired）\n\n")
        (insert "提示：当前是帮助页，不参与编辑。\n")
        (insert "直接 `C-x C-f` 打开文件后就进入正常编码流程。")
        (goto-char (point-min))))
    (if (window-live-p window)
        (set-window-buffer window buf)
      (switch-to-buffer buf))
    (my/workspace-center-help-window (or window (selected-window)))
    buf))

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
       (and (not (window-parameter win 'window-side))
            (not (derived-mode-p 'treemacs-mode 'vterm-mode))
            (not (eq major-mode 'ellama-session-mode))
            (not (string-match-p "\\*vterm\\*" (buffer-name)))
            (not (string-match-p "\\*AI-Codex\\*" (buffer-name)))
            (not (string-match-p "^ellama " (buffer-name))))))
   (window-list)))

(defun my/workspace-should-show-help-p (&optional window)
  "判断 WINDOW 是否适合显示启动帮助页。"
  (let ((win (or window (selected-window))))
    (when (window-live-p win)
      (with-selected-window win
        (or (derived-mode-p 'dired-mode)
            (member (buffer-name) '("*scratch*" "*dashboard*" "*Messages*")))))))

(defun my/vscode-layout ()
  "重置为类似 VS Code 的布局：左树+中代码+下终端+右侧 AI。"
  (interactive)
  (let* ((project-root (my/project-root-or-default))
         (terminal-height 12)
         (code-win nil)
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
    (setq code-win (or (my/find-code-window) (selected-window)))
    (let ((target-win code-win))
      ;; 防止编辑区被终端/侧栏占据，必要时落回 scratch。
      (when (and (window-live-p target-win)
                 (with-selected-window target-win
                   (or (derived-mode-p 'vterm-mode 'treemacs-mode)
                       (window-parameter target-win 'window-side))))
        (set-window-buffer target-win (get-buffer-create "*scratch*")))
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
          (other-window -1))))
    ;; 每次应用布局都拉起右侧 AI 面板，保持 Cline/VSCode 风格一致。
    (when (fboundp 'my/ai-open-panel)
      (ignore-errors (my/ai-open-panel)))
    ;; 打开右侧面板后，把焦点还给主编辑区。
    (when (window-live-p code-win)
      (select-window code-win)
      ;; 若主区是目录/启动缓冲区，则改为简短帮助页，避免误入不稳定功能区。
      (when (my/workspace-should-show-help-p code-win)
        (my/workspace-open-help-buffer code-win)))))

(global-set-key (kbd "<f9>") #'my/vscode-layout)
(add-hook 'emacs-startup-hook #'my/vscode-layout)
(add-hook 'window-size-change-functions #'my/workspace-recenter-help-windows)

(provide 'core-workspace)
;;; core-workspace.el ends here
