;;; git.el --- Git 版本控制 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 Magit、git-todos、git-timemachine、forge、git-modes、magit-delta
;; 以及供快捷键/右键菜单复用的 Git 操作。
;;
;; 功能：
;; - Magit: 全功能 Git 界面（status/blame/log/diff/stage/discard/pull/push/stash/timemachine）
;; - magit-todos: 代码中的 TODO/FIXME 等标记管理
;; - git-timemachine: 文件历史时间旅行
;; - forge: GitHub/GitLab PR/Issue 管理（集成在 Magit 状态页）
;; - git-modes: .gitignore/.gitconfig/.gitmodules 语法高亮
;; - magit-delta: 使用 delta CLI 增强差异显示
;;
;; 快捷键：
;; - `C-c g s` / `C-x g`         打开 Magit 状态页面
;; - `C-c g b` / `C-c g l`       文件级: blame / log
;; - `C-c g d` / `C-c g t`       文件级: diff / timemachine
;; - `C-c g S` / `C-c g D`       文件级: stage / discard
;; - `C-c g F` / `C-c g P`       仓库级: pull / push
;; - `C-c g #` / `C-c g @`       仓库级: stash / pop
;; - `C-c g f i`                 forge: 列出 Issues
;; - `C-c g f p`                 forge: 创建 Pull Request
;; - `C-c g f n`                 forge: 列出 Pull Requests
;; - `C-c g f c`                 forge: 拉取远程 forge 数据
;;
;; 右键菜单：
;; 文件缓冲区的右键菜单集成了 Git 子菜单，包含上述常用操作。
;;
;; forge Token 配置：
;; 首次使用 `forge-add-pullreq` 时会自动引导创建 GitHub token。
;; 或手动在 `~/.authinfo` 中添加：
;;   machine api.github.com login USERNAME^forge password TOKEN

;;; Code:

(require 'subr-x)

(defun custom/git-repo-root (&optional file)
  "返回 FILE 所在 Git 仓库根目录。"
  (when-let ((target (or file (buffer-file-name) default-directory)))
    (locate-dominating-file target ".git")))

(defun custom/git-file-in-repo-p (&optional file)
  "判断 FILE 或当前 buffer 是否位于 Git 仓库中。"
  (and (custom/git-repo-root file) t))

(defun custom/git-buffer-file ()
  "返回当前 buffer 对应的文件，不存在时抛出用户错误。"
  (or (buffer-file-name)
      (user-error "当前缓冲区没有关联文件")))

(defun custom/git--ensure-repo (&optional file)
  "确保 FILE 或当前 buffer 位于 Git 仓库中，并返回仓库根目录。"
  (or (custom/git-repo-root file)
      (user-error "当前不在 Git 仓库中")))

(defun custom/git--run (&rest args)
  "在当前仓库中执行 Git ARGS。"
  (custom/diag "git" "执行: git %s" (string-join args " "))
  (let ((default-directory (custom/git--ensure-repo)))
    (with-temp-buffer
      (let ((status (apply #'process-file "git" nil t nil args))
            (output (string-trim (buffer-string))))
        (unless (eq status 0)
          (error "Git 命令失败: %s" (if (string-empty-p output) (string-join args " ") output)))
        output))))

(defun custom/git-status-dwim ()
  "打开当前仓库的 Magit 状态页。"
  (interactive)
  (custom/diag "git" "Magit 状态: repo=%s, file=%s" (custom/git-repo-root) (custom/git-buffer-file))
  (magit-status-setup-buffer (custom/git--ensure-repo)))

(defun custom/git-blame-current-file ()
  "对当前文件执行 blame。"
  (interactive)
  (custom/git-buffer-file)
  (call-interactively #'magit-blame-addition))

(defun custom/git-log-current-file ()
  "查看当前文件历史。"
  (interactive)
  (custom/git-buffer-file)
  (call-interactively #'magit-log-buffer-file))

(defun custom/git-diff-current-file ()
  "查看当前文件 diff。"
  (interactive)
  (custom/git-buffer-file)
  (call-interactively #'magit-diff-buffer-file))

(defun custom/git-stage-current-file ()
  "Stage 当前文件。"
  (interactive)
  (let ((file (custom/git-buffer-file)))
    (custom/git--ensure-repo file)
    (custom/git--run "add" "--" file)
    (message "已 stage: %s" (file-name-nondirectory file))))

(defun custom/git-discard-current-file ()
  "丢弃当前文件所有未提交修改。"
  (interactive)
  (let ((file (custom/git-buffer-file)))
    (custom/git--ensure-repo file)
    (when (y-or-n-p (format "丢弃 %s 的所有未提交修改？" (file-name-nondirectory file)))
      (custom/git--run "restore" "--source=HEAD" "--staged" "--worktree" "--" file)
      (revert-buffer t t t)
      (message "已丢弃: %s" (file-name-nondirectory file)))))

(defun custom/git-timemachine-toggle ()
  "切换当前文件的 git-timemachine。"
  (interactive)
  (custom/diag "git" "Timemachine 切换: %s" (custom/git-buffer-file))
  (custom/git-buffer-file)
  (call-interactively #'git-timemachine-toggle))

(defun custom/git-push-current-repo ()
  "Push 当前仓库。"
  (interactive)
  (custom/git--ensure-repo)
  (call-interactively #'magit-push-current-to-upstream))

(defun custom/git-pull-current-repo ()
  "Pull 当前仓库。"
  (interactive)
  (custom/git--ensure-repo)
  (call-interactively #'magit-pull-from-upstream))

(defun custom/git-stash-push ()
  "Stash 当前仓库中的修改。"
  (interactive)
  (custom/git--ensure-repo)
  (custom/git--run "stash" "push" "-m" (format-time-string "stash-%Y%m%d-%H%M%S"))
  (message "已创建 stash"))

(defun custom/git-stash-pop ()
  "恢复最近一次 stash。"
  (interactive)
  (custom/git--ensure-repo)
  (when (y-or-n-p "恢复最近一次 stash？")
    (custom/git--run "stash" "pop")
    (message "已恢复最近一次 stash")))

;; Magit（强大的 Git 界面）
(use-package magit
  :defer t
  :commands (magit-status
             magit-status-setup-buffer
             magit-blame-addition
             magit-log-buffer-file
             magit-diff-buffer-file
             magit-pull-from-upstream
             magit-push-current-to-upstream)
  :custom
  (magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1))

;; Magit Todos（显示代码中的 TODO）
(use-package magit-todos
  :after magit
  :defer t)

(use-package git-timemachine
  :defer t
  :commands (git-timemachine git-timemachine-toggle))

;; ═════════════════════════════════════════════════════════════════════════════
;; Forge - GitHub/GitLab PR/Issue 管理
;; ═════════════════════════════════════════════════════════════════════════════

;; Forge 在 Magit 状态页中集成 Pull Requests 和 Issues 面板
;; 首次使用需要配置 GitHub/GitLab token（见 Commentary）
(use-package forge
  :after magit
  :defer t
  :commands (forge-add-pullreq forge-list-issues forge-list-pullreqs
             forge-pull forge-create-issue)
  :bind (("C-c g f i" . forge-list-issues)
         ("C-c g f p" . forge-add-pullreq)
         ("C-c g f n" . forge-list-pullreqs)
         ("C-c g f c" . forge-pull)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Git Modes - Git 配置文件语法高亮
;; ═════════════════════════════════════════════════════════════════════════════

;; 自动为 .gitignore、.gitconfig、.gitmodules 启用对应的 major mode
(use-package git-modes
  :defer t)

;; ═════════════════════════════════════════════════════════════════════════════
;; Magit Delta - 增强差异显示
;; ═════════════════════════════════════════════════════════════════════════════

;; 使用 delta CLI 替代 Magit 默认的差异显示
;; 前置依赖：guix install delta
(use-package magit-delta
  :after magit
  :defer t
  :config
  (magit-delta-mode +1))

(provide 'git)
;;; git.el ends here
