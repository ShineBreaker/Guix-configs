;;; workspace.el --- 工作区布局与文件树 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 稳健的工作区布局系统：Treemacs + 编辑器 + Minimap + 终端。
;;
;; 布局结构：
;; ┌──────┬──────────┬─────────┐
;; │      │ 编辑器   │ Minimap │
;; │Treeml│ (中上)   │ (右上)  │
;; │ acs  ├──────────┴─────────┤
;; │      │  终端 (下，全宽)   │
;; └──────┴────────────────────┘
;;
;; 功能说明：
;; - Treemacs: 左侧文件树（宽度 30），受窗口参数保护
;; - 编辑器: 中间主编辑区，接收所有文件打开操作
;; - Minimap: 编辑器右侧（普通窗口分割，仅 GUI），受窗口参数保护
;; - 终端: 下方全宽延伸，受窗口参数保护
;; - Dirvish/Dired: 优先使用 `nerd-icons' 渲染文件图标，与 Treemacs 主题统一
;;
;; Git 集成：
;; - treemacs-git-mode: extended 模式（显示已修改/新增/删除/未跟踪文件状态）
;; - diff-hl: Magit 刷新后同步更新编辑区差异指示
;;
;; 核心特性：
;; - 窗口四重保护：no-other-window + no-delete-other-windows + window-dedicated-p + window-preserve-size
;; - 文件打开控制：确保文件始终在编辑器窗口打开
;; - 自动布局触发稳态：find-file-hook + server-switch-hook 共用同一调度入口
;; - 自动布局执行校验：idle timer 真正执行前会再次确认目标文件 buffer 仍显示在当前 frame
;; - 自动布局容错：延迟触发失败时会回滚 transitioning/initialized 状态，避免触发永久卡死
;;
;; 快捷键：
;; - F5: 切换工作区布局
;; - `C-c t l`: 通过前缀键触发布局
;; - `C-c t t`: 打开/切换 Treemacs
;; - `C-c t r`: 在 Treemacs 中定位当前文件
;;
;; 提示：
;; - 在修改布局的时候，可以利用 `tmux` 来测试

;;; Code:

(require 'seq)

;; ═════════════════════════════════════════════════════════════════════════════
;; Treemacs 文件树
;; ═════════════════════════════════════════════════════════════════════════════

(use-package treemacs
  :commands (treemacs treemacs-select-window)
  :config
  (setq treemacs-width 30
        treemacs-position 'left
        treemacs-follow-after-init nil
         treemacs-is-never-other-window t
         treemacs-git-mode 'extended
         treemacs-git-commit-diff-mode t)
  (defun custom--treemacs-safe-apply-annotations (orig-fun &rest args)
    "安全执行 Treemacs 延迟注解，忽略失效 marker。"
    (condition-case nil
        (apply orig-fun args)
      (wrong-type-argument nil)
      (error nil)))
  (when (fboundp 'treemacs--apply-annotations-deferred)
    (advice-add 'treemacs--apply-annotations-deferred
                :around #'custom--treemacs-safe-apply-annotations))
  (define-key treemacs-mode-map [mouse-1] #'treemacs-single-click-expand-action)
  (define-key treemacs-mode-map [double-mouse-1] #'treemacs-RET-action))

(use-package treemacs-nerd-icons
  :after treemacs
  :config
  (treemacs-load-theme "nerd-icons"))

(use-package treemacs-icons-dired
  :if (not (locate-library "dirvish"))
  :after treemacs
  :hook (dired-mode . treemacs-icons-dired-mode))

(use-package dirvish
  :if (locate-library "dirvish")
  :commands (dirvish dirvish-dwim)
  :init
  (setq dirvish-attributes '(nerd-icons file-size)
        dirvish-nerd-icons-height 0.95
        dirvish-nerd-icons-offset 0.0)
  (when (require 'dirvish nil t)
    (dirvish-override-dired-mode))
  :config
  (setq dirvish-use-mode-line nil
        dirvish-side-auto-expand nil)
  (when (require 'dirvish-subtree nil t)
    (setopt dirvish-subtree-state-style 'nerd))
  ;; 鼠标左键打开文件/切换目录子树
  ;; Dirvish 文档推荐绑定（docs/CUSTOMIZING.org）
  (define-key dirvish-mode-map [mouse-1] #'dirvish-subtree-toggle-or-open))

(defun custom--ensure-dirvish-loaded ()
  "在可用时加载 Dirvish，并返回是否加载成功。"
  (and (locate-library "dirvish")
       (require 'dirvish nil t)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 状态管理
;; ═════════════════════════════════════════════════════════════════════════════

;; 使用单一 frame parameter 存储 plist，统一管理所有工作区状态：
;;   (:active BOOL :initialized BOOL :transitioning BOOL :windows ALIST)
;;
;; :active        — 布局是否已激活
;; :initialized   — 是否已完成一次布局初始化（防止重复触发）
;; :transitioning — 是否正在切换/重建布局
;; :windows       — alist，格式 ((treemacs . <win>) (editor . <win>) ...)

(defun custom--workspace-frame (&optional frame)
  "返回工作区操作的目标 FRAME。"
  (or frame (selected-frame)))

(defun custom--workspace-get-state (&optional frame)
  "返回 FRAME 的工作区状态 plist。"
  (or (frame-parameter (custom--workspace-frame frame) 'custom--workspace-state)
      (list :active nil :initialized nil :transitioning nil :windows nil)))

(defun custom--workspace-set-state (state &optional frame)
  "设置 FRAME 的工作区状态为 STATE plist。"
  (set-frame-parameter (custom--workspace-frame frame) 'custom--workspace-state state))

(defun custom--workspace-state-ref (key &optional frame)
  "从 FRAME 的状态 plist 中获取 KEY 对应的值。"
  (plist-get (custom--workspace-get-state frame) key))

(defun custom--workspace-state-set (key value &optional frame)
  "在 FRAME 的状态 plist 中设置 KEY 为 VALUE。"
  (custom--workspace-set-state
   (plist-put (custom--workspace-get-state frame) key value)
   frame))

;; ── 便捷访问器 ──

(defun custom--workspace-layout-active-p (&optional frame)
  "返回 FRAME 的工作区是否已激活。"
  (custom--workspace-state-ref :active frame))

(defun custom--workspace-set-layout-active (value &optional frame)
  "设置 FRAME 的工作区激活状态为 VALUE。"
  (custom--workspace-state-set :active value frame))

(defun custom--workspace-windows-state (&optional frame)
  "返回 FRAME 的工作区窗口记录。"
  (custom--workspace-state-ref :windows frame))

(defun custom--workspace-set-windows-state (value &optional frame)
  "设置 FRAME 的工作区窗口记录为 VALUE。"
  (custom--workspace-state-set :windows value frame))

(defun custom--workspace-layout-initialized-p (&optional frame)
  "返回 FRAME 是否已完成布局初始化。"
  (custom--workspace-state-ref :initialized frame))

(defun custom--workspace-set-layout-initialized (value &optional frame)
  "设置 FRAME 的布局初始化状态为 VALUE。"
  (custom--workspace-state-set :initialized value frame))

(defun custom--workspace-transitioning-state-p (&optional frame)
  "返回 FRAME 是否正在切换工作区。"
  (custom--workspace-state-ref :transitioning frame))

(defun custom--workspace-set-transitioning (value &optional frame)
  "设置 FRAME 的工作区切换状态为 VALUE。"
  (custom--workspace-state-set :transitioning value frame))

;; ── 状态操作 ──

(defun custom--workspace-window-list (&optional frame)
  "返回 FRAME 内参与工作区逻辑的窗口列表。"
  (window-list (custom--workspace-frame frame) 'nomini))

(defun custom--workspace-minimap-buffer-p (buffer)
  "判断 BUFFER 是否为 minimap buffer。"
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (or (bound-and-true-p minimap-sb-mode)
          (eq major-mode 'minimap-mode)
          (string= (buffer-name buffer) " *MINIMAP*")))))

(defun custom--workspace-live-window-p (window)
  "判断 WINDOW 是否仍是可用的 live window。"
  (and (windowp window)
       (window-live-p window)))

(defun custom--workspace-reset-state ()
  "重置工作区布局状态记录。"
  (custom--workspace-set-state
   (list :active nil :initialized nil :transitioning nil :windows nil)))

(defun custom--workspace-state-stale-p ()
  "判断当前记录的工作区状态是否已经失效。"
  (and (custom--workspace-layout-active-p)
       (not (seq-some (lambda (entry)
                         (custom--workspace-live-window-p (cdr entry)))
                       (custom--workspace-windows-state)))))

(defun custom--workspace-maybe-reset-stale-state (&rest _)
  "在布局窗口都已失效时清理残留工作区状态。"
  (when (custom--workspace-state-stale-p)
    (custom--workspace-cancel-treemacs-timers)
    (custom--workspace-reset-state)))

(defun custom--workspace-remember-window (kind window)
  "记录 KIND 对应的 WINDOW 引用。"
  (when (window-live-p window)
    (set-window-parameter window 'custom--workspace-pane kind))
  (let ((state (custom--workspace-windows-state)))
    (setf (alist-get kind state) window)
    (custom--workspace-set-windows-state state))
  window)

(defun custom--workspace-refresh-window-records ()
  "根据当前窗口布局刷新特殊窗口记录。"
  (custom--workspace-set-windows-state nil)
  (custom--find-treemacs-window)
  (custom--find-terminal-window)
  (custom--workspace-remember-window 'minimap (custom--find-minimap-window))
  (custom--find-editor-window)
  (custom--workspace-maybe-reset-stale-state)
  (custom--workspace-windows-state))

(defun custom--workspace-cancel-treemacs-timers ()
  "取消布局切换前残留的 Treemacs 延迟任务。"
  (when (fboundp 'treemacs--apply-annotations-deferred)
    (cancel-function-timers #'treemacs--apply-annotations-deferred))
  (when (fboundp 'treemacs--follow)
    (cancel-function-timers #'treemacs--follow))
  (when (fboundp 'custom--treemacs-cancel-nav-timer)
    (custom--treemacs-cancel-nav-timer)))

(defun custom--workspace-should-create-minimap-p (&optional frame)
  "判断是否应该创建 minimap。终端模式下返回 nil。"
  (and (display-graphic-p (or frame (selected-frame)))
       (fboundp 'minimap-mode)))

;; ── 窗口保护 ──

(defun custom--workspace-protect-window (win &optional preserve-size)
  "为 WIN 重新施加工作区保护参数。"
  (when (window-live-p win)
    (set-window-parameter win 'no-other-window t)
    (set-window-parameter win 'no-delete-other-windows t)
    (set-window-dedicated-p win t)
    (when preserve-size
      (window-preserve-size win t t))))

(defun custom--workspace-mark-window (win kind &optional preserve-size)
  "将 WIN 标记为 KIND 对应的工作区窗口，并施加保护。"
  (when (window-live-p win)
    (set-window-parameter win 'custom--workspace-pane kind)
    (custom--workspace-remember-window kind win)
    (custom--workspace-protect-window win preserve-size)))

(defun custom--workspace-apply-window-protections ()
  "为当前布局中的特殊窗口重新施加保护参数。"
  (let ((treemacs-win (custom--find-treemacs-window))
        (terminal-win (custom--find-terminal-window))
        (minimap-win (custom--find-minimap-window)))
    (custom--workspace-mark-window treemacs-win 'treemacs t)
    (custom--workspace-mark-window terminal-win 'terminal nil)
    (when (window-live-p terminal-win)
      (set-window-parameter terminal-win 'custom--terminal t))
    (custom--workspace-mark-window minimap-win 'minimap t)))

(defun custom--workspace-prune-terminal-windows ()
  "确保当前 frame 只保留一个 terminal 窗口。"
  (let* ((terminal-windows
          (seq-filter
           (lambda (win)
             (or (eq (window-parameter win 'custom--workspace-pane) 'terminal)
                 (window-parameter win 'custom--terminal)
                 (with-current-buffer (window-buffer win)
                   (derived-mode-p 'vterm-mode 'term-mode 'shell-mode 'eshell-mode))))
           (custom--workspace-window-list)))
         (primary-terminal
          (or (cdr (assoc 'terminal (custom--workspace-windows-state)))
              (car terminal-windows))))
    (when (window-live-p primary-terminal)
      (dolist (win terminal-windows)
        (unless (eq win primary-terminal)
          (set-window-parameter win 'custom--terminal nil)
          (set-window-parameter win 'custom--terminal-buffer nil)
          (set-window-parameter win 'custom--workspace-pane nil)
          (set-window-dedicated-p win nil)
          (ignore-errors (delete-window win)))))))

(defun custom--workspace-sync-pane-state ()
  "重新识别并同步当前 frame 的 pane 元数据。"
  (when (custom--workspace-layout-active-p)
    (custom--workspace-prune-terminal-windows)
    (when-let ((treemacs-win (custom--find-treemacs-window)))
      (custom--workspace-mark-window treemacs-win 'treemacs t))
    (when-let ((terminal-win (custom--find-terminal-window)))
      (custom--workspace-mark-window terminal-win 'terminal nil)
      (set-window-parameter terminal-win 'custom--terminal t))
    (when-let ((minimap-win (custom--find-minimap-window)))
      (custom--workspace-mark-window minimap-win 'minimap t))
    (when-let ((editor-win (custom--find-editor-window)))
      (custom--workspace-remember-window 'editor editor-win))))

(defun custom--workspace-ensure-minimap-for-buffer (&optional buffer)
  "必要时为 BUFFER 所在编辑上下文重新拉起 minimap。"
  (let ((target-buffer (or buffer (current-buffer))))
    (when (and (custom--workspace-layout-active-p)
               (custom--workspace-should-create-minimap-p)
               (buffer-live-p target-buffer)
               (with-current-buffer target-buffer
                 buffer-file-name)
               (not (window-live-p (custom--find-minimap-window))))
      (with-current-buffer target-buffer
        (ignore-errors
          (when (fboundp 'minimap-mode)
            (minimap-mode 1))))
      (custom--workspace-sync-pane-state))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 窗口查找函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--find-editor-window ()
  "查找主编辑窗口。
优先使用保存的 editor 窗口引用，否则排除 Treemacs、终端、Minimap 窗口。"
  (or
   ;; 优先使用保存的引用
   (let ((saved-editor (cdr (assoc 'editor (custom--workspace-windows-state)))))
     (when (window-live-p saved-editor)
        saved-editor))
    ;; 否则遍历查找
    (let ((found
           (seq-find
            (lambda (win)
              (let ((buf (window-buffer win)))
                (and (buffer-live-p buf)
                     (not (memq (window-parameter win 'custom--workspace-pane)
                                '(treemacs terminal minimap)))
                     (not (window-parameter win 'window-side))
                     (not (window-parameter win 'custom--terminal))
                     (with-current-buffer buf
                       (and (not (derived-mode-p 'treemacs-mode 'vterm-mode))
                            (not (custom--workspace-minimap-buffer-p buf)))))))
            (custom--workspace-window-list))))
      (when found
        (custom--workspace-remember-window 'editor found)))))

(defun custom--find-treemacs-window ()
  "查找 Treemacs 窗口。"
  (let ((found
         (seq-find
          (lambda (win)
            (or (eq (window-parameter win 'custom--workspace-pane) 'treemacs)
                (with-current-buffer (window-buffer win)
                  (derived-mode-p 'treemacs-mode))))
          (custom--workspace-window-list))))
    (when found
      (custom--workspace-remember-window 'treemacs found))))

(defun custom--find-terminal-window ()
  "查找终端窗口。
优先使用保存的窗口引用，其次按 window-parameter 'custom--terminal 标记查找，
最后按 vterm-mode 查找。"
  (or
   ;; 优先使用保存的引用
   (let ((saved-term (cdr (assoc 'terminal (custom--workspace-windows-state)))))
     (when (window-live-p saved-term)
       saved-term))
   ;; 其次按标记查找
   (seq-find
    (lambda (win)
      (or (eq (window-parameter win 'custom--workspace-pane) 'terminal)
          (window-parameter win 'custom--terminal)))
    (custom--workspace-window-list))
    ;; 最后按 mode 查找
    (let ((found
            (seq-find
             (lambda (win)
               (with-current-buffer (window-buffer win)
                 (derived-mode-p 'vterm-mode 'term-mode 'shell-mode 'eshell-mode)))
             (custom--workspace-window-list))))
       (when found
         (custom--workspace-remember-window 'terminal found)))))

(defun custom--workspace-current-terminal-buffer (&optional frame)
  "返回 FRAME 中当前可复用的终端 buffer。"
  (let* ((target-frame (custom--workspace-frame frame))
         (terminal-win (and (frame-live-p target-frame)
                            (with-selected-frame target-frame
                              (custom--find-terminal-window))))
         (terminal-buffer (and (window-live-p terminal-win)
                               (window-buffer terminal-win))))
    (when (buffer-live-p terminal-buffer)
      terminal-buffer)))

(defun custom--find-minimap-window ()
  "查找 Minimap 窗口。"
  (let ((found
         (seq-find
          (lambda (win)
            (let ((buf (window-buffer win)))
              (or (eq (window-parameter win 'custom--workspace-pane) 'minimap)
                  (custom--workspace-minimap-buffer-p buf))))
          (custom--workspace-window-list))))
    (when found
      (custom--workspace-remember-window 'minimap found))))

(defun custom--find-file-buffer ()
  "查找最近的文件 buffer（排除特殊 buffer）。"
  (seq-find
   (lambda (b)
     (and (buffer-file-name b)
          (not (string-match-p "\\*.*\\*" (buffer-name b)))))
   (buffer-list)))

(defun custom--workspace-context-directory ()
  "返回当前工作区上下文对应的目录。"
  (file-name-as-directory
   (expand-file-name
    (or (when (and (fboundp 'projectile-project-p)
                   (fboundp 'projectile-project-root)
                   (ignore-errors (projectile-project-p)))
          (ignore-errors (projectile-project-root)))
        default-directory
        "~/"))))

(defun custom--workspace-buffer-directory (buffer)
  "返回 BUFFER 对应的实际目录。"
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (file-name-as-directory
       (expand-file-name
        (or (when buffer-file-name
              (file-name-directory buffer-file-name))
            default-directory
            "~/"))))))

(defun custom--workspace-project-root-for-buffer (buffer)
  "返回 BUFFER 对应的项目根目录；若不在项目中则返回 nil。"
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((project-root
             (or (when (and (fboundp 'projectile-project-p)
                            (fboundp 'projectile-project-root)
                            (ignore-errors (projectile-project-p)))
                   (ignore-errors (projectile-project-root)))
                 (when-let ((project (ignore-errors (project-current nil default-directory))))
                   (if (fboundp 'project-root)
                       (ignore-errors (project-root project))
                     (ignore-errors (cdr project))))
                 (locate-dominating-file default-directory ".projectile")
                 (locate-dominating-file default-directory ".git"))))
        (when project-root
          (file-name-as-directory
           (expand-file-name project-root)))))))

(defun custom--workspace-context-for-buffer (buffer &optional fallback-dir)
  "为 BUFFER 计算统一的工作区上下文。

返回 plist，包含：
- `:buffer-dir`：主编辑区文件/目录所在目录
- `:project-root`：若存在则为项目根目录
- `:sync-dir`：其他 pane 应跟随的目录（优先项目根目录，其次文件目录）
- `:treemacs-dir`：Treemacs 应展示/定位的目录（优先项目根）
- `:is-project`：是否处于项目内"
  (let* ((buffer-dir (or (custom--workspace-buffer-directory buffer)
                         (and fallback-dir
                              (file-name-as-directory
                               (expand-file-name fallback-dir)))
                         (custom--workspace-context-directory)))
         (project-root (custom--workspace-project-root-for-buffer buffer))
         (sync-dir (or project-root buffer-dir))
         (treemacs-dir (or project-root buffer-dir)))
    (list :buffer-dir buffer-dir
          :project-root project-root
          :sync-dir sync-dir
          :treemacs-dir treemacs-dir
          :is-project (and project-root t))))

(defun custom--workspace-editor-buffer-p (buffer)
  "判断 BUFFER 是否适合显示在主编辑窗口。"
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (and (not (minibufferp buffer))
           (or buffer-file-name
               (derived-mode-p 'dired-mode))
           (not (derived-mode-p 'treemacs-mode
                                'vterm-mode
                                'term-mode
                                'shell-mode
                                'eshell-mode
                                'dashboard-mode))
           (not (custom--workspace-minimap-buffer-p buffer))))))

(defun custom--workspace-fallback-buffer (&optional dir)
  "为主编辑窗口选择一个稳定的后备 buffer。

DIR 非 nil 时，优先用它作为 dired 后备目录。"
  (or (seq-find #'custom--workspace-editor-buffer-p
                (buffer-list))
      (let ((target-dir (or dir (custom--workspace-context-directory))))
        (when (fboundp 'dired-noselect)
          (dired-noselect target-dir)))
       (custom--find-file-buffer)
       (get-buffer "*scratch*")))

;; ═════════════════════════════════════════════════════════════════════════════
;; 同步辅助函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--workspace-sync-terminal-directory (dir)
  "将终端区域同步到 DIR。"
  (let* ((target-dir (file-name-as-directory (expand-file-name dir)))
         (terminal-win (custom--find-terminal-window))
         (terminal-buffer (and (window-live-p terminal-win)
                               (window-buffer terminal-win))))
    (when (buffer-live-p terminal-buffer)
      (with-current-buffer terminal-buffer
        (let ((old-dir (file-name-as-directory (expand-file-name default-directory))))
          (setq default-directory target-dir)
          (unless (string-equal old-dir target-dir)
            (cond
             ((derived-mode-p 'vterm-mode)
              (when (fboundp 'vterm-send-string)
                (vterm-send-string (format "cd %s" (shell-quote-argument target-dir)))
                (when (fboundp 'vterm-send-return)
                  (vterm-send-return))))
             ((derived-mode-p 'shell-mode)
              (when (fboundp 'comint-simple-send)
                (comint-simple-send (get-buffer-process terminal-buffer)
                                    (format "cd %s" (shell-quote-argument target-dir)))))
             ((derived-mode-p 'term-mode)
              (when (fboundp 'term-send-raw-string)
                (term-send-raw-string
                 (format "cd %s\n" (shell-quote-argument target-dir))))))))))))

(defun custom--workspace-terminal-start-directory ()
  "返回新建终端窗口时应使用的初始目录。"
  (let* ((editor-win (custom--find-editor-window))
         (editor-buffer (and (window-live-p editor-win)
                             (window-buffer editor-win)))
         (context (and (buffer-live-p editor-buffer)
                       (custom--workspace-context-for-buffer editor-buffer))))
    (file-name-as-directory
     (expand-file-name
      (or (plist-get context :sync-dir)
          (plist-get context :buffer-dir)
          default-directory
          "~/")))))

(defun custom--workspace-sync-editor (editor-win target-buffer buffer-dir)
  "将 EDITOR-WIN 同步到 TARGET-BUFFER，设置 BUFFER-DIR。"
  (when (and (window-live-p editor-win)
             (buffer-live-p target-buffer)
             (not (eq (window-buffer editor-win) target-buffer)))
    (set-window-buffer editor-win target-buffer))
  (when (buffer-live-p target-buffer)
    (with-current-buffer target-buffer
      (setq default-directory buffer-dir))))

(defun custom--workspace-sync-treemacs (treemacs-dir is-project target-buffer)
  "将 Treemacs 同步到 TREEMACS-DIR。"
  (when (and (fboundp 'custom/treemacs-navigate-to)
             (window-live-p (custom--find-treemacs-window)))
    (ignore-errors
      (custom/treemacs-navigate-to treemacs-dir is-project
                                   (and (buffer-live-p target-buffer)
                                        (buffer-file-name target-buffer))))))

(defun custom/workspace-sync-current-context (&optional preferred-buffer preferred-dir)
  "在工作区切换后统一同步编辑区、文件树和终端。"
  (interactive)
  (when (custom--workspace-layout-active-p)
    (let* ((fallback-dir (or preferred-dir
                             (custom--workspace-context-directory)))
           (editor-win (custom--find-editor-window))
           (target-buffer (if (custom--workspace-editor-buffer-p preferred-buffer)
                              preferred-buffer
                            (custom--workspace-fallback-buffer fallback-dir)))
           (context (custom--workspace-context-for-buffer target-buffer fallback-dir)))
      (custom--workspace-sync-editor editor-win target-buffer
                                     (plist-get context :buffer-dir))
      (custom--workspace-sync-terminal-directory (plist-get context :sync-dir))
      (custom--workspace-ensure-minimap-for-buffer target-buffer)
      (custom--workspace-sync-pane-state)
      (custom--workspace-sync-treemacs (plist-get context :treemacs-dir)
                                       (plist-get context :is-project)
                                       target-buffer))))

(defun custom/open-directory-browser (&optional dir)
  "在当前上下文中打开目录浏览器。

如果 Dirvish 可用，则优先使用 `dirvish-dwim'；否则回退到 `dired'。
DIR 非 nil 时，打开对应目录。"
  (interactive)
  (let ((target-dir (file-name-as-directory
                     (expand-file-name
                      (or dir default-directory "~/")))))
    (setq default-directory target-dir)
    (custom--ensure-dirvish-loaded)
    (cond
     ((fboundp 'dirvish-dwim)
      (dirvish-dwim target-dir))
     ((fboundp 'dired)
      (dired target-dir))
     (t
      (user-error "当前环境不可用目录浏览器")))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 布局完整性检查
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--workspace-collect-window-state ()
  "刷新并返回当前布局的窗口状态 alist。"
  (custom--workspace-refresh-window-records)
  (custom--workspace-windows-state))

(defun custom--workspace-check-windows-intact-p (window-state)
  "根据 WINDOW-STATE 检查核心窗口是否完整。

检查编辑器、Treemacs、Minimap 和终端窗口是否存在且处于正确模式。"
  (let* ((treemacs-win (cdr (assoc 'treemacs window-state)))
         (terminal-win (cdr (assoc 'terminal window-state)))
         (minimap-win (cdr (assoc 'minimap window-state)))
         (editor-win (cdr (assoc 'editor window-state))))
    (and (window-live-p editor-win)
         (window-live-p treemacs-win)
         (with-current-buffer (window-buffer treemacs-win)
           (derived-mode-p 'treemacs-mode))
         (or (not (custom--workspace-should-create-minimap-p))
             (window-live-p minimap-win))
         (or (not terminal-win)
             (and (window-live-p terminal-win)
                  (or (with-current-buffer (window-buffer terminal-win)
                        (derived-mode-p 'vterm-mode))
                      (window-parameter terminal-win 'custom--terminal)))))))

(defun custom--workspace-layout-intact-p ()
  "检查工作区布局是否完整。
返回 nil 如果：
- 布局未激活
- Treemacs 窗口不存在或不可见
- 主编辑窗口不存在
- 终端窗口丢失（仅在成功创建过的情况下）"
  (and (custom--workspace-layout-active-p)
       (custom--workspace-check-windows-intact-p
        (custom--workspace-collect-window-state))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 窗口设置辅助函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--setup-treemacs-window (win)
  "设置 Treemacs 窗口参数。"
  (with-selected-window win
    (treemacs)
    (custom--workspace-mark-window win 'treemacs t)))

(defun custom--setup-terminal-window (win)
  "设置终端窗口参数。
复用已有的 vterm buffer（如果存在），否则创建新的。"
  (with-selected-window win
    (let ((display-buffer-overriding-action '((display-buffer-same-window)))
          (target-dir (custom--workspace-terminal-start-directory))
          (existing-vterm (window-parameter win 'custom--terminal-buffer)))
      (cond
       ((buffer-live-p existing-vterm)
        (switch-to-buffer existing-vterm))
       ((fboundp 'vterm)
        (let ((default-directory target-dir))
          (let ((buffer (vterm (generate-new-buffer-name "*vterm*"))))
            (set-window-parameter win 'custom--terminal-buffer buffer))))
       ((fboundp 'custom/open-terminal)
        (let ((buffer (current-buffer))
              (default-directory target-dir))
          (custom/open-terminal)
          (set-window-parameter win 'custom--terminal-buffer (current-buffer))
          (unless (derived-mode-p 'vterm-mode 'term-mode 'shell-mode 'eshell-mode)
            (set-window-buffer win buffer))))
       (t
        (let ((default-directory target-dir))
          (shell)
          (set-window-parameter win 'custom--terminal-buffer (current-buffer))))))
    ;; 设置窗口参数（不设 preserve-size，允许用户调整高度）
    (custom--workspace-mark-window win 'terminal nil)
    ;; 设置标记用于修复时查找
    (set-window-parameter win 'custom--terminal t)))

(defun custom--setup-minimap-window (win)
  "设置 Minimap 窗口参数。"
  (with-selected-window win
    ;; 确保 minimap 包已加载
    (require 'minimap nil t)
    (when (fboundp 'minimap-mode)
      (minimap-mode 1)
      (custom--workspace-mark-window win 'minimap t))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 文件打开控制
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--ensure-file-in-editor-window (orig-fun &rest args)
  "确保文件在主编辑窗口打开，而不是特殊窗口。

关键：不在调用 ORIG-FUN 前切换窗口。
Treemacs 等 UI 组件的 visit 函数依赖当前 buffer/window 中的按钮上下文
（如 treemacs-current-button），提前切走会导致上下文丢失。
改为在文件打开后异步处理：将 buffer 移入编辑窗口并同步路径。"
  (prog1 (apply orig-fun args)
    (when (and (custom--workspace-layout-active-p)
               (buffer-file-name))
      (let ((target-buffer (current-buffer))
            (target-frame (selected-frame)))
        (run-with-idle-timer
         0.05 nil
         (lambda (buf frame)
           (when (and (buffer-live-p buf)
                      (frame-live-p frame))
             (with-selected-frame frame
               (let ((editor-win (custom--find-editor-window)))
                 (when (window-live-p editor-win)
                   (unless (eq (window-buffer editor-win) buf)
                     (set-window-buffer editor-win buf)
                     (select-window editor-win))))
               (custom/workspace-sync-current-context
                buf (buffer-local-value 'default-directory buf)))))
         target-buffer target-frame)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 布局操作主函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--workspace-validate-frame-size (frame terminal-height)
  "验证 FRAME 是否有足够空间创建工作区布局。
TERMINAL-HEIGHT 是终端窗口目标高度。空间不足时发出 `user-error'。"
  (let ((width (frame-width frame))
        (height (frame-height frame)))
    (when (< width 50)
      (user-error "窗口宽度不足 (%d)，至少需要 50 列" width))
    (when (< height (+ terminal-height 6))
      (user-error "窗口高度不足 (%d)，至少需要 %d 行" height (+ terminal-height 6)))))

(defun custom--workspace-split-terminal (editor-win terminal-height &optional terminal-buffer)
  "在 EDITOR-WIN 下方分割终端窗口，高度为 TERMINAL-HEIGHT。
返回终端窗口，空间不足时返回 nil。"
  (let ((editor-h (window-height editor-win)))
    (when (> editor-h (+ terminal-height 4))
      (let ((term-win (split-window editor-win (- terminal-height) 'below)))
        (when (buffer-live-p terminal-buffer)
          (set-window-parameter term-win 'custom--terminal-buffer terminal-buffer))
        (custom--setup-terminal-window term-win)
        term-win))))

(defun custom--workspace-init-treemacs (editor-win)
  "在 EDITOR-WIN 侧边启动 Treemacs。返回 Treemacs 窗口或 nil。"
  (select-window editor-win)
  (condition-case nil
      (progn
        (treemacs)
        (let ((treemacs-win (custom--find-treemacs-window)))
          (when treemacs-win
            (custom--workspace-mark-window treemacs-win 'treemacs t))
          treemacs-win))
    (error (message "[workspace] Treemacs 启动失败，跳过文件树") nil)))

(defun custom--workspace-schedule-minimap (frame target-buffer)
  "延迟为 FRAME 中的 TARGET-BUFFER 创建 Minimap。"
  (when (custom--workspace-should-create-minimap-p)
    (run-with-idle-timer
     0.2 nil
     (lambda (target-frame target-buffer)
       (when (frame-live-p target-frame)
         (with-selected-frame target-frame
           (ignore-errors
             (when-let ((editor (custom--find-editor-window)))
               (select-window editor))
             (custom--workspace-ensure-minimap-for-buffer target-buffer)
             (when-let ((minimap-win (custom--find-minimap-window)))
               (custom--setup-minimap-window minimap-win))
             (custom--workspace-refresh-window-records)
             (custom--workspace-sync-pane-state)
             (when-let ((editor (custom--find-editor-window)))
               (select-window editor))))))
     frame target-buffer)))

(defun custom--workspace-prepare-editor (frame display-buf)
  "在 FRAME 中准备编辑器起始窗口，显示 DISPLAY-BUF。
清理侧边窗口，删除多余窗口，返回编辑器窗口。"
  (dolist (win (custom--workspace-window-list frame))
    (when (window-parameter win 'window-side)
      (ignore-errors (delete-window win))))
  (let ((editor-win (or (seq-find (lambda (win)
                                    (not (window-parameter win 'window-side)))
                                  (custom--workspace-window-list frame))
                        (frame-selected-window frame))))
    (select-window editor-win)
    (delete-other-windows editor-win)
    (switch-to-buffer display-buf)
    editor-win))

(defun custom--workspace-finalize-layout (frame editor-win terminal-win treemacs-win display-buf)
  "在 FRAME 中记录布局状态并注册后续操作。"
  (custom--workspace-set-layout-active t frame)
  (custom--workspace-set-layout-initialized t frame)
  (custom--workspace-remember-window 'treemacs treemacs-win)
  (custom--workspace-remember-window 'editor editor-win)
  (custom--workspace-remember-window 'terminal terminal-win)
  (custom--workspace-refresh-window-records)
  (custom--workspace-schedule-minimap frame display-buf)
  (advice-add 'find-file :around #'custom--ensure-file-in-editor-window)
  (select-window editor-win)
  (message "工作区布局已激活"))

(defun custom--workspace-layout-create (&optional preferred-buffer preferred-dir)
  "创建工作区布局。布局图详见文件 Commentary。
PREFERRED-BUFFER 非 nil 时优先放入编辑窗口。
PREFERRED-DIR 非 nil 时作为后备目录。"
  (let* ((frame (selected-frame))
         (terminal-height (if (display-graphic-p frame) 12 8))
         (display-buf (if (custom--workspace-editor-buffer-p preferred-buffer)
                          preferred-buffer
                         (custom--workspace-fallback-buffer preferred-dir)))
         (reused-terminal-buffer (custom--workspace-current-terminal-buffer frame))
         editor-win terminal-win treemacs-win)
    (custom--workspace-set-transitioning t frame)
    (unwind-protect
        (with-selected-frame frame
          (custom--workspace-validate-frame-size frame terminal-height)
          (custom--workspace-cancel-treemacs-timers)
          (setq editor-win (custom--workspace-prepare-editor frame display-buf))
          (setq terminal-win (custom--workspace-split-terminal
                              editor-win terminal-height reused-terminal-buffer))
          (unless terminal-win
            (message "[workspace] 空间不足，跳过终端"))
          (setq treemacs-win (custom--workspace-init-treemacs editor-win))
          (custom--workspace-finalize-layout
           frame editor-win terminal-win treemacs-win display-buf)
          (custom/workspace-sync-current-context display-buf preferred-dir))
      (custom--workspace-set-transitioning nil frame))))

(defun custom--workspace-clear-window-protections (frame)
  "清除 FRAME 内所有窗口的工作区保护参数。"
  (dolist (win (custom--workspace-window-list frame))
    (set-window-parameter win 'no-delete-other-windows nil)
    (set-window-parameter win 'no-other-window nil)
    (set-window-parameter win 'custom--terminal nil)
    (set-window-parameter win 'custom--workspace-pane nil)
    (set-window-dedicated-p win nil)))

(defun custom--workspace-layout-close ()
  "关闭工作区布局。"
  (let ((frame (selected-frame)))
    (custom--workspace-set-transitioning t frame)
    (unwind-protect
        (with-selected-frame frame
          (custom--workspace-cancel-treemacs-timers)

          (advice-remove 'find-file #'custom--ensure-file-in-editor-window)

          (when (fboundp 'minimap-kill)
            (ignore-errors (minimap-kill)))

          (custom--workspace-clear-window-protections frame)

          (when-let ((editor-win (or (cdr (assoc 'editor (custom--workspace-windows-state frame)))
                                     (seq-find (lambda (win)
                                                 (not (window-parameter win 'window-side)))
                                               (custom--workspace-window-list frame))
                                     (frame-selected-window frame))))
            (select-window editor-win)
            (delete-other-windows editor-win))

          (custom--workspace-reset-state)
          (message "工作区布局已关闭"))
      (custom--workspace-set-transitioning nil frame))))

(defun custom/toggle-workspace-layout ()
  "切换工作区布局。
第一次调用：创建布局
第二次调用：关闭布局，恢复单窗口"
  (interactive)
  (custom/diag "workspace" "切换工作区布局")
  (condition-case err
      (progn
        ;; 关闭 which-key 弹窗
        (when (fboundp 'which-key--hide-popup)
          (ignore-errors (which-key--hide-popup)))

         (if (custom--workspace-layout-active-p)
             (custom--workspace-layout-close)
           (custom--workspace-layout-create)))
    (error
     (message "[workspace] 布局错误: %s" (error-message-string err)))))

(defun custom/ensure-workspace-layout (&optional preferred-buffer preferred-dir)
  "确保当前工作区布局已处于稳态。

PREFERRED-BUFFER 和 PREFERRED-DIR 会传递给布局创建/同步逻辑。"
  (interactive)
  (custom--workspace-maybe-reset-stale-state)
  (if (custom--workspace-layout-active-p)
      (progn
        (unless (custom--workspace-layout-intact-p)
          (custom--workspace-layout-create preferred-buffer preferred-dir))
        (custom/workspace-sync-current-context preferred-buffer preferred-dir))
    (custom--workspace-layout-create preferred-buffer preferred-dir)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Treemacs 文件定位
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/treemacs-reveal-current-file ()
  "在 Treemacs 中定位当前文件。"
  (interactive)
  (custom/diag "workspace" "定位文件: %s" (or (buffer-file-name) "无文件"))
  (if-let ((file (buffer-file-name)))
      (progn
        (unless (and (fboundp 'treemacs-current-visibility)
                     (eq (treemacs-current-visibility) 'visible))
          (treemacs))
        (if (fboundp 'custom--treemacs-reveal-path)
            (custom--treemacs-reveal-path file)
          (message "Treemacs 未提供文件定位命令")))
    (message "当前缓冲区没有关联文件")))

;; ═════════════════════════════════════════════════════════════════════════════
;; Dired 行为定制
;; ═════════════════════════════════════════════════════════════════════════════

;; 启用 dired-find-alternate-file（默认被禁用）
(put 'dired-find-alternate-file 'disabled nil)

;; 使用 dired-mode-hook 统一收口，保证每次进入 dired 都拿到一致的非模态导航键。
(add-hook 'dired-mode-hook
          (lambda ()
            (define-key dired-mode-map (kbd "RET") #'dired-find-alternate-file)
            (define-key dired-mode-map (kbd "C-m") #'dired-find-alternate-file)
            (define-key dired-mode-map (kbd "a") #'dired-find-alternate-file)
            (define-key dired-mode-map (kbd "h") #'dired-up-directory)
            (define-key dired-mode-map (kbd "j") #'dired-next-line)
            (define-key dired-mode-map (kbd "k") #'dired-previous-line)
            (define-key dired-mode-map (kbd "l") #'dired-find-alternate-file)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 目录打开处理
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/open-directory (dir)
  "打开目录：设置为工作目录，显示 Treemacs，触发布局。"
  (interactive "DOpen directory: ")
  (when (file-directory-p dir)
    (let ((target-dir (file-name-as-directory dir))
          (frame (selected-frame)))
      (setq default-directory target-dir)
      (custom--ensure-dirvish-loaded)
      ;; 延迟触发布局，避免窗口冲突
      (run-with-idle-timer
       0.2 nil
       (lambda (target-frame open-dir)
         (when (frame-live-p target-frame)
           (with-selected-frame target-frame
             (let ((target-buffer (ignore-errors
                                    (dired-noselect open-dir))))
              (custom/ensure-workspace-layout target-buffer open-dir)
              (when-let ((editor-win (custom--find-editor-window)))
                (when (and (window-live-p editor-win)
                           (buffer-live-p target-buffer))
                  (set-window-buffer editor-win target-buffer)
                  (with-current-buffer target-buffer
                    (setq default-directory (file-name-as-directory open-dir)))))
                ;; 在 Treemacs 中切换到目录根；非项目目录也应能正常显示。
                (when (fboundp 'custom/treemacs-navigate-to)
                  (custom/treemacs-navigate-to open-dir nil open-dir))
                (custom--workspace-sync-pane-state)))))
        frame target-dir))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 自动布局触发
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--workspace-auto-layout-request-p (&optional buffer)
  "判断 BUFFER 是否满足自动布局的基础触发条件。"
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (and buffer-file-name
           (not (derived-mode-p 'dashboard-mode))
           (not (minibufferp buffer))))))

(defun custom--workspace-buffer-visible-in-frame-p (buffer frame)
  "判断 BUFFER 当前是否仍显示在 FRAME 中。"
  (and (buffer-live-p buffer)
       (frame-live-p frame)
       (seq-some (lambda (win)
                   (eq (window-buffer win) buffer))
                 (custom--workspace-window-list frame))))

(defun custom--workspace-should-run-auto-layout-p (frame buffer)
  "判断 FRAME 中是否仍应为 BUFFER 执行自动布局。"
  (and (custom--workspace-auto-layout-request-p buffer)
       (frame-live-p frame)
       (not (custom--workspace-layout-active-p frame))
       (not (custom--workspace-layout-initialized-p frame))
       (not (custom--workspace-transitioning-state-p frame))
       (custom--workspace-buffer-visible-in-frame-p buffer frame)))

(defun custom--workspace-run-auto-layout (frame buffer dir)
  "为 FRAME 中的 BUFFER 执行自动布局。

执行前会再次确认 BUFFER 仍是当前 frame 的可见文件 buffer，
避免用户在 idle timer 触发前切到 dashboard、游戏等非编辑上下文时
误创建工作区布局。DIR 为当时记录的工作目录。"
  (condition-case err
      (when (custom--workspace-should-run-auto-layout-p frame buffer)
        (with-selected-frame frame
          (unless (custom--workspace-layout-active-p)
            (custom/ensure-workspace-layout buffer dir))))
    (error
     (message "[workspace] Auto-layout failed: %s" (error-message-string err))
     (custom--workspace-set-transitioning nil frame)
     (custom--workspace-set-layout-initialized nil frame))))

(defun custom--workspace-schedule-auto-layout ()
  "为当前文件 buffer 安排一次延迟自动布局。"
  (custom--workspace-maybe-reset-stale-state)
  (when (and (custom--workspace-auto-layout-request-p (current-buffer))
             (not (custom--workspace-layout-active-p))
             (not (custom--workspace-layout-initialized-p))
             (not (custom--workspace-transitioning-state-p)))
    (let ((target-buffer (current-buffer))
          (target-dir default-directory)
          (frame (selected-frame)))
      ;; 延迟触发，让 find-file 完整执行完毕后再创建布局
      (run-with-idle-timer
       0.1 nil
       (lambda (target-frame buffer dir)
         (custom--workspace-run-auto-layout target-frame buffer dir))
       frame target-buffer target-dir))))

(defun custom--trigger-layout-on-file ()
  "打开文件时自动触发布局（仅触发一次）。
使用延迟触发，避免在 find-file-hook 中同步修改窗口配置，
导致与 find-file 后续的 switch-to-buffer 冲突造成窗口分裂。"
  (custom--workspace-schedule-auto-layout))

(defun custom--trigger-layout-on-server-switch ()
  "在 `server-switch-hook' 中为 emacsclient 缓冲切换补触发布局。"
  (custom--workspace-schedule-auto-layout))

(defun custom--workspace-handle-frame-deletion (frame)
  "在 FRAME 删除时清理该 frame 的工作区状态。"
  (when (frame-live-p frame)
    (with-selected-frame frame
      (custom--workspace-cancel-treemacs-timers)
      (custom--workspace-reset-state))))

(add-hook 'find-file-hook #'custom--trigger-layout-on-file)
(when (boundp 'server-switch-hook)
  (add-hook 'server-switch-hook #'custom--trigger-layout-on-server-switch))
(add-hook 'delete-frame-functions #'custom--workspace-handle-frame-deletion)

;; ═════════════════════════════════════════════════════════════════════════════
;; Git 集成增强
;; ═════════════════════════════════════════════════════════════════════════════

;; diff-hl 与 Magit 联动：Magit 刷新后同步更新编辑区差异指示
(with-eval-after-load 'magit
  (with-eval-after-load 'diff-hl
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 快捷键
;; ═════════════════════════════════════════════════════════════════════════════

(global-set-key (kbd "<f5>") #'custom/toggle-workspace-layout)

(provide 'workspace)
;;; workspace.el ends here
