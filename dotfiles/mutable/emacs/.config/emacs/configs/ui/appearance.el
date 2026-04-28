;;; appearance.el --- 界面外观配置 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置主题、字体、行号、模式行等视觉元素。
;;
;; 核心机制 — `custom/apply-frame-appearance':
;; 所有 display-dependent（依赖 GUI/TTY 类型）的设置集中在此函数中，
;; 它是 standalone 和 daemon 模式的统一入口：
;;   - standalone: 加载时直接调用
;;   - daemon: 通过 `custom/register-daemon-frame-hook' 统一注册
;; 覆盖的设置：cursor-type、字体高度、tab-line、window-divider、
;; doom-modeline 高度/图标、ef-themes take-over、终端 ANSI face colors。
;;
;; 标签栏策略：使用 Emacs 内建 `tab-line'，不再依赖 `centaur-tabs'。
;; 原因是 `centaur-tabs' 的 tabset 与 buffer/group 缓存是全局状态，
;; 在 daemon + 多个 emacsclient frame 下天然容易互相污染。
;; `tab-line' 是窗口局部机制，更适合当前配置的 daemon/client 工作流。
;;
;; 标签栏视觉策略：外观尽量贴近 JetBrains / VSCode 一类 IDE。
;; - 当前标签使用更接近编辑区的背景，并加一条强调色下划线
;; - 非当前标签保持统一块状留白，避免终端里文字紧贴在一起
;; - 左右滚动与关闭按钮统一改成更稳定的文本按钮，兼顾 GUI/TTY
;; - 鼠标提示与行为说明尽量汉化，便于直接理解标签栏交互
;;
;; 多 client frame 隔离策略：
;; - 每个 frame 使用 frame parameter `custom--frame-tab-buffers' 维护独立的标签缓冲区列表
;; - 缓冲区通过 `find-file-hook'、`window-buffer-change-functions' 等自动注册到当前 frame
;; - 关闭标签仅从当前 frame 的列表中移除，不影响其他 frame
;; - 切换项目时（Projectile hook）自动清空标签列表，重建新项目上下文
;; - 标签切换默认优先作用于工作区主编辑窗口，避免 Treemacs / 终端窗口抢走标签上下文
;; - 特殊窗口（Dashboard、Treemacs、终端、帮助等）不显示标签栏，也不会进入标签列表
;; - `C-x t g` 刷新当前 frame 的标签上下文并重建标签列表
;;
;; menu-bar/tool-bar/scroll-bar 通过 `default-frame-alist' 在顶层禁用，
;; 对所有 frame 类型（standalone/daemon GUI/daemon TTY）统一生效。
;;
;; 终端模式适配策略 (emacs -nw)：
;; - 关键检测：(display-graphic-p) 返回 nil 时为终端模式
;; - 尊重终端配色：不加载 ef-themes 主题，不设置 frame 背景色
;; - ANSI 颜色策略：使用 ANSI 名称（如 "cyan"、"brightblack"）替代 RGB 纯色
;;   ANSI 名称自动映射到终端自身调色板，与终端主题保持一致
;; - 涵盖元素：右键菜单、补全弹窗、当前行高亮、括号匹配、搜索高亮、
;;   行号、模式行、标签栏、which-key 等
;;
;; GUI 专属功能降级（在其他配置文件中处理）：
;; - eldoc-box (childframe) → echo area 多行显示
;; - pixel-scroll → 不启用
;; - minimap / sidebar → 工作区布局中不自动显示
;; - kind-icon (SVG) → Nerd Font 文字图标替代
;; - diff-hl (fringe) → margin 方式显示
;; - doom-modeline 图标 → 禁用，紧凑高度
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 背景透明度
;; ═════════════════════════════════════════════════════════════════════════════

;; 仅 GUI 生效，终端不支持。
;; 值为 0~100 的整数，100 表示完全不透明，56 表示约 56% 不透明。
(defcustom custom:frame-background-opacity 92
  "GUI frame 背景透明度（0~100，100 = 不透明）。"
  :type 'integer
  :group 'faces)

;; ═════════════════════════════════════════════════════════════════════════════
;; 界面简化
;; ═════════════════════════════════════════════════════════════════════════════

;; 通过 default-frame-alist 禁用菜单栏、工具栏、滚动条
;; 此方式对 daemon 模式友好：新 frame 创建时自动继承这些参数
(dolist (param '((menu-bar-lines . 0)
                 (tool-bar-lines . 0)
                 (vertical-scroll-bars)
                 (horizontal-scroll-bars)))
  (unless (assq (car param) default-frame-alist)
    (push param default-frame-alist)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 行号显示
;; ═════════════════════════════════════════════════════════════════════════════

;; 使用相对行号（类似 Vim）
;; 相对行号便于使用 Vim 风格的跳转命令（如 5j 向下跳 5 行）
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

;; 在某些模式下禁用行号（终端、文件树等不需要行号）
(dolist (mode '(vterm-mode term-mode eshell-mode shell-mode
                treemacs-mode dashboard-mode special-mode))
  (add-hook (intern (concat (symbol-name mode) "-hook"))
            (lambda () (display-line-numbers-mode -1))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 标签栏和鼠标支持
;; ═════════════════════════════════════════════════════════════════════════════

;; 关闭内置 tab-bar，改用 window-local `tab-line` 作为文件标签栏。
(tab-bar-mode -1)

(defconst custom:tabs-hidden-modes
  '(dashboard-mode treemacs-mode vterm-mode term-mode eshell-mode shell-mode
    help-mode helpful-mode special-mode completion-list-mode)
  "不显示在标签栏中的 major mode 列表。")

(defconst custom:tabs-name-max-width 36
  "单个标签名最大宽度。")

(defun custom/tab-visible-p (buffer)
  "判断 BUFFER 是否应该显示在标签栏中。"
  (let ((name (buffer-name buffer)))
    (with-current-buffer buffer
      (not (or (minibufferp buffer)
               (string-prefix-p " " name)
               (string-prefix-p "*" name)
               (apply #'derived-mode-p custom:tabs-hidden-modes))))))

(require 'tab-line)

(defun custom--tabs-target-window (&optional window)
  "返回标签命令应优先操作的 WINDOW。"
  (or (and (window-live-p window) window)
      (and (fboundp 'custom--find-editor-window)
           (let ((editor-window (ignore-errors (custom--find-editor-window))))
             (and (window-live-p editor-window)
                  editor-window)))
      (selected-window)))

(defun custom--tabs-collect-window-history (window)
  "收集 WINDOW 的当前 buffer 与前后历史 buffer。"
  (let (buffers)
    (when (window-live-p window)
      (push (window-buffer window) buffers)
      (dolist (entry (window-prev-buffers window))
        (when (buffer-live-p (car entry))
          (push (car entry) buffers)))
      (when (fboundp 'window-next-buffers)
        (dolist (buffer (window-next-buffers window))
          (when (buffer-live-p buffer)
            (push buffer buffers)))))
    buffers))

;; ── Per-frame 标签缓冲区跟踪 ──

(defun custom--tabs-get-frame-buffer-list (&optional frame)
  "返回 FRAME 的标签缓冲区列表。"
  (frame-parameter (or frame (selected-frame)) 'custom--frame-tab-buffers))

(defun custom--tabs-set-frame-buffer-list (buffers &optional frame)
  "设置 FRAME 的标签缓冲区列表为 BUFFERS。"
  (set-frame-parameter (or frame (selected-frame)) 'custom--frame-tab-buffers buffers))

(defun custom--tabs-register-buffer (buffer &optional frame)
  "将 BUFFER 注册到 FRAME 的标签列表尾部（去重）。"
  (let* ((target-frame (or frame (selected-frame)))
         (buffers (or (custom--tabs-get-frame-buffer-list target-frame) '())))
    (unless (memq buffer buffers)
      (custom--tabs-set-frame-buffer-list
       (append buffers (list buffer))
       target-frame))))

(defun custom--tabs-unregister-buffer (buffer &optional frame)
  "从 FRAME 的标签列表中移除 BUFFER。"
  (let* ((target-frame (or frame (selected-frame)))
         (buffers (or (custom--tabs-get-frame-buffer-list target-frame) '())))
    (when (memq buffer buffers)
      (custom--tabs-set-frame-buffer-list
       (delq buffer buffers)
       target-frame))))

(defun custom--tabs-register-current-buffer ()
  "将当前缓冲区注册到当前 frame 的标签列表。"
  (when (and (not (minibufferp))
             (custom/tab-visible-p (current-buffer)))
    (custom--tabs-register-buffer (current-buffer))))

(defun custom--tabs-on-window-buffer-change (frame-or-window)
  "当缓冲区变更时，将新缓冲区注册到对应 frame 的标签列表。
FRAME-OR-WINDOW 可以是 frame（全局 hook 传入）或 window（buffer-local hook 传入）。"
  (cond
   ((frame-live-p frame-or-window)
    (walk-windows
     (lambda (window)
       (when (eq (window-frame window) frame-or-window)
         (let ((buffer (window-buffer window)))
           (when (and (buffer-live-p buffer)
                      (custom/tab-visible-p buffer)
                      (not (minibufferp buffer))
                      (let ((pane (window-parameter window 'custom--workspace-pane)))
                        (or (null pane) (eq pane 'editor))))
             (custom--tabs-register-buffer buffer frame-or-window)))))
     'no-mini frame-or-window))
   ((window-live-p frame-or-window)
    (let ((buffer (window-buffer frame-or-window))
          (frame (window-frame frame-or-window)))
      (when (and (buffer-live-p buffer)
                 (custom/tab-visible-p buffer)
                 (not (minibufferp buffer))
                 (let ((pane (window-parameter frame-or-window 'custom--workspace-pane)))
                   (or (null pane) (eq pane 'editor))))
        (custom--tabs-register-buffer buffer frame))))))

(defun custom--tabs-on-kill-buffer ()
  "当缓冲区被关闭时，从所有 frame 的标签列表中移除。"
  (let ((buffer (current-buffer)))
    (dolist (frame (frame-list))
      (when (frame-live-p frame)
        (let ((buffers (custom--tabs-get-frame-buffer-list frame)))
          (when (memq buffer buffers)
            (custom--tabs-set-frame-buffer-list (delq buffer buffers) frame)))))))

(defun custom/tabs-clear-for-frame (&optional frame)
  "清空 FRAME 的标签缓冲区列表。
仅清除 frame parameter 和 tab-line 缓存，不重建标签列表。
项目切换时由后续 find-file/server-switch 等 hook 自然重建。"
  (interactive)
  (let ((target-frame (or frame (selected-frame))))
    (custom--tabs-set-frame-buffer-list nil target-frame)
    ;; 仅清除 tab-line 缓存，触发视觉刷新，不重建标签列表
    (walk-windows
     (lambda (window)
       (when (eq (window-frame window) target-frame)
         (set-window-parameter window 'tab-line-cache nil)))
     'no-mini target-frame)
    (when (called-interactively-p 'interactive)
      (message "已清空当前 frame 的标签列表"))))

(defun custom--tabs-on-frame-deletion (frame)
  "FRAME 删除时清理标签状态。"
  (custom--tabs-set-frame-buffer-list nil frame))


(defun custom--tabs-frame-buffers (&optional window)
  "返回 WINDOW 所在 frame 的标签缓冲区列表。
仅返回通过 `custom--tabs-register-buffer' 注册且仍然存活的缓冲区。"
  (let* ((target-window (custom--tabs-target-window window))
         (target-frame (window-frame target-window))
         (frame-buffers (custom--tabs-get-frame-buffer-list target-frame)))
    (seq-filter (lambda (buf)
                  (and (buffer-live-p buf)
                       (custom/tab-visible-p buf)))
                (or frame-buffers '()))))


(defun custom/tab-line-tabs ()
  "返回当前窗口标签栏要展示的 buffer 列表。"
  (or (custom--tabs-frame-buffers (selected-window))
      (list (current-buffer))))

(defun custom/tab-line-tab-name (buffer &optional _buffers)
  "生成 BUFFER 的标签名。"
  (let* ((name (truncate-string-to-width
                (buffer-name buffer)
                custom:tabs-name-max-width 0 nil t))
         (icon (when (and (display-graphic-p)
                          (require 'nerd-icons nil t))
                 (with-current-buffer buffer
                   (nerd-icons-icon-for-buffer))))
         (prefix (if (and (stringp icon)
                          (not (string-empty-p icon)))
                     (concat icon " ")
                   ""))
         (suffix (if (buffer-modified-p buffer) " ●" "")))
    (concat prefix name suffix)))

(defun custom--tab-line-help-echo (selected-p)
  "返回标签的中文提示文本。SELECTED-P 表示是否为当前标签。"
  (if selected-p
      "当前标签：鼠标中键关闭，右键打开菜单"
    "左键切换标签，鼠标中键关闭，右键打开菜单"))

(defun custom--tab-line-close-button (face selected-p)
  "返回标签关闭按钮文本。FACE 为标签 face，SELECTED-P 表示是否当前标签。"
  (let ((show-close (and tab-line-close-button-show
                         (not (eq tab-line-close-button-show
                                  (if selected-p 'non-selected 'selected))))))
    (if (not show-close)
        ""
      (let ((close (copy-sequence tab-line-close-button)))
        (add-face-text-property 0 (length close) face t close)
        close))))

(defun custom/tab-line-tab-name-format (tab tabs)
  "以更接近 IDE 的样式格式化 TAB。
TABS 为当前窗口全部标签列表。"
  (let* ((buffer-p (bufferp tab))
         (selected-p (if buffer-p
                         (eq tab (window-buffer))
                       (cdr (assq 'selected tab))))
         (name (if buffer-p
                   (funcall tab-line-tab-name-function tab tabs)
                 (cdr (assq 'name tab))))
         (face (if selected-p
                   (if (mode-line-window-selected-p)
                       'tab-line-tab-current
                     'tab-line-tab)
                 'tab-line-tab-inactive))
           (label (concat " " (string-replace "%" "%%" name)))
         close
         (help-echo (custom--tab-line-help-echo selected-p)))
    (dolist (fn tab-line-tab-face-functions)
      (setq face (funcall fn tab tabs face buffer-p selected-p)))
    (setq close (custom--tab-line-close-button face selected-p))
    (apply #'propertize
           (concat
            (propertize label
                        'face face
                        'keymap tab-line-tab-map
                        'help-echo help-echo
                        'follow-link 'ignore)
             close)
            `(tab ,tab
                 ,@(if selected-p '(selected t))
                 mouse-face tab-line-highlight))))

(defun custom/apply-tab-line-button-preset ()
  "应用统一的标签栏按钮文本样式。"
  (setq tab-line-close-button
        (propertize " x "
                    'rear-nonsticky nil
                    'keymap tab-line-tab-close-map
                    'mouse-face 'tab-line-close-highlight
                    'help-echo "关闭标签")
        tab-line-left-button
        (propertize " < "
                    'rear-nonsticky nil
                    'keymap tab-line-left-map
                    'mouse-face 'tab-line-highlight
                    'help-echo "向左滚动标签栏")
        tab-line-right-button
        (propertize " > "
                    'rear-nonsticky nil
                    'keymap tab-line-right-map
                    'mouse-face 'tab-line-highlight
                    'help-echo "向右滚动标签栏")))

(defun custom/apply-tab-line-face-preset ()
  "应用更接近 JetBrains / VSCode 的标签栏外观。"
  (let* ((valid-bg (lambda (val) (and val (not (string-prefix-p "unspecified" val)) val)))
         (default-bg (or (funcall valid-bg (face-background 'default nil t))
                         (funcall valid-bg (face-background 'default nil 'default))
                         "#282c34"))
         (default-fg (or (funcall valid-bg (face-foreground 'default nil t))
                         (funcall valid-bg (face-foreground 'default nil 'default))
                         "#bbc2cf"))
         (accent-fg (or (funcall valid-bg (face-foreground 'cursor nil t))
                        (funcall valid-bg (face-foreground 'font-lock-keyword-face nil t))
                        default-fg))
         (mode-line-bg (or (funcall valid-bg (face-background 'mode-line nil t)) default-bg))
         (mode-line-inactive-bg (or (funcall valid-bg (face-background 'mode-line-inactive nil t))
                                    mode-line-bg))
         (mode-line-inactive-fg (or (funcall valid-bg (face-foreground 'mode-line-inactive nil t))
                                    default-fg))
         (shadow-fg (or (funcall valid-bg (face-foreground 'shadow nil t)) mode-line-inactive-fg)))
    (set-face-attribute 'tab-line nil
                        :background mode-line-inactive-bg
                        :foreground mode-line-inactive-fg
                        :box nil
                        :height 0.95
                        :raise 2)       ; 上移文字，配合 padding 空格撑大行高实现垂直居中
    (set-face-attribute 'tab-line-tab-current nil
                        :background default-bg
                        :foreground default-fg
                        :box nil
                        :weight 'medium
                        :underline `(:color ,accent-fg :position t))
    (set-face-attribute 'tab-line-tab nil
                        :background mode-line-bg
                        :foreground default-fg
                        :box nil
                        :weight 'medium)
    (set-face-attribute 'tab-line-tab-inactive nil
                        :background mode-line-inactive-bg
                        :foreground shadow-fg
                        :box nil)
    (set-face-attribute 'tab-line-highlight nil
                        :background mode-line-bg
                        :foreground default-fg
                        :box nil)
    (set-face-attribute 'tab-line-close-highlight nil
                        :foreground "tomato"
                        :background 'unspecified)
    (set-face-attribute 'tab-line-tab-modified nil
                        :foreground "goldenrod"
                        :background 'unspecified)))

(defun custom--tabs-switch-to-buffer (buffer &optional window)
  "在 WINDOW 中切换到 BUFFER，并刷新标签显示。"
  (when (buffer-live-p buffer)
    (let ((target-window (custom--tabs-target-window window))
          (switch-to-buffer-obey-display-actions nil))
      (with-selected-window target-window
        (switch-to-buffer buffer)
        (tab-line-force-update t)))))

(defun custom/tabs-next (&optional arg)
  "切换到当前标签列表中的下一个标签。ARG 为步数。"
  (interactive "p")
  (let* ((target-window (custom--tabs-target-window))
         (buffers (custom--tabs-frame-buffers target-window))
         (current (window-buffer target-window))
         (position (seq-position buffers current))
         (step (or arg 1)))
    (when (and position buffers)
      (custom--tabs-switch-to-buffer
       (nth (mod (+ position step) (length buffers)) buffers)
       target-window))))

(defun custom/tabs-previous (&optional arg)
  "切换到当前标签列表中的上一个标签。ARG 为步数。"
  (interactive "p")
  (custom/tabs-next (- (or arg 1))))

(defun custom/tabs-select-index (index)
  "切换到当前标签列表中的第 INDEX 个标签。"
  (interactive)
  (let* ((target-window (custom--tabs-target-window))
         (buffers (custom--tabs-frame-buffers target-window))
         (buffer (nth (1- index) buffers)))
    (if buffer
        (custom--tabs-switch-to-buffer buffer target-window)
      (user-error "当前标签数量不足 %d 个" index))))

(defun custom/tabs-close-buffer (&optional window)
  "关闭当前标签，切换到下一个可用标签。"
  (interactive)
  (let* ((target-window (custom--tabs-target-window window))
         (buffer (window-buffer target-window))
         (target-frame (window-frame target-window))
         (frame-buffers (or (custom--tabs-get-frame-buffer-list target-frame) '()))
         (remaining (delq buffer frame-buffers))
         ;; 过滤掉已死或不可见的候选，找到第一个有效切换目标
         (valid-next (seq-find (lambda (b)
                                 (and (buffer-live-p b)
                                      (custom/tab-visible-p b)))
                               remaining)))
    (custom--tabs-unregister-buffer buffer target-frame)
    (cond
     (valid-next
      (custom--tabs-switch-to-buffer valid-next target-window))
     (t
      (with-selected-window target-window
        (bury-buffer buffer)
        (let ((fallback (seq-find (lambda (b)
                                    (and (buffer-live-p b)
                                         (not (eq b buffer))))
                                  (buffer-list target-frame))))
          (when fallback
            (switch-to-buffer fallback)))
         (tab-line-force-update t))))))

(defun custom/tab-line-close-tab (tab)
  "鼠标关闭按钮回调：从当前 frame 标签列表注销缓冲区并切换。
TAB 由 `tab-line-close-tab-function' 传入，为要关闭的 buffer 对象。"
  (interactive)
  (let* ((buffer (if (bufferp tab) tab (current-buffer)))
         (target-window (custom--tabs-target-window))
         (target-frame (window-frame target-window)))
    (when (and buffer (buffer-live-p buffer))
      (let* ((frame-buffers (or (custom--tabs-get-frame-buffer-list target-frame) '()))
             (remaining (delq buffer frame-buffers))
             (valid-next (seq-find (lambda (b)
                                     (and (buffer-live-p b)
                                          (custom/tab-visible-p b)))
                                   remaining)))
        (custom--tabs-unregister-buffer buffer target-frame)
        (if valid-next
            (custom--tabs-switch-to-buffer valid-next target-window)
          (with-selected-window target-window
            (bury-buffer buffer)
            (tab-line-force-update t)))))))

(defun custom/tabs-refresh-context (&optional frame)
  "刷新 FRAME 的标签栏上下文，完全重建标签列表。"
  (interactive)
  (let ((target-frame (or frame (selected-frame))))
    ;; 先清空再收集，确保「刷新=重建」而非追加
    (custom--tabs-set-frame-buffer-list nil target-frame)
    (walk-windows
     (lambda (window)
       (when (eq (window-frame window) target-frame)
         (let ((buffer (window-buffer window)))
           (when (and (buffer-live-p buffer)
                      (custom/tab-visible-p buffer)
                       (let ((pane (window-parameter window 'custom--workspace-pane)))
                         (or (null pane) (eq pane 'editor))))
             (custom--tabs-register-buffer buffer target-frame)))))
     'no-mini target-frame)
    ;; 清除 tab-line 缓存并强制刷新
    (walk-windows
     (lambda (window)
       (when (eq (window-frame window) target-frame)
         (set-window-parameter window 'tab-line-cache nil)
         (force-mode-line-update t)))
     'no-mini target-frame)
    (when (called-interactively-p 'interactive)
      (message "已刷新当前 frame 的标签上下文"))))


(setq tab-line-tabs-function #'custom/tab-line-tabs
      tab-line-tab-name-function #'custom/tab-line-tab-name
      tab-line-tab-name-format-function #'custom/tab-line-tab-name-format
      tab-line-close-tab-function #'custom/tab-line-close-tab
      tab-line-close-button-show 'selected
      tab-line-new-button-show nil
      tab-line-switch-cycling t
      tab-line-separator "")

(custom/apply-tab-line-button-preset)

(setq tab-line-exclude-modes
      (delete-dups (append custom:tabs-hidden-modes tab-line-exclude-modes)))

(global-tab-line-mode 1)

(dolist (hook '(dashboard-mode-hook
                treemacs-mode-hook
                vterm-mode-hook
                term-mode-hook
                eshell-mode-hook
                shell-mode-hook
                help-mode-hook
                helpful-mode-hook
                minibuffer-setup-hook))
  (add-hook hook
            (lambda ()
              (setq-local tab-line-exclude t)
              (tab-line-mode -1))))

;; 注册标签缓冲区跟踪 hook
(add-hook 'find-file-hook #'custom--tabs-register-current-buffer)
(add-hook 'kill-buffer-hook #'custom--tabs-on-kill-buffer)
(add-hook 'window-buffer-change-functions #'custom--tabs-on-window-buffer-change)
(add-hook 'delete-frame-functions #'custom--tabs-on-frame-deletion)
(add-hook 'server-switch-hook
          (lambda ()
            (when (and (buffer-file-name)
                       (custom/tab-visible-p (current-buffer)))
              (custom--tabs-register-buffer (current-buffer)))))
;; 项目切换时清空标签列表
(with-eval-after-load 'projectile
  (add-hook 'projectile-after-switch-project-hook
            (lambda ()
              (custom/tabs-clear-for-frame))))

;; 终端模式下启用鼠标支持
(xterm-mouse-mode 1)

;; 右键菜单（GUI 和终端均启用）
(context-menu-mode 1)

;; ═════════════════════════════════════════════════════════════════════════════
;; 光标和当前行高亮
;; ═════════════════════════════════════════════════════════════════════════════

;; 光标类型由 custom/apply-frame-appearance 按 display 类型设置（GUI: bar, TTY: box）

;; 高亮当前行（便于定位光标位置）
(global-hl-line-mode 1)

;; ═════════════════════════════════════════════════════════════════════════════
;; 字体配置
;; ═════════════════════════════════════════════════════════════════════════════

;; 默认字体大小（单位：1/10 pt，110 = 11pt）
;; 修改方法：改变 custom:default-font-height 的值
;; - 100 = 10pt (较小)
;; - 110 = 11pt (默认)
;; - 120 = 12pt (较大)
;; - 140 = 14pt (更大)
(defcustom custom:default-font-height 110
  "默认字体大小（1/10 pt）。"
  :type 'integer
  :group 'faces)

;; 字体大小由 custom/apply-frame-appearance 统一设置（仅 GUI）

;; ═════════════════════════════════════════════════════════════════════════════
;; 统一 per-frame 外观设置
;; ═════════════════════════════════════════════════════════════════════════════

(defvar custom/terminal-faces-active nil
  "非 nil 表示最近一次切到了终端 ANSI face 覆盖。")

(defun custom/graphic-frame-exists-p ()
  "返回当前会话中是否存在任意 GUI frame。"
  (catch 'found
    (dolist (frame (frame-list))
      (when (display-graphic-p frame)
        (throw 'found t)))
    nil))

(defun custom/apply-terminal-faces ()
  "为当前 frame 应用终端 ANSI 颜色。
仅在终端模式 (display-graphic-p 为 nil) 下有意义。
所有 set-face-attribute 调用都使用 frame-local 参数 (selected-frame)，
这样在 daemon 混合 GUI+TTY 模式下不会污染 GUI frame 的主题配色。
调用前应已在 with-selected-frame 上下文中。"
  (condition-case err
      (let ((tty (selected-frame)))
        ;; tab-line 终端配色
        (when (facep 'tab-line)
          (set-face-attribute 'tab-line tty
                              :background "black" :foreground "brightblack" :box nil)
          (set-face-attribute 'tab-line-tab tty
                              :background "brightblack" :foreground "white" :box nil)
          (set-face-attribute 'tab-line-tab-current tty
                              :background "cyan" :foreground "black" :box nil
                              :weight 'bold)
          (set-face-attribute 'tab-line-tab-inactive tty
                              :background "brightblack" :foreground "white" :box nil)
          (set-face-attribute 'tab-line-highlight tty
                              :background "white" :foreground "black" :box nil)
          (set-face-attribute 'tab-line-close-highlight tty
                              :background "black" :foreground "brightred" :box nil)
          (set-face-attribute 'tab-line-tab-modified tty
                              :background "black" :foreground "brightyellow" :box nil))
        ;; 内置 face
        (set-face-attribute 'highlight tty :background "brightblack" :foreground "white")
        (set-face-attribute 'region tty :background "brightblack" :foreground "white")
        (set-face-attribute 'hl-line tty :background "brightblack")
        (set-face-attribute 'show-paren-match tty :background "cyan" :foreground "black")
        (set-face-attribute 'show-paren-mismatch tty :background "red" :foreground "white")
        (set-face-attribute 'lazy-highlight tty :background "brightblack" :foreground "brightyellow")
        (set-face-attribute 'match tty :background "brightblack" :foreground "brightyellow")
        (set-face-attribute 'isearch tty :background "cyan" :foreground "black")
        (set-face-attribute 'isearch-fail tty :background "red" :foreground "white")
        (set-face-attribute 'line-number tty :foreground "brightblack")
        (set-face-attribute 'line-number-current-line tty :foreground "brightgreen")
        (set-face-attribute 'mode-line tty :background "brightblack" :foreground "white")
        (set-face-attribute 'mode-line-inactive tty :background "black" :foreground "brightblack")
        (set-face-attribute 'help-key-binding tty :foreground "cyan")
        (set-face-attribute 'button tty :foreground "cyan")
        (set-face-attribute 'link tty :foreground "cyan")
        (set-face-attribute 'completions-common-part tty :foreground "cyan")
        (set-face-attribute 'completions-first-difference tty :foreground "brightcyan")
        ;; TTY 右键菜单
        (set-face-attribute 'tty-menu-enabled-face tty
                            :foreground "brightwhite" :background "brightblack" :weight 'bold)
        (set-face-attribute 'tty-menu-disabled-face tty
                            :foreground "brightblack" :background "brightblack")
        (set-face-attribute 'tty-menu-selected-face tty
                            :background "cyan" :foreground "black")
        ;; Corfu 补全弹窗（延迟加载，需等待 face 定义）
        ;; 仅终端模式下应用 ANSI 颜色；GUI 模式由主题管理 face。
        (with-eval-after-load 'corfu
          (unless (display-graphic-p)
            (set-face-attribute 'corfu-default tty :background "brightblack" :foreground "white")
            (set-face-attribute 'corfu-current tty :background "cyan" :foreground "black")
            (set-face-attribute 'corfu-bar tty :background "brightblack")
            (set-face-attribute 'corfu-border tty :background "brightblack")))
        ;; which-key（延迟加载，需等待 face 定义）
        (with-eval-after-load 'which-key
          (unless (display-graphic-p)
            (set-face-attribute 'which-key-key-face tty :foreground "brightcyan")
            (set-face-attribute 'which-key-separator-face tty :foreground "brightblack")
            (set-face-attribute 'which-key-command-description-face tty :foreground "white")
            (set-face-attribute 'which-key-group-description-face tty :foreground "brightblue"))))
    (error
     (message "custom/apply-terminal-faces: %s" (error-message-string err)))))

(defun custom/apply-frame-appearance (&optional frame)
  "为 FRAME 应用所有 display-dependent 外观设置。
这是 GUI/TTY 外观的统一入口，覆盖：
  - cursor-type（GUI: bar, TTY: box）
  - 字体高度（仅 GUI）
  - tab-line 外观
  - window-divider-mode（仅 GUI）
  - doom-modeline 高度/图标
  - dashboard 图标开关
  - ef-themes take-over-modus-themes（仅 GUI）
  - 终端 ANSI face colors（仅 TTY）

menu-bar/tool-bar/scroll-bar 通过 `default-frame-alist' 在顶层统一禁用。"
  (condition-case err
      (with-selected-frame (or frame (selected-frame))
        (let ((graphic-p (display-graphic-p)))
          ;; ── 全局变量（跨 frame 生效但需按 display 类型设置） ──
          (setq doom-modeline-icon graphic-p
                dashboard-set-heading-icons graphic-p
                dashboard-set-file-icons graphic-p)
          (setq-default cursor-type (if graphic-p 'bar 'box))

          (if graphic-p
              ;; ── GUI 专属设置 ──
              (progn
                (set-face-attribute 'default nil :height custom:default-font-height)
                (setq window-divider-default-right-width 1
                      window-divider-default-bottom-width 0)
                (window-divider-mode 1)
                (setq doom-modeline-height 26)
                ;; 安全网：以防某些非 frame-local 的操作影响了全局 face，
                ;; 重载主题恢复 GUI 配色（frame-local 改动下通常无需触发）。
                (when (and custom/terminal-faces-active
                           custom-enabled-themes)
                  (load-theme (car custom-enabled-themes) t))
                (setq custom/terminal-faces-active nil)
                (set-frame-parameter nil 'alpha-background custom:frame-background-opacity)
                (custom/apply-tab-line-face-preset)
                ;; ef-themes take-over（若 ef-themes 已加载）
                (when (fboundp 'ef-themes-take-over-modus-themes-mode)
                  (ef-themes-take-over-modus-themes-mode 1))
                ;; 像素级平滑滚动（仅 GUI，daemon 下按 frame 启用）
                ;; mouse.el 在 appearance.el 之后加载，用 eval-after-load 确保
                ;; 函数可用。standalone 模式下顶层已直接调用。
                (if (fboundp 'custom/maybe-enable-pixel-scroll)
                    (custom/maybe-enable-pixel-scroll)
                  (with-eval-after-load 'mouse
                    (when (display-graphic-p)
                      (custom/maybe-enable-pixel-scroll)))))
            ;; ── 终端专属设置 ──
            (progn
              (window-divider-mode -1)
              (setq doom-modeline-height 1)
              ;; 使用 frame-local 的 set-face-attribute，不会污染 GUI frame。
              ;; 混合 daemon (GUI+TTY) 下每个 TTY frame 独立应用 ANSI 覆盖。
              (custom/apply-terminal-faces)
              (setq custom/terminal-faces-active t)))

          (force-mode-line-update t)))
    (error
     (message "custom/apply-frame-appearance: frame=%s error=%s"
              (or frame (selected-frame))
              (error-message-string err)))))

;; standalone 模式下直接初始化（daemon 模式由 frame hook 触发）
(unless (daemonp)
  (custom/apply-frame-appearance))

(custom/register-daemon-frame-hook #'custom/apply-frame-appearance)

;; ═════════════════════════════════════════════════════════════════════════════
;; 窗口分割线
;; ═════════════════════════════════════════════════════════════════════════════

;; window-divider 由 custom/apply-frame-appearance 统一管理（仅 GUI 启用）

;; ═════════════════════════════════════════════════════════════════════════════
;; 主题配置
;; ═════════════════════════════════════════════════════════════════════════════

;; Ef-themes - 现代化主题集合
;; 延迟加载以加速启动
;;
;; 使用说明：
;; - F6: 循环切换主题
;; - C-F6: 选择特定主题
;; - M-F6: 加载随机主题
;;
;; 修改默认主题：
;; 将 'ef-owl 改为其他主题名称，如：
;; - ef-dark: 深色主题
;; - ef-light: 浅色主题
;; - ef-duo-dark: 双色深色主题
(use-package ef-themes
  :defer t
  :init
  ;; ef-themes-take-over 由 custom/apply-frame-appearance 统一管理
  :bind
  (("<f6>" . ef-themes-rotate)
   ("C-<f6>" . ef-themes-select)
   ("M-<f6>" . ef-themes-load-random))
  :custom
  (ef-themes-mixed-fonts t)         ; 混合字体支持
  (ef-themes-italic-constructs t)   ; 斜体支持
  :config
  ;; 不在这里加载默认主题，由 color-scheme.el 根据系统状态决定
  )

;; ═════════════════════════════════════════════════════════════════════════════
;; 模式行配置
;; ═════════════════════════════════════════════════════════════════════════════

;; Doom Modeline - 现代化模式行
;; 使用 hook 延迟加载，避免影响启动速度
;;
;; 配置说明：
;; - doom-modeline-height: 模式行高度（像素）
;; - doom-modeline-buffer-file-name-style: 文件名显示方式
;;   - 'truncate-upto-project: 显示相对于项目根的路径
;;   - 'relative-to-project: 完整相对路径
;;   - 'file-name: 仅文件名
;; - doom-modeline-project-detection: 项目检测方式
(use-package doom-modeline
  :defer t
  :hook (after-init . doom-modeline-mode)
  :custom
  (doom-modeline-height 26)  ; 由 custom/apply-frame-appearance 按 display 类型覆盖
  (doom-modeline-buffer-file-name-style 'truncate-upto-project)
  (doom-modeline-project-detection 'project)
  (doom-modeline-icon nil))  ; 由 custom/apply-frame-appearance 按 display 类型覆盖

;; ═════════════════════════════════════════════════════════════════════════════
;; 迷你地图
;; ═════════════════════════════════════════════════════════════════════════════

;; Minimap - 代码缩略图（类似 Sublime Text）
;; 按需加载，不影响启动速度
;;
;; 使用说明：
;; - F8: 切换迷你地图显示
;; - 迷你地图会显示在窗口右侧
;;
;; 配置说明：
;; - minimap-window-location: 显示位置 (left/right)
;; - minimap-width-fraction: 宽度占比（0.1 = 10%）
;; - minimap-minimum-width: 最小宽度（字符数）
(use-package minimap
  :if (locate-library "minimap")
  :commands (minimap-mode minimap-create minimap-kill)
  :bind ("<f8>" . minimap-mode)
  :init
  (setq minimap-window-location 'right
        minimap-width-fraction 0.1
        minimap-minimum-width 15
        minimap-recreate-window t
        minimap-dedicated-window t
        minimap-automatically-delete-window 'visible))

;; ═════════════════════════════════════════════════════════════════════════════
;; 终端模式界面配色
;; ═════════════════════════════════════════════════════════════════════════════

;; 终端 ANSI 颜色由 custom/apply-frame-appearance → custom/apply-terminal-faces 统一管理

(provide 'appearance)
;;; appearance.el ends here
