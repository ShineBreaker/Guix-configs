;;; tab-line.el --- 文件标签栏子系统 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 基于 Emacs 内建 `tab-line' 的文件标签栏。
;;
;; 集中管理：
;; - per-frame 标签缓冲区列表（frame parameter `literal--frame-tab-buffers'）
;; - 标签注册/注销（find-file / kill-buffer / window-buffer-change hook）
;; - 标签栏视觉（IDE 风格：当前标签底色 + 强调下划线，非当前标签退回编辑区背景）
;; - 标签切换、关闭、刷新命令
;;
;; 提供 feature `appearance-tab-line'。
;;
;; 标签栏策略：使用 Emacs 内建 `tab-line'，不使用 `centaur-tabs'。
;; 原因是 `centaur-tabs' 的 tabset 与 buffer/group 缓存是全局状态，
;; 在 daemon + 多个 emacsclient frame 下天然容易互相污染。
;; `tab-line' 是窗口局部机制，更适合当前配置的 daemon/client 工作流。
;;
;; 多 client frame 隔离策略：
;; - 每个 frame 使用 frame parameter `literal--frame-tab-buffers' 维护独立的标签缓冲区列表
;; - 缓冲区通过 `find-file-hook'、`window-buffer-change-functions' 等自动注册到当前 frame
;; - file mode hook 若抛错，`global-tab-line-mode' 可能来不及给新 buffer 启用
;;   `tab-line-mode'；标签注册路径会再次幂等启用，避免单个 major-mode 报错拖掉标签栏
;; - 关闭标签仅从当前 frame 的列表中移除，不影响其他 frame
;; - 切换项目时（Projectile hook）自动清空标签列表，重建新项目上下文
;; - 标签切换默认作用于当前窗口
;; - 特殊窗口（Dashboard、终端、帮助、Agent 等）不显示标签栏

;;; Code:

(require 'tab-line)
(require 'color)

;; ═════════════════════════════════════════════════════════════════════════════
;; 常量
;; ═════════════════════════════════════════════════════════════════════════════

;; 关闭内置 tab-bar，改用 window-local `tab-line` 作为文件标签栏。
(tab-bar-mode -1)

(defconst literal:tabs-hidden-modes
  '(dashboard-mode ghostel-mode term-mode eshell-mode shell-mode
    help-mode helpful-mode special-mode completion-list-mode
    agent-shell-mode magit-mode)
  "不显示在标签栏中的 major mode 列表。
视图类 buffer 集中在此维护，避免污染每个 mode 的 hook 注册。")

(defconst literal:tabs-name-max-width 36
  "单个标签名最大宽度。")

(defun literal/tab-visible-p (buffer)
  "判断 BUFFER 是否应该显示在标签栏中。
采用白名单机制：只有关联文件的 buffer 才显示。"
  (and (buffer-live-p buffer)
       (buffer-file-name buffer)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Face 变量
;; ═════════════════════════════════════════════════════════════════════════════

(defvar literal--tab-line-face-current nil
  "当前标签使用的显式 face plist。")

(defvar literal--tab-line-face-inactive nil
  "非当前标签使用的显式 face plist。")

(defvar literal--tab-line-face-highlight nil
  "标签 hover 使用的显式 face plist。")

;; TTY 专用标签 face plist —— 透明背景,靠前景色 + 下划线区分当前标签。
;; GUI preset (literal/apply-tab-line-face-preset) 读取主题 RGB 会污染 TTY
;; (渲染成不透明 256color),故 TTY 用独立常量,literal--tab-line-face-value
;; 按 (display-graphic-p) 选择,GUI/TTY 互不干扰。
(defconst literal--tab-line-face-current-tty
  '(:inherit nil :background unspecified :foreground "brightwhite"
    :box nil :overline nil :inverse-video nil :weight semibold
    :underline (:color "brightcyan" :position t))
  "终端模式当前标签 face plist。
背景 unspecified 让终端用 default(透明),靠下划线 + 加粗前景区分当前标签。")

(defconst literal--tab-line-face-inactive-tty
  '(:inherit nil :background unspecified :foreground "brightblack"
    :box nil :overline nil :underline nil :inverse-video nil :weight medium)
  "终端模式非当前标签 face plist。")

(defconst literal--tab-line-face-highlight-tty
  '(:inherit nil :background "brightblack" :foreground "brightwhite"
    :box nil :overline nil :underline nil :inverse-video nil)
  "终端模式标签 hover face plist。
hover 是局部高亮,brightblack(轻微不透明)可接受。")

;; ═════════════════════════════════════════════════════════════════════════════
;; 窗口定位（简化版：直接选 selected-window）
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal--tabs-target-window (&optional window)
  "返回标签命令应优先操作的 WINDOW。
默认返回 selected-window，显式传入 WINDOW 时优先使用它。"
  (or (and (window-live-p window) window)
      (selected-window)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Per-frame 标签缓冲区跟踪
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal--tabs-get-frame-buffer-list (&optional frame)
  "返回 FRAME 的标签缓冲区列表。"
  (frame-parameter (or frame (selected-frame)) 'literal--frame-tab-buffers))

(defun literal--tabs-set-frame-buffer-list (buffers &optional frame)
  "设置 FRAME 的标签缓冲区列表为 BUFFERS。"
  (set-frame-parameter (or frame (selected-frame)) 'literal--frame-tab-buffers buffers))

(defun literal--tabs-register-buffer (buffer &optional frame)
  "将 BUFFER 注册到 FRAME 的标签列表尾部（去重）。"
  (let* ((target-frame (or frame (selected-frame)))
         (buffers (or (literal--tabs-get-frame-buffer-list target-frame) '())))
    (unless (memq buffer buffers)
      (literal--tabs-set-frame-buffer-list
       (append buffers (list buffer))
       target-frame))))

(defun literal--tabs-unregister-buffer (buffer &optional frame)
  "从 FRAME 的标签列表中移除 BUFFER。"
  (let* ((target-frame (or frame (selected-frame)))
         (buffers (or (literal--tabs-get-frame-buffer-list target-frame) '())))
    (when (memq buffer buffers)
      (literal--tabs-set-frame-buffer-list
       (delq buffer buffers)
       target-frame))))

(defun literal--tabs-register-current-buffer ()
  "将当前缓冲区注册到当前 frame 的标签列表。"
  (when (and (not (minibufferp))
             (literal/tab-visible-p (current-buffer)))
    (literal--tabs-ensure-current-buffer-tab-line)
    (literal--tabs-register-buffer (current-buffer))))

(defun literal--tabs-ensure-current-buffer-tab-line ()
  "确保当前文件 buffer 显示 tab-line。
`global-tab-line-mode' 依赖 major mode 切换后的 hook 给新 buffer 启用
`tab-line-mode'。如果 file mode hook 中途报错，Emacs 会继续打开文件，
但该 buffer 可能错过全局 minor mode 的初始化。这里在标签注册路径中
做一次幂等恢复，只作用于本配置认可的文件标签 buffer。"
  (when (and global-tab-line-mode
             (not (minibufferp))
             (literal/tab-visible-p (current-buffer))
             (not (memq major-mode literal:tabs-hidden-modes)))
    (setq-local tab-line-exclude nil)
    (tab-line-mode 1)))

(defun literal--tabs-on-window-buffer-change (frame-or-window)
  "当缓冲区变更时，将新缓冲区注册到对应 frame 的标签列表。
FRAME-OR-WINDOW 可以是 frame（全局 hook 传入）或 window（buffer-local hook 传入）。"
  (cond
   ((frame-live-p frame-or-window)
    (walk-windows
     (lambda (window)
       (when (eq (window-frame window) frame-or-window)
         (let ((buffer (window-buffer window)))
           (when (and (buffer-live-p buffer)
                      (literal/tab-visible-p buffer)
                      (not (minibufferp buffer)))
             (with-current-buffer buffer
               (literal--tabs-ensure-current-buffer-tab-line))
             (literal--tabs-register-buffer buffer frame-or-window)))))
     'no-mini frame-or-window))
   ((window-live-p frame-or-window)
    (let ((buffer (window-buffer frame-or-window))
          (frame (window-frame frame-or-window)))
      (when (and (buffer-live-p buffer)
                 (literal/tab-visible-p buffer)
                 (not (minibufferp buffer)))
        (with-current-buffer buffer
          (literal--tabs-ensure-current-buffer-tab-line))
        (literal--tabs-register-buffer buffer frame))))))

(defun literal--tabs-on-kill-buffer ()
  "当缓冲区被关闭时，从所有 frame 的标签列表中移除。"
  (let ((buffer (current-buffer)))
    (dolist (frame (frame-list))
      (when (frame-live-p frame)
        (let ((buffers (literal--tabs-get-frame-buffer-list frame)))
          (when (memq buffer buffers)
            (literal--tabs-set-frame-buffer-list (delq buffer buffers) frame)))))))

(defun literal/tabs-clear-for-frame (&optional frame)
  "清空 FRAME 的标签缓冲区列表。
仅清除 frame parameter 和 tab-line 缓存，不重建标签列表。
项目切换时由后续 find-file/server-switch 等 hook 自然重建。"
  (interactive)
  (let ((target-frame (or frame (selected-frame))))
    (literal--tabs-set-frame-buffer-list nil target-frame)
    ;; 仅清除 tab-line 缓存，触发视觉刷新，不重建标签列表
    (walk-windows
     (lambda (window)
       (when (eq (window-frame window) target-frame)
         (set-window-parameter window 'tab-line-cache nil)))
     'no-mini target-frame)
    (when (called-interactively-p 'interactive)
      (message "已清空当前 frame 的标签列表"))))

(defun literal--tabs-on-frame-deletion (frame)
  "FRAME 删除时清理标签状态。"
  (literal--tabs-set-frame-buffer-list nil frame))

(defun literal--tabs-frame-buffers (&optional window)
  "返回 WINDOW 所在 frame 的标签缓冲区列表。
仅返回通过 `literal--tabs-register-buffer' 注册且仍然存活的缓冲区。"
  (let* ((target-window (literal--tabs-target-window window))
         (target-frame (window-frame target-window))
         (frame-buffers (literal--tabs-get-frame-buffer-list target-frame)))
    (seq-filter (lambda (buf)
                  (and (buffer-live-p buf)
                       (literal/tab-visible-p buf)))
                (or frame-buffers '()))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 标签名格式化
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/tab-line-tabs ()
  "返回当前窗口标签栏要展示的 buffer 列表。"
  (or (literal--tabs-frame-buffers (selected-window))
      (list (current-buffer))))

(defun literal/tab-line-tab-name (buffer &optional _buffers)
  "生成 BUFFER 的标签名。"
  (let* ((name (truncate-string-to-width
                (buffer-name buffer)
                literal:tabs-name-max-width 0 nil t))
         (icon (when (display-graphic-p)
                 (require 'nerd-icons)
                 (with-current-buffer buffer
                   (nerd-icons-icon-for-buffer))))
         (prefix (if (and (stringp icon)
                          (not (string-empty-p icon)))
                     (concat icon " ")
                   ""))
         (suffix (if (buffer-modified-p buffer) " ●" "")))
    (concat prefix name suffix)))

(defun literal--tab-line-help-echo (selected-p)
  "返回标签的中文提示文本。SELECTED-P 表示是否为当前标签。"
  (if selected-p
      "当前标签：鼠标中键关闭，右键打开菜单"
    "左键切换标签，鼠标中键关闭，右键打开菜单"))

(defun literal--tab-line-close-button (face selected-p)
  "返回标签关闭按钮文本。FACE 为标签 face，SELECTED-P 表示是否当前标签。"
  (let ((show-close (and tab-line-close-button-show
                         (not (eq tab-line-close-button-show
                                  (if selected-p 'non-selected 'selected))))))
    (if (not show-close)
        ""
      (let ((close (copy-sequence tab-line-close-button)))
        (add-face-text-property 0 (length close) face t close)
        ;; 当前标签保持"纯文本 + 下划线"外观，不再给关闭按钮单独挂
        ;; `mouse-face'，避免 PGTK/GUI hover 态再次画出浅色描边。
        (when selected-p
          (put-text-property 0 (length close) 'mouse-face nil close))
        close))))

(defun literal--tab-line-face-value (face)
  "返回 FACE 对应的显式 face 定义。
GUI 用主题色 plist,TTY 用透明背景专用 plist(见 `literal--tab-line-face-*-tty')。
按 `(display-graphic-p)' 选择,避免 GUI 主题 RGB 污染终端渲染成不透明 256color。"
  (let ((tty-p (null (display-graphic-p))))
    (pcase face
      ('tab-line-tab-current
       (if tty-p literal--tab-line-face-current-tty literal--tab-line-face-current))
      ('tab-line-tab
       (if tty-p literal--tab-line-face-inactive-tty literal--tab-line-face-inactive))
      ('tab-line-tab-inactive
       (if tty-p literal--tab-line-face-inactive-tty literal--tab-line-face-inactive))
      ('tab-line-highlight
       (if tty-p literal--tab-line-face-highlight-tty literal--tab-line-face-highlight))
      (_ face))))

(defun literal/tab-line-tab-name-format (tab tabs)
  "以更接近 IDE 的样式格式化 TAB。
TABS 为当前窗口全部标签列表。"
  (let* ((buffer-p (bufferp tab))
         (selected-p (if buffer-p
                         (eq tab (window-buffer))
                       (cdr (assq 'selected tab))))
         (name (if buffer-p
                   (funcall tab-line-tab-name-function tab tabs)
                 (cdr (assq 'name tab))))
         ;; tab-line 位于窗口顶部时，`mode-line-window-selected-p' 在某些场景下
         ;; 会让当前 buffer 的标签退回普通 tab face，视觉上又变成"按钮底色+
         ;; 浅色外框"。这里选中标签一律使用 current face，避免激活态抖动。
         (face (if selected-p
                   'tab-line-tab-current
                 'tab-line-tab-inactive))
         (label (concat " " (string-replace "%" "%%" name)))
         mouse-face
         close
         (help-echo (literal--tab-line-help-echo selected-p)))
    (dolist (fn tab-line-tab-face-functions)
      (setq face (funcall fn tab tabs face buffer-p selected-p)))
    (setq face (literal--tab-line-face-value face))
    ;; 当前标签不再设置 `mouse-face'。这样鼠标悬停时不会进入 Emacs
    ;; 的按钮 hover 绘制路径，避免 selected tab 周围出现额外浅色边。
    (setq mouse-face (unless selected-p
                       literal--tab-line-face-highlight))
    (setq close (literal--tab-line-close-button face selected-p))
    (apply #'propertize
           (concat
            (propertize label
                        'face face
                        'keymap tab-line-tab-map
                        'help-echo help-echo
                        'follow-link 'ignore)
             close)
           `(tab ,tab
                 mouse-face ,mouse-face))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 按钮与 Face 预设
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/apply-tab-line-button-preset ()
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

(defun literal--color-luminance (color)
  "返回 COLOR 的相对亮度，范围约为 0.0 到 1.0。"
  (when-let* ((rgb (ignore-errors (color-name-to-rgb color))))
    (+ (* 0.2126 (nth 0 rgb))
       (* 0.7152 (nth 1 rgb))
       (* 0.0722 (nth 2 rgb)))))

(defun literal--pick-readable-color (background &rest candidates)
  "为 BACKGROUND 从 CANDIDATES 中选择对比度最高的颜色。"
  (let ((bg-luminance (or (literal--color-luminance background) 0.0))
        (best-color nil)
        (best-distance -1.0))
    (dolist (candidate candidates best-color)
      (let ((fg-luminance (literal--color-luminance candidate)))
        (when fg-luminance
          (let ((distance (abs (- bg-luminance fg-luminance))))
            (when (> distance best-distance)
              (setq best-distance distance
                    best-color candidate))))))))

(defun literal/apply-tab-line-face-preset ()
  "应用更接近 JetBrains / VSCode 的标签栏外观。
颜色来源:优先读取 face 的 :background/:foreground,缺失时回退 ANSI 颜色名。
不依赖 modus-themes,ef-themes/任意主题都可工作。"
  (let* ((valid-bg (lambda (val) (and val (not (string-prefix-p "unspecified" val)) val)))
         (default-bg (or (funcall valid-bg (face-background 'default nil t))
                         (funcall valid-bg (face-background 'default nil 'default))
                         'unspecified))
         (default-fg (or (funcall valid-bg (face-foreground 'default nil t))
                         (funcall valid-bg (face-foreground 'default nil 'default))
                         'unspecified))
         (accent-fg (or (funcall valid-bg (face-foreground 'cursor nil t))
                        (funcall valid-bg (face-foreground 'font-lock-keyword-face nil t))
                        default-fg))
         (mode-line-fg (or (funcall valid-bg (face-foreground 'mode-line nil t))
                           default-fg))
         (mode-line-bg (or (funcall valid-bg (face-background 'mode-line nil t))
                           default-bg))
         (mode-line-inactive-bg (or (funcall valid-bg (face-background 'mode-line-inactive nil t))
                                    default-bg))
         (mode-line-inactive-fg (or (funcall valid-bg (face-foreground 'mode-line-inactive nil t))
                                    default-fg))
         (shadow-fg (or (funcall valid-bg (face-foreground 'shadow nil t))
                        mode-line-inactive-fg))
         ;; 整条标签栏本身回到编辑区背景，按钮颜色只用于标签块，
         ;; 避免整个标签栏被主题的 mode-line 色整片染色。
         (inactive-bg default-bg)
         ;; 某些主题会把 `mode-line' 画得比 `mode-line-inactive' 更暗，
         ;; 这里仍按亮度纠偏，但只影响"激活标签按钮"的底色。
         (current-bg (if (let ((active-luminance (literal--color-luminance mode-line-bg))
                               (inactive-luminance (literal--color-luminance mode-line-inactive-bg)))
                           (and active-luminance
                                inactive-luminance
                                (< active-luminance inactive-luminance)))
                         mode-line-bg
                       mode-line-inactive-bg))
         (current-fg (or (literal--pick-readable-color
                          current-bg
                          default-fg
                          mode-line-fg
                          accent-fg
                          shadow-fg
                          mode-line-inactive-fg)
                         default-fg))
         (inactive-fg (or (literal--pick-readable-color
                           inactive-bg
                           shadow-fg
                           mode-line-inactive-fg
                           default-fg
                           mode-line-fg)
                          default-fg))
         ;; 关闭按钮高亮 / 修改标记：从语义 face 读,缺失时回退 ANSI 颜色名
         (close-fg (or (funcall valid-bg (face-foreground 'error nil t))
                       "tomato"))
         (modified-fg (or (funcall valid-bg (face-foreground 'warning nil t))
                          "goldenrod")))
    (setq literal--tab-line-face-current
          `(:inherit nil
            :background ,current-bg
            :foreground ,current-fg
            :box nil
            :overline nil
            :inverse-video nil
            :weight semibold
            :underline (:color ,accent-fg :position t)))
    (setq literal--tab-line-face-inactive
          `(:inherit nil
            :background unspecified
            :foreground ,inactive-fg
            :box nil
            :overline nil
            :underline nil
            :inverse-video nil
            :weight medium))
    (setq literal--tab-line-face-highlight
          `(:inherit nil
            :background ,current-bg
            :foreground ,current-fg
            :box nil
            :overline nil
            :underline nil
            :inverse-video nil))
    (set-face-attribute 'tab-line nil
                        :inherit nil
                        :background default-bg
                        :foreground default-fg
                        :box nil
                        :overline nil
                        :underline nil
                        :inverse-video nil
                        :height 0.95)
    (set-face-attribute 'tab-line-highlight nil
                        :inherit nil
                        :background current-bg
                        :foreground current-fg
                        :box nil
                        :overline nil
                        :underline nil
                        :inverse-video nil)
    (set-face-attribute 'tab-line-close-highlight nil
                        :inherit nil
                        :foreground close-fg
                        :background 'unspecified
                        :box nil
                        :overline nil
                        :underline nil
                        :inverse-video nil)
    (set-face-attribute 'tab-line-tab-modified nil
                        :inherit nil
                        :foreground modified-fg
                        :background 'unspecified
                        :box nil
                        :overline nil
                        :underline nil
                        :inverse-video nil)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 标签切换与关闭
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal--tabs-switch-to-buffer (buffer &optional window)
  "在 WINDOW 中切换到 BUFFER，并刷新标签显示。"
  (when (buffer-live-p buffer)
    (let ((target-window (literal--tabs-target-window window))
          (switch-to-buffer-obey-display-actions nil))
      (with-selected-window target-window
        (switch-to-buffer buffer)
        (tab-line-force-update t)))))

(defun literal/tabs-next (&optional arg)
  "切换到当前标签列表中的下一个标签。ARG 为步数。"
  (interactive "p")
  (let* ((target-window (literal--tabs-target-window))
         (buffers (literal--tabs-frame-buffers target-window))
         (current (window-buffer target-window))
         (position (seq-position buffers current))
         (step (or arg 1)))
    (when (and position buffers)
      (literal--tabs-switch-to-buffer
       (nth (mod (+ position step) (length buffers)) buffers)
       target-window))))

(defun literal/tabs-previous (&optional arg)
  "切换到当前标签列表中的上一个标签。ARG 为步数。"
  (interactive "p")
  (literal/tabs-next (- (or arg 1))))

(defun literal/tabs-select-index (index)
  "切换到当前标签列表中的第 INDEX 个标签。"
  (interactive)
  (let* ((target-window (literal--tabs-target-window))
         (buffers (literal--tabs-frame-buffers target-window))
         (buffer (nth (1- index) buffers)))
    (if buffer
        (literal--tabs-switch-to-buffer buffer target-window)
      (user-error "当前标签数量不足 %d 个" index))))
;; 别名桥接：README/prefix-keymaps.el 使用更面向用户语义的名字，
;; 实现仍由通用内部名承担；alias 让两边都对，避免 API 不一致报错。
(defalias 'literal/tabs-select-visible-tab #'literal/tabs-select-index)
(defalias 'literal/tabs-close-current #'literal/tabs-close-buffer)

(defun literal/tabs-close-buffer (&optional window)
  "关闭当前标签，切换到下一个可用标签。"
  (interactive)
  (let* ((target-window (literal--tabs-target-window window))
         (buffer (window-buffer target-window))
         (target-frame (window-frame target-window))
         (frame-buffers (or (literal--tabs-get-frame-buffer-list target-frame) '()))
         (remaining (delq buffer frame-buffers))
         ;; 过滤掉已死或不可见的候选，找到第一个有效切换目标
         (valid-next (seq-find (lambda (b)
                                 (and (buffer-live-p b)
                                      (literal/tab-visible-p b)))
                               remaining)))
    (literal--tabs-unregister-buffer buffer target-frame)
    (cond
     (valid-next
      (literal--tabs-switch-to-buffer valid-next target-window))
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

(defun literal/tab-line-close-tab (tab)
  "鼠标关闭按钮回调：从当前 frame 标签列表注销缓冲区并切换。
TAB 由 `tab-line-close-tab-function' 传入，为要关闭的 buffer 对象。"
  (interactive)
  (let* ((buffer (if (bufferp tab) tab (current-buffer)))
         (target-window (literal--tabs-target-window))
         (target-frame (window-frame target-window)))
    (when (and buffer (buffer-live-p buffer))
      (let* ((frame-buffers (or (literal--tabs-get-frame-buffer-list target-frame) '()))
             (remaining (delq buffer frame-buffers))
             (valid-next (seq-find (lambda (b)
                                     (and (buffer-live-p b)
                                          (literal/tab-visible-p b)))
                                   remaining)))
        (literal--tabs-unregister-buffer buffer target-frame)
        (if valid-next
            (literal--tabs-switch-to-buffer valid-next target-window)
          (with-selected-window target-window
            (bury-buffer buffer)
            (tab-line-force-update t)))))))

(defun literal/tabs-refresh-context (&optional frame)
  "刷新 FRAME 的标签栏上下文，完全重建标签列表。"
  (interactive)
  (let ((target-frame (or frame (selected-frame))))
    ;; 先清空再收集，确保「刷新=重建」而非追加
    (literal--tabs-set-frame-buffer-list nil target-frame)
    (walk-windows
     (lambda (window)
       (when (eq (window-frame window) target-frame)
         (let ((buffer (window-buffer window)))
           (when (and (buffer-live-p buffer)
                      (literal/tab-visible-p buffer))
             (literal--tabs-register-buffer buffer target-frame)))))
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

;; ═════════════════════════════════════════════════════════════════════════════
;; 全局配置与 Hook 注册
;; ═════════════════════════════════════════════════════════════════════════════

(setq tab-line-tabs-function #'literal/tab-line-tabs
      tab-line-tab-name-function #'literal/tab-line-tab-name
      tab-line-tab-name-format-function #'literal/tab-line-tab-name-format
      tab-line-close-tab-function #'literal/tab-line-close-tab
      tab-line-close-button-show 'selected
      tab-line-new-button-show nil
      tab-line-switch-cycling t
      tab-line-separator "")

(literal/apply-tab-line-button-preset)

(setq tab-line-exclude-modes
      (delete-dups (append literal:tabs-hidden-modes tab-line-exclude-modes)))

(global-tab-line-mode 1)

;; 在视图类 mode buffer 中关闭 tab-line（避免无意义的空白标签栏）
(dolist (hook '(dashboard-mode-hook
                ghostel-mode-hook
                term-mode-hook
                eshell-mode-hook
                shell-mode-hook
                help-mode-hook
                helpful-mode-hook
                minibuffer-setup-hook
                agent-shell-mode-hook
                magit-mode-hook))
  (add-hook hook
            (lambda ()
              (setq-local tab-line-exclude t)
              (tab-line-mode -1))))

;; 注册标签缓冲区跟踪 hook
(add-hook 'find-file-hook #'literal--tabs-register-current-buffer)
(add-hook 'kill-buffer-hook #'literal--tabs-on-kill-buffer)
(add-hook 'window-buffer-change-functions #'literal--tabs-on-window-buffer-change)
(add-hook 'delete-frame-functions #'literal--tabs-on-frame-deletion)
(add-hook 'server-switch-hook
          (lambda ()
            (when (and (buffer-file-name)
                       (literal/tab-visible-p (current-buffer)))
              (literal--tabs-ensure-current-buffer-tab-line)
              (literal--tabs-register-buffer (current-buffer)))))
;; 项目切换时清空标签列表
(with-eval-after-load 'projectile
  (add-hook 'projectile-after-switch-project-hook
            (lambda ()
              (literal/tabs-clear-for-frame))))

(provide 'literal-tab-line)
;;; tab-line.el ends here
