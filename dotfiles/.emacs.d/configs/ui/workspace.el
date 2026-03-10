;;; workspace.el --- 工作区布局与文件树 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Treemacs 文件树和 VS Code 风格的工作区布局。

;;; Code:

(require 'seq)
(require 'cl-lib)

;; Treemacs 文件树
(use-package treemacs
  :bind ("C-c t" . treemacs)
  :custom
  (treemacs-width 30)
  (treemacs-position 'left)
  (treemacs-git-mode 'simple)
  :config
  (treemacs-project-follow-mode 1)
  (treemacs-follow-mode 1))

;; Nerd Icons 主题
(use-package treemacs-nerd-icons
  :after treemacs
  :config
  (treemacs-load-theme "nerd-icons"))

;; 帮助页面模式
(define-derived-mode my/workspace-help-mode special-mode "Workspace-Help"
  "中间编辑区启动帮助模式。")

;; 居中显示帮助页面
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

;; 打开帮助缓冲区
(defun my/workspace-open-help-buffer (&optional window)
  "在 WINDOW 打开简短帮助文档。"
  (let ((buf (get-buffer-create "*Workspace-Help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/workspace-help-mode)
        (insert "\n\n")
        (cl-labels
            ((section (title)
               (insert (propertize title 'face '(:weight bold :foreground "#7aa2f7")))
               (insert "\n"))
             (row (key desc)
               (insert (format "  %-14s %s\n" key desc))))
          (section "文件与搜索")
          (row "C-x C-f" "打开文件")
          (row "C-p" "项目内快速找文件")
          (row "C-S-f" "全文搜索 (ripgrep)")
          (row "C-S-b" "切换缓冲区")
          (row "C-s" "当前文件内搜索")
          (insert "\n")
          (section "编辑与控制")
          (row "C-x C-s" "保存当前文件")
          (row "C-S-c" "复制（选区/当前行）")
          (row "C-S-v" "粘贴")
          (row "M-y" "粘贴历史")
          (row "C-." "上下文操作菜单")
          (row "C-g" "取消当前命令")
          (insert "\n")
          (section "窗口切换")
          (row "C-w h/j/k/l" "切换到 左/下/上/右 窗口")
          (row "C-x o" "循环切换窗口")
          (row "C-c t" "打开/聚焦 Treemacs")
          (insert "\n")
          (section "工作区布局")
          (row "<f5>" "重建 VS Code 风格布局")
          (insert "\n")
          (section "Git 操作")
          (row "C-c g b" "显示当前行 Git blame")
          (insert "\n")
          (section "AI 工作流")
          (row "C-c a c" "开始 AI 对话")
          (row "C-c a q" "询问选区代码")
          (row "C-c a e" "让 AI 改写代码")
          (row "C-c a i" "让 AI 补写代码")
          (insert "\n")
          (section "模式切换")
          (row "C-c v v" "切换到 Vim 模式")
          (row "C-c v e" "切换到 Emacs 模式"))
        (insert "\n\n")
        (insert "按 ")
        (insert (propertize "C-x C-f" 'face '(:weight bold)))
        (insert " 立即开始编辑。\n")
        (goto-char (point-min))))
    (if (window-live-p window)
        (set-window-buffer window buf)
      (switch-to-buffer buf))
    (my/workspace-center-help-window (or window (selected-window)))
    buf))

;; 辅助函数
(defun my/find-code-window ()
  "查找代码编辑窗口。"
  (seq-find
   (lambda (win)
     (with-selected-window win
       (and (not (window-parameter win 'window-side))
            (not (derived-mode-p 'treemacs-mode 'vterm-mode)))))
   (window-list)))

(defun my/workspace-should-show-help-p (&optional window)
  "判断 WINDOW 是否适合显示启动帮助页。"
  (let ((win (or window (selected-window))))
    (when (window-live-p win)
      (with-selected-window win
        (or (derived-mode-p 'dired-mode)
            (member (buffer-name) '("*scratch*" "*dashboard*" "*Messages*")))))))

;; VS Code 风格布局：左树+中代码+下终端+右AI
(defun my/vscode-layout ()
  "重置为类似 VS Code 的布局。"
  (interactive)
  (let* ((terminal-height 12)
         (code-win nil)
         (vterm-win
          (seq-find
           (lambda (win)
             (with-selected-window win
               (derived-mode-p 'vterm-mode)))
           (window-list))))
    ;; 打开 Treemacs
    (unless (and (fboundp 'treemacs-is-visible) (treemacs-is-visible))
      (treemacs))
    ;; 获取代码窗口
    (setq code-win (or (my/find-code-window) (selected-window)))
    (select-window code-win)
    ;; 创建底部终端（仅当不存在时）
    (unless (window-live-p vterm-win)
      (when (> (window-height) (+ terminal-height 5))
        (split-window-below (- (window-height) terminal-height))
        (other-window 1)
        (if (fboundp 'vterm)
            (vterm)
          (shell))
        (other-window -1)))
    ;; 打开右侧 AI 面板
    (when (fboundp 'my/ai-open-panel)
      (ignore-errors (my/ai-open-panel)))
    ;; 焦点回到代码窗口
    (when (window-live-p code-win)
      (select-window code-win)
      ;; 若主区是目录/启动缓冲区，则显示帮助页
      (when (my/workspace-should-show-help-p code-win)
        (my/workspace-open-help-buffer code-win)))))

;; 窗口尺寸变化后重算帮助页居中
(defun my/workspace-recenter-help-windows (_frame)
  "窗口尺寸变化后重算帮助页居中。"
  (dolist (win (window-list nil 'nomini))
    (my/workspace-center-help-window win)))

;; 绑定到 F5 并在启动时自动应用
(global-set-key (kbd "<f5>") #'my/vscode-layout)
(add-hook 'emacs-startup-hook #'my/vscode-layout)
(add-hook 'window-size-change-functions #'my/workspace-recenter-help-windows)

(provide 'workspace)
;;; workspace.el ends here
