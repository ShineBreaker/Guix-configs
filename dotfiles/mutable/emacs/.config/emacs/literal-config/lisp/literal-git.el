;;; literal-git.el --- Git 操作辅助函数 + display-buffer 路由 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Git 操作辅助函数（供 C-c g 前缀和右键菜单复用）。
;; - Magit 状态页路由到底部 side-window（40% 高度）
;; - COMMIT_EDITMSG 经 server-window 路由到上方主编辑窗口
;;   （保持「上编辑 + 下 magit」布局一致）
;; - 文件级操作：blame / log / diff / stage / discard / timemachine
;; - 仓库级操作：push / pull / stash push / stash pop
;;
;; 所有操作通过 `literal:executable-git'（启动期缓存）调用 git，
;; 不每次搜 PATH。

;;; Code:

(require 'subr-x)
(require 'literal-bootstrap)

;; ═════════════════════════════════════════════════════════════════════════════
;; 仓库检测辅助
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/git-repo-root (&optional file)
  "返回 FILE 所在 Git 仓库根目录。"
  (when-let* ((target (or file (buffer-file-name) default-directory)))
    (locate-dominating-file target ".git")))

(defun literal/git-file-in-repo-p (&optional file)
  "判断 FILE 或当前 buffer 是否位于 Git 仓库中。"
  (and (literal/git-repo-root file) t))

(defun literal/git-buffer-file ()
  "返回当前 buffer 对应的文件，不存在时抛出用户错误。"
  (or (buffer-file-name)
      (user-error "当前缓冲区没有关联文件")))

(defun literal/git--ensure-repo (&optional file)
  "确保 FILE 或当前 buffer 位于 Git 仓库中，并返回仓库根目录。"
  (or (literal/git-repo-root file)
      (user-error "当前不在 Git 仓库中")))

(defun literal/git--run (&rest args)
  "在当前仓库中执行 Git ARGS。"
  (let ((default-directory (literal/git--ensure-repo)))
    (with-temp-buffer
      (let ((status (apply #'process-file literal:executable-git nil t nil args))
            (output (string-trim (buffer-string))))
        (unless (eq status 0)
          (error "Git 命令失败: %s"
                 (if (string-empty-p output) (string-join args " ") output)))
        output))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 文件级操作（C-c g 前缀）
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/git-status-dwim ()
  "打开当前仓库的 Magit 状态页。"
  (interactive)
  (magit-status-setup-buffer (literal/git--ensure-repo)))

(defun literal/git-blame-current-file ()
  "对当前文件执行 blame。"
  (interactive)
  (literal/git-buffer-file)
  (call-interactively #'magit-blame-addition))

(defun literal/git-log-current-file ()
  "查看当前文件历史。"
  (interactive)
  (literal/git-buffer-file)
  (call-interactively #'magit-log-buffer-file))

(defun literal/git-diff-current-file ()
  "查看当前文件 diff。"
  (interactive)
  (literal/git-buffer-file)
  (call-interactively #'magit-diff-buffer-file))

(defun literal/git-stage-current-file ()
  "Stage 当前文件。"
  (interactive)
  (let ((file (literal/git-buffer-file)))
    (literal/git--ensure-repo file)
    (literal/git--run "add" "--" file)
    (message "已 stage: %s" (file-name-nondirectory file))))

(defun literal/git-discard-current-file ()
  "丢弃当前文件所有未提交修改。"
  (interactive)
  (let ((file (literal/git-buffer-file)))
    (literal/git--ensure-repo file)
    (when (y-or-n-p (format "丢弃 %s 的所有未提交修改？"
                            (file-name-nondirectory file)))
      (literal/git--run "restore" "--source=HEAD" "--staged" "--worktree" "--" file)
      (revert-buffer t t t)
      (message "已丢弃: %s" (file-name-nondirectory file)))))

(defun literal/git-timemachine-toggle ()
  "切换当前文件的 git-timemachine。"
  (interactive)
  (literal/git-buffer-file)
  (call-interactively #'git-timemachine-toggle))

;; ═════════════════════════════════════════════════════════════════════════════
;; 仓库级操作
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/git-push-current-repo ()
  "Push 当前仓库。"
  (interactive)
  (literal/git--ensure-repo)
  (call-interactively #'magit-push-current-to-upstream))

(defun literal/git-pull-current-repo ()
  "Pull 当前仓库。"
  (interactive)
  (literal/git--ensure-repo)
  (call-interactively #'magit-pull-from-upstream))

(defun literal/git-stash-push ()
  "Stash 当前仓库中的修改。"
  (interactive)
  (literal/git--ensure-repo)
  (literal/git--run "stash" "push" "-m"
                    (format-time-string "stash-%Y%m%d-%H%M%S"))
  (message "已创建 stash"))

(defun literal/git-stash-pop ()
  "恢复最近一次 stash。"
  (interactive)
  (literal/git--ensure-repo)
  (when (y-or-n-p "恢复最近一次 stash？")
    (literal/git--run "stash" "pop")
    (message "已恢复最近一次 stash")))

;; ═════════════════════════════════════════════════════════════════════════════
;; Magit 显示策略
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/magit-display-buffer (buffer)
  "Magit 缓冲区显示策略。
- magit-status → 底部 side-window (height 0.4)
- 其他 magit 子缓冲区（diff/log/process）→ 复用 status 所在窗口
注意：commit message 不经过这里，由 emacsclient/with-editor 经
`server-window' → `display-buffer' 路径显示。"
  (let ((buffer-mode (buffer-local-value 'major-mode buffer)))
    (cond
     ((eq buffer-mode 'magit-status-mode)
      (display-buffer buffer '(display-buffer-in-side-window
                               (side . bottom) (window-height . 0.4))))
     (t
      (display-buffer buffer '(display-buffer-same-window))))))

(defun literal/git-commit-setup-buffer-maybe ()
  "当前 buffer 是 Git 提交消息文件时加载并启用 `git-commit-mode'。"
  (when (and buffer-file-name
             (member (file-name-nondirectory buffer-file-name)
                     '("COMMIT_EDITMSG" "MERGE_MSG" "TAG_EDITMSG"
                       "NOTES_EDITMSG" "PULLREQ_EDITMSG")))
    (require 'git-commit)
    (git-commit-setup-check-buffer)))

;; ═════════════════════════════════════════════════════════════════════════════
;; display-buffer 辅助（窗口路由）
;; ═════════════════════════════════════════════════════════════════════════════

(cl-defun literal/register-side-window (regex side size &key slot width)
  "把 REGEX 匹配的 buffer 路由到 SIDE 边的 side-window，占用 SIZE 比例。

REGEX : buffer-name 匹配字符串正则
SIDE  : bottom / right / left / top（符号）
SIZE  : 0~1 浮点比例
SLOT  : 默认 0（同 side 多窗口的堆叠顺序）
WIDTH : 非 nil 强制按 window-width；nil（默认）时按 SIDE 自动推导
        （left/right → window-width，top/bottom → window-height）。

规则追加到 `display-buffer-alist' 末尾。顺序敏感：更具体的规则应先注册。"
  (let* ((slot (or slot 0))
         (use-width (or width (memq side '(left right))))
         (window-dim (if use-width 'window-width 'window-height)))
    (add-to-list 'display-buffer-alist
                 `(,regex
                   (display-buffer-in-side-window)
                   (side . ,side)
                   (slot . ,slot)
                   (,window-dim . ,size))
                 t)))

(defun literal/display-buffer-in-main-window (buffer &optional _alist)
  "把 BUFFER 显示在「主编辑窗口」并选中。
主编辑窗口 = 当前 frame 内最靠上（y 坐标最小）的非 side-window 窗口。
保证无论光标当前在哪个窗口（如底部 magit），COMMIT_EDITMSG
都稳定落到上方编辑窗口，与「上编辑 + 下 magit」布局一致。

若无候选（如 frame 只剩 side-window），退化为 `display-buffer-pop-up-window'。

同时用作 `display-buffer-alist' 的 action 函数（参数 ALIST 被忽略）和
`server-window' 的值（server.el 调用时只传 buffer 一个参数）。"
  (let* ((frame (selected-frame))
         (candidates
          (cl-remove-if
           (lambda (w) (window-parameter w 'window-side))
           (window-list frame 'no-minibuf (frame-first-window frame))))
         (target (car (sort candidates
                            (lambda (a b)
                              (let ((ya (nth 1 (window-edges a nil t t)))
                                    (yb (nth 1 (window-edges b nil t t))))
                                (or (< ya yb)
                                    (and (= ya yb)
                                         (< (nth 0 (window-edges a nil t t))
                                            (nth 0 (window-edges b nil t t)))))))))))
    (if (window-live-p target)
        (progn
          (set-window-buffer target buffer)
          (select-window target)
          target)
      (display-buffer buffer '(display-buffer-pop-up-window)))))

(defun literal/display-or-focus (buffer action &optional select)
  "有则聚焦，无则按 ACTION 创建。
BUFFER 已在某窗口显示时，聚焦该窗口（SELECT 非 nil）；否则用 ACTION
（display-buffer 动作列表）创建新窗口。临时绑定 display-buffer-alist 为 nil，
避免递归匹配 display-buffer-alist 中的规则。"
  (when (buffer-live-p buffer)
    (if-let* ((win (get-buffer-window buffer)))
        (when select (select-window win))
      (let ((display-buffer-alist nil))
        (display-buffer buffer action)))))

(provide 'literal-git)
;;; literal-git.el ends here
