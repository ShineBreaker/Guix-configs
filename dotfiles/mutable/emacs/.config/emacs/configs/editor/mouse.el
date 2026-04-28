;;; mouse.el --- 鼠标操作增强 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 提供类 VS Code / JetBrains 的鼠标交互体验。
;; 在移除 Evil 后，本文件成为非模态工作流的核心补充输入层：
;; - 右键上下文菜单（代码导航、LSP、格式化、多光标）
;; - 文件缓冲区右键菜单额外集成 Git 子菜单
;;   （status/blame/log/diff/stage/discard/pull/push/stash/timemachine）
;; - 右键菜单中文化由 `configs/i18n/context-menu.el' 统一处理
;; - Ctrl+Click 跳转到定义
;; - 鼠标侧键前进/后退
;; - Alt+Click 多光标
;; - 平滑滚动、滚轮速度与拖拽行为优化
;; - 光标悬停自动显示文档（eldoc-box）
;;
;; 悬停模式策略：
;; - prog-mode: 自动悬停显示文档
;; - text-mode / org-mode / markdown-mode: 仅手动触发

;;; Code:

(require 'subr-x)

;; ═════════════════════════════════════════════════════════════════════════════
;; 鼠标事件辅助函数
;; ═════════════════════════════════════════════════════════════════════════════

(defvar custom/mouse--context-marker nil
  "最近一次右键菜单触发位置的 marker。")

(defvar custom/mouse--context-window nil
  "最近一次右键菜单触发位置的 window。")

(defun custom/mouse--goto-event (event)
  "跳转到 EVENT 位置，成功返回 t。"
  (when-let* ((posn (event-start event))
              (window (posn-window posn))
              (pos (posn-point posn))
              ((window-live-p window))
              ((integer-or-marker-p pos)))
    (select-window window)
    (goto-char pos)
    t))

(defun custom/mouse--save-context (event)
  "保存 EVENT 位置供右键菜单使用。"
  (setq custom/mouse--context-window (posn-window (event-start event)))
  (when (custom/mouse--goto-event event)
    (setq custom/mouse--context-marker (point-marker))))

(defun custom/mouse--call-at-context (command)
  "在保存的右键位置调用 COMMAND。"
  (let ((window custom/mouse--context-window)
        (marker custom/mouse--context-marker))
    (if (and (window-live-p window)
             marker
             (marker-buffer marker))
        (with-selected-window window
          (with-current-buffer (marker-buffer marker)
            (goto-char marker)
            (call-interactively command)))
      (call-interactively command))))

(defun custom/corfu-popupinfo-show-dwim ()
  "按当前上下文显示文档。
Corfu 激活时显示候选文档，否则显示光标处符号文档。"
  (interactive)
  (cond
   ((and (boundp 'corfu--candidates)
         corfu--candidates
         (fboundp 'corfu-popupinfo-toggle))
    (corfu-popupinfo-toggle))
   (t
    (custom/code-show-hover))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 右键菜单命令
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/mouse-menu-goto-definition ()
  "在右键位置跳转到定义。"
  (interactive)
  (custom/mouse--call-at-context #'custom/code-goto-definition))

(defun custom/mouse-menu-find-references ()
  "在右键位置查找引用。"
  (interactive)
  (custom/mouse--call-at-context #'custom/code-goto-references))

(defun custom/mouse-menu-show-hover ()
  "在右键位置显示文档。"
  (interactive)
  (custom/mouse--call-at-context #'custom/corfu-popupinfo-show-dwim))

(defun custom/mouse-menu-goto-implementation ()
  "在右键位置跳转到实现。"
  (interactive)
  (custom/mouse--call-at-context #'eglot-find-implementation))

(defun custom/mouse-menu-rename ()
  "在右键位置重命名符号。"
  (interactive)
  (custom/mouse--call-at-context #'custom/code-rename))

(defun custom/mouse-menu-code-action ()
  "在右键位置执行代码操作。"
  (interactive)
  (custom/mouse--call-at-context #'custom/code-action))

(defun custom/mouse-menu-format ()
  "在右键位置格式化代码。"
  (interactive)
  (custom/mouse--call-at-context #'custom/code-format-dwim))

(defun custom/mouse-menu-comment ()
  "在右键位置切换注释。"
  (interactive)
  (custom/mouse--call-at-context #'custom/code-comment-dwim))

(defun custom/mouse-menu-add-cursor ()
  "在右键位置添加多光标。"
  (interactive)
  (custom/mouse--call-at-context #'custom/mouse-add-cursor))

(defun custom/mouse-add-cursor ()
  "在当前点添加多光标。"
  (interactive)
  (when (require 'multiple-cursors-core nil t)
    (unless (bound-and-true-p multiple-cursors-mode)
      (mc/maybe-multiple-cursors-mode))
    (mc/create-fake-cursor-at-point)
    (mc/maybe-multiple-cursors-mode)))

(defun custom/mouse-menu-list-errors ()
  "打开错误列表面板。"
  (interactive)
  (when (fboundp 'custom/flycheck-list-errors-dwim)
    (custom/flycheck-list-errors-dwim)))

(defun custom/mouse-menu-git-status ()
  "打开当前仓库状态。"
  (interactive)
  (custom/mouse--call-at-context #'custom/git-status-dwim))

(defun custom/mouse-menu-git-blame ()
  "查看当前文件 blame。"
  (interactive)
  (custom/mouse--call-at-context #'custom/git-blame-current-file))

(defun custom/mouse-menu-git-log ()
  "查看当前文件历史。"
  (interactive)
  (custom/mouse--call-at-context #'custom/git-log-current-file))

(defun custom/mouse-menu-git-diff ()
  "查看当前文件 diff。"
  (interactive)
  (custom/mouse--call-at-context #'custom/git-diff-current-file))

(defun custom/mouse-menu-git-stage ()
  "Stage 当前文件。"
  (interactive)
  (custom/mouse--call-at-context #'custom/git-stage-current-file))

(defun custom/mouse-menu-git-discard ()
  "丢弃当前文件修改。"
  (interactive)
  (custom/mouse--call-at-context #'custom/git-discard-current-file))

(defun custom/mouse-menu-git-timemachine ()
  "切换当前文件历史浏览。"
  (interactive)
  (custom/mouse--call-at-context #'custom/git-timemachine-toggle))

(defun custom/mouse-menu-git-pull ()
  "Pull 当前仓库。"
  (interactive)
  (custom/mouse--call-at-context #'custom/git-pull-current-repo))

(defun custom/mouse-menu-git-push ()
  "Push 当前仓库。"
  (interactive)
  (custom/mouse--call-at-context #'custom/git-push-current-repo))

(defun custom/mouse-menu-git-stash-push ()
  "Stash 当前修改。"
  (interactive)
  (custom/mouse--call-at-context #'custom/git-stash-push))

(defun custom/mouse-menu-git-stash-pop ()
  "恢复最近 stash。"
  (interactive)
  (custom/mouse--call-at-context #'custom/git-stash-pop))

;; ═════════════════════════════════════════════════════════════════════════════
;; 右键上下文菜单
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/mouse-context-menu (menu click)
  "在编程模式下增强右键菜单。"
  (custom/mouse--save-context click)
  (let ((code-context-p (derived-mode-p 'prog-mode))
        (git-context-p (and (buffer-file-name) (fboundp 'custom/git-file-in-repo-p)
                            (custom/git-file-in-repo-p)))
        (has-symbol (thing-at-point 'symbol t))
        (has-eglot (and (fboundp 'eglot-managed-p) (eglot-managed-p))))
    (when code-context-p
      (let ((code-menu (make-sparse-keymap "代码操作")))
        (define-key-after code-menu [cut]
          '(menu-item "剪切" kill-region :enable (use-region-p)))
        (define-key-after code-menu [copy]
          '(menu-item "复制" kill-ring-save :enable (use-region-p)))
        (define-key-after code-menu [paste]
          '(menu-item "粘贴" yank))

        (when has-symbol
          (define-key-after code-menu [sep1] menu-bar-separator)
          (define-key-after code-menu [goto-def]
            '(menu-item "跳转到定义" custom/mouse-menu-goto-definition))
          (define-key-after code-menu [find-refs]
            '(menu-item "查找引用" custom/mouse-menu-find-references))
          (define-key-after code-menu [show-doc]
            '(menu-item "显示文档" custom/mouse-menu-show-hover))
          (when has-eglot
            (define-key-after code-menu [goto-impl]
              '(menu-item "跳转到实现" custom/mouse-menu-goto-implementation))))

        (when has-eglot
          (define-key-after code-menu [sep2] menu-bar-separator)
          (define-key-after code-menu [rename]
            '(menu-item "重命名" custom/mouse-menu-rename))
          (define-key-after code-menu [code-action]
            '(menu-item "代码操作" custom/mouse-menu-code-action)))

        (define-key-after code-menu [sep3] menu-bar-separator)
        (define-key-after code-menu [format]
          '(menu-item "格式化" custom/mouse-menu-format))
        (define-key-after code-menu [comment]
          '(menu-item "切换注释" custom/mouse-menu-comment))

        (when (bound-and-true-p flycheck-mode)
          (define-key-after code-menu [sep5] menu-bar-separator)
          (define-key-after code-menu [list-errors]
            '(menu-item "错误列表" custom/mouse-menu-list-errors)))

        (when (require 'multiple-cursors-core nil t)
          (define-key-after code-menu [sep4] menu-bar-separator)
          (define-key-after code-menu [add-cursor]
            '(menu-item "添加光标" custom/mouse-menu-add-cursor)))

        (define-key-after menu [code-menu]
          `(menu-item "代码操作" ,code-menu))))

    (when git-context-p
      (let ((git-menu (make-sparse-keymap "Git")))
        (define-key-after git-menu [status]
          '(menu-item "仓库状态" custom/mouse-menu-git-status))
        (define-key-after git-menu [sep1] menu-bar-separator)
        (define-key-after git-menu [blame]
          '(menu-item "当前文件 Blame" custom/mouse-menu-git-blame))
        (define-key-after git-menu [log]
          '(menu-item "当前文件历史" custom/mouse-menu-git-log))
        (define-key-after git-menu [diff]
          '(menu-item "当前文件差异" custom/mouse-menu-git-diff))
        (define-key-after git-menu [timemachine]
          '(menu-item "文件时光机" custom/mouse-menu-git-timemachine))
        (define-key-after git-menu [sep2] menu-bar-separator)
        (define-key-after git-menu [stage]
          '(menu-item "Stage 当前文件" custom/mouse-menu-git-stage))
        (define-key-after git-menu [discard]
          '(menu-item "丢弃当前文件修改" custom/mouse-menu-git-discard))
        (define-key-after git-menu [sep3] menu-bar-separator)
        (define-key-after git-menu [pull]
          '(menu-item "Pull" custom/mouse-menu-git-pull))
        (define-key-after git-menu [push]
          '(menu-item "Push" custom/mouse-menu-git-push))
        (define-key-after git-menu [stash-push]
          '(menu-item "Stash Push" custom/mouse-menu-git-stash-push))
        (define-key-after git-menu [stash-pop]
          '(menu-item "Stash Pop" custom/mouse-menu-git-stash-pop))
        (define-key-after menu [git-menu]
          `(menu-item "Git" ,git-menu)))))
  menu)

(when (boundp 'context-menu-functions)
  (add-hook 'context-menu-functions #'custom/mouse-context-menu))

;; 智能右键菜单（Treemacs 中保留原生行为）
(defun custom/mouse-context-menu-open (event)
  "智能右键菜单：Treemacs 中使用原生菜单，其他地方使用增强菜单。"
  (interactive "e")
  (if (and (window-live-p (posn-window (event-start event)))
           (with-selected-window (posn-window (event-start event))
             (derived-mode-p 'treemacs-mode)))
      (with-selected-window (posn-window (event-start event))
        (let ((cmd (and (boundp 'treemacs-mode-map)
                        (lookup-key treemacs-mode-map [mouse-3]))))
          (if (commandp cmd)
              (call-interactively cmd)
            (treemacs-rightclick-menu event))))
    (context-menu-open event)))

(global-set-key [mouse-3] #'custom/mouse-context-menu-open)

;; ═════════════════════════════════════════════════════════════════════════════
;; 鼠标快捷键
;; ═════════════════════════════════════════════════════════════════════════════

;; Ctrl+Click 跳转到定义
(defun custom/mouse-goto-definition (event)
  "Ctrl+Click 跳转到定义。"
  (interactive "e")
  (when (custom/mouse--goto-event event)
    (if (thing-at-point 'symbol t)
        (call-interactively #'custom/code-goto-definition)
      (message "点击位置没有可跳转的符号"))))

;; Shift+Click 扩展选区
(defun custom/mouse-extend-region (event)
  "Shift+Click 扩展选区到点击位置。"
  (interactive "e")
  (let ((deactivate-mark nil))
    (unless (region-active-p)
      (push-mark (point) t t))
    (when (custom/mouse--goto-event event)
      (activate-mark))))

;; 鼠标侧键导航
(defun custom/mouse-jump-back ()
  "鼠标侧键后退。"
  (interactive)
  (if (fboundp 'xref-go-back)
      (condition-case err
          (xref-go-back)
        (error (message "%s" (error-message-string err))))
    (pop-mark)))

(defun custom/mouse-jump-forward ()
  "鼠标侧键前进。"
  (interactive)
  (if (fboundp 'xref-go-forward)
      (condition-case err
          (xref-go-forward)
        (error (message "%s" (error-message-string err))))
    (message "前进功能不可用")))

(global-set-key (kbd "C-<mouse-1>") #'custom/mouse-goto-definition)
(global-set-key (kbd "S-<mouse-1>") #'custom/mouse-extend-region)
(global-set-key (kbd "<mouse-8>") #'custom/mouse-jump-back)
(global-set-key (kbd "<mouse-9>") #'custom/mouse-jump-forward)

;; Treemacs 中禁用全局鼠标覆盖，让 treemacs-mode-map 的绑定生效
(with-eval-after-load 'treemacs
  (define-key treemacs-mode-map (kbd "C-<mouse-1>") nil)
  (define-key treemacs-mode-map (kbd "S-<mouse-1>") nil))

;; ═════════════════════════════════════════════════════════════════════════════
;; eldoc-box 文档弹窗
;; ═════════════════════════════════════════════════════════════════════════════

(defvar custom/eldoc-box-enabled t
  "是否启用 eldoc-box 文档弹窗。")

(defun custom/eldoc-box-help-at-point ()
  "优先使用 eldoc-box 显示符号文档。"
  (interactive)
  (cond
   ((and (display-graphic-p)
         (require 'eldoc-box nil t)
         (fboundp 'eldoc-box-help-at-point))
    (eldoc-box-help-at-point))
   ((fboundp 'eglot-help-at-point)
    (eglot-help-at-point))
   ((fboundp 'eldoc-doc-buffer)
    (eldoc-doc-buffer))
   (t
    (describe-thing-at-point))))

(defun custom/eldoc-box-refresh-buffer ()
  "按当前 major mode 刷新 eldoc-box 自动悬停策略。"
  (when (and custom/eldoc-box-enabled
             (display-graphic-p)
             (require 'eldoc-box nil t))
    (cond
     ;; 编程模式：启用光标悬停文档
     ((derived-mode-p 'prog-mode)
      (when (and (fboundp 'eldoc-box-hover-at-point-mode)
                 (not (bound-and-true-p eldoc-box-hover-at-point-mode)))
        (eldoc-box-hover-at-point-mode 1)))
     ;; 文本模式：禁用自动悬停
     (t
      (when (and (fboundp 'eldoc-box-hover-at-point-mode)
                 (bound-and-true-p eldoc-box-hover-at-point-mode))
        (eldoc-box-hover-at-point-mode -1))))))

(defun custom/eldoc-box-toggle ()
  "切换 eldoc-box 总开关。"
  (interactive)
  (setq custom/eldoc-box-enabled (not custom/eldoc-box-enabled))
  (unless custom/eldoc-box-enabled
    (when (and (fboundp 'eldoc-box-quit-frame) (featurep 'eldoc-box))
      (eldoc-box-quit-frame)))
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (custom/eldoc-box-refresh-buffer)))
  (message "eldoc-box 已%s" (if custom/eldoc-box-enabled "启用" "禁用")))

;; ═════════════════════════════════════════════════════════════════════════════
;; eldoc 初始化
;; ═════════════════════════════════════════════════════════════════════════════

(setq eldoc-idle-delay 0.35
      eldoc-echo-area-use-multiline-p (not (display-graphic-p))) ; 终端下允许多行显示（弥补无 eldoc-box）

;; 终端模式下增强 eldoc echo area 显示
;; 注意：daemon 模式下此顶层 `display-graphic-p' 返回 nil，
;; 因此该设置会生效；standalone GUI 下不会设置。
;; 终端帧的实际行为由 appearance.el 中的 per-frame 逻辑管理。
(unless (display-graphic-p)
  (setq eldoc-echo-area-display-truncation nil)) ; 显示完整文档，不截断

(add-hook 'prog-mode-hook #'eldoc-mode)
(add-hook 'after-change-major-mode-hook #'custom/eldoc-box-refresh-buffer)

(use-package eldoc-box
  :defer t
  :init
  (add-hook 'eglot-managed-mode-hook #'custom/eldoc-box-refresh-buffer))

;; ═════════════════════════════════════════════════════════════════════════════
;; 滚动与鼠标优化
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/maybe-enable-pixel-scroll ()
  "在 GUI frame 中启用像素级平滑滚动。
优先使用 pixel-scroll-precision-mode (Emacs 29+)，回退到 pixel-scroll-mode。"
  (when (display-graphic-p)
    (cond
     ((fboundp 'pixel-scroll-precision-mode)
      (pixel-scroll-precision-mode 1)
      (setq pixel-scroll-precision-interpolate-page t))
     ((fboundp 'pixel-scroll-mode)
      (pixel-scroll-mode 1)))))

;; 平滑滚动（仅 GUI 模式）
;; 注意：daemon 模式下 `(display-graphic-p)' 在加载时返回 nil，
;; 所以顶层启用不会生效。通过 `custom/apply-frame-appearance' 中的
;; `custom/maybe-enable-pixel-scroll' 按 frame 启用。
(unless (daemonp)
  (custom/maybe-enable-pixel-scroll))

;; 鼠标滚轮速度优化
(setq mouse-wheel-scroll-amount '(3 ((shift) . 1) ((control) . nil))
      mouse-wheel-progressive-speed nil
      mouse-wheel-follow-mouse t)

;; 拖拽文本优化
(setq mouse-drag-and-drop-region t
      mouse-drag-and-drop-region-cross-program t)

;; Alt+Click 添加多光标
(use-package multiple-cursors
  :defer t
  :bind (("M-<mouse-1>" . mc/add-cursor-on-click))
  :config
  (setq mc/always-run-for-all t))

(provide 'mouse)
;;; mouse.el ends here
