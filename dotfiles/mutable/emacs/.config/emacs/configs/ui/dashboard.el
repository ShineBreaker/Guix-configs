;;; dashboard.el --- 启动仪表盘配置 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置启动仪表盘，集成文件管理器、前缀键概览和鼠标工作流提示。
;;
;; Daemon/Client 模式优化：
;; Dashboard 的刷新和显示通过 `custom/register-daemon-frame-hook'
;; 统一接入 daemon/client 的 frame 生命周期，确保 emacsclient
;; 启动时能够即时呈现最新内容。
;; 为避免 frame hook 过早触发导致错过真正的 client
;; 占位缓冲区，dashboard 调度会在短暂 idle 后按需重试一次。
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

(require 'cl-lib)

;; ═════════════════════════════════════════════════════════════════════════════
;; 工具函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/dashboard-center-line (line)
  "在当前窗口中居中插入 LINE。"
  (let* ((win-width (window-width))
         (line-width (string-width line))
         (padding (max 0 (/ (- win-width line-width) 2))))
    (insert (make-string padding ?\s) line "\n")))

;; ═════════════════════════════════════════════════════════════════════════════
;; 自定义 ASCII Banner（Doom 风格）
;; ═════════════════════════════════════════════════════════════════════════════

(defvar custom/dashboard-ascii-banner
  '(
    ""
    " ███████╗  ███╗   ███╗   █████╗    ██████╗  ███████╗ "
    " ██╔════╝  ████╗ ████║  ██╔══██╗  ██╔════╝  ██╔════╝ "
    " █████╗    ██╔████╔██║  ███████║  ██║       ███████╗ "
    " ██╔══╝    ██║╚██╔╝██║  ██╔══██║  ██║       ╚════██║ "
    " ███████╗  ██║ ╚═╝ ██║  ██║  ██║  ╚██████╗  ███████║ "
    " ╚══════╝  ╚═╝     ╚═╝  ╚═╝  ╚═╝   ╚═════╝  ╚══════╝ "
    ""
    "                   ── F u s i o n   E d i t i o n ── "
    "")
  "Doom 风格 ASCII art banner。")

(defun custom/dashboard-insert-ascii-banner ()
  "插入居中的自定义 ASCII banner。"
  (let* ((max-len (apply #'max (mapcar #'length custom/dashboard-ascii-banner)))
         (padding (max 0 (/ (- (window-width) max-len) 2)))
         (pad-str (make-string padding ?\s))
         (banner-face (if (facep 'dashboard-banner) 'dashboard-banner 'font-lock-keyword-face)))
    (insert "\n")
    (dolist (line custom/dashboard-ascii-banner)
      (insert pad-str (propertize line 'face banner-face) "\n"))
    (insert "\n")))

;; ═════════════════════════════════════════════════════════════════════════════
;; 居中包装的原生列表显示
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/dashboard-insert-centered-list (title list list-size &optional icon key)
  "居中显示列表项，标题独立居中，列表项带装饰边框。
ICON 是左侧 Nerd Font 图标字符串。
KEY 是右侧快捷键提示字符串。"
  (when (car list)
    (let* ((items (seq-take list list-size))
           (max-display-len (apply #'max (mapcar (lambda (item) (string-width (cdr item))) items)))
           (box-width (+ 2 max-display-len 3)) ; 2=indent, 3=margin+borders
           (icon-str (or icon ""))
           (key-str (if key (concat " " key) ""))
           (title-line (concat icon-str " " title key-str))
           (title-pad (max 0 (/ (- (window-width) (string-width title-line)) 2)))
           (box-pad (max 0 (/ (- (window-width) box-width) 2))))
      ;; 标题行
      (insert (make-string title-pad ?\s)
              (propertize icon-str 'face 'font-lock-comment-face) " "
              (propertize title 'face 'dashboard-heading)
              (propertize key-str 'face 'font-lock-comment-face) "\n")
      ;; 上边框
      (insert (make-string box-pad ?\s)
              (propertize (concat "┌" (make-string (- box-width 2) ?─) "┐") 'face 'shadow) "\n")
      ;; 列表项
      (dolist (el items)
        (let* ((path (car el))
               (display (cdr el))
               (fill (max 0 (- box-width 5 (string-width display)))))
          (insert (make-string box-pad ?\s) (propertize "│  " 'face 'shadow))
          (insert-text-button
           display
           'action (lambda (b) (find-file (button-get b 'my-path)))
           'follow-link t
           'face 'dashboard-items-face
           'mouse-face 'highlight
           'help-echo "打开文件"
           'my-path path)
          (insert (make-string (1+ fill) ?\s) (propertize "│" 'face 'shadow) "\n")))
      ;; 下边框
      (insert (make-string box-pad ?\s)
              (propertize (concat "└" (make-string (- box-width 2) ?─) "┘") 'face 'shadow) "\n"))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 自定义项目生成器
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/dashboard-insert-recents (list-size)
  "居中插入最近文件列表。"
  (when (bound-and-true-p recentf-mode)
    (custom/dashboard-insert-centered-list
     "Recent Files"
     (mapcar (lambda (f) (cons f (abbreviate-file-name f)))
             recentf-list)
     list-size
     "󰋚" "C-x C-r")))

(defun custom/dashboard--known-projects ()
  "返回 dashboard 可展示的项目列表。

优先读取 Projectile 的已知项目缓存。由于 `project.el` 配置被延迟加载，
dashboard 首次渲染时 `projectile-mode` 可能尚未启动，因此这里需要在可用时
主动加载 Projectile 并同步 known projects 文件。"
  (let ((projects nil))
    (when (require 'projectile nil t)
      (when (fboundp 'projectile-load-known-projects)
        (projectile-load-known-projects))
      (setq projects
            (and (boundp 'projectile-known-projects)
                 projectile-known-projects)))
    (unless projects
      (setq projects
            (and (fboundp 'project-known-project-roots)
                 (project-known-project-roots))))
    (delete-dups
     (seq-filter #'file-directory-p
                 (mapcar #'file-name-as-directory projects)))))

(defun custom/dashboard-insert-projects (list-size)
  "居中插入项目列表。"
  (let ((projects (custom/dashboard--known-projects)))
    (when projects
      (custom/dashboard-insert-centered-list
       "Projects"
       (mapcar (lambda (p) (cons p (abbreviate-file-name p)))
               projects)
       list-size
       "󰝰" "C-x p p"))))

(defun custom/dashboard-insert-bookmarks (list-size)
  "居中插入书签列表。"
  (require 'bookmark)
  (custom/dashboard-insert-centered-list
   "Bookmarks"
   (mapcar (lambda (b)
             (cons (bookmark-get-filename b) b))
           (bookmark-all-names))
   list-size
   "󰉋" "C-c e b l"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 快捷键帮助内容（动态提取）
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/dashboard--extract-top-level-bindings ()
  "提取 dashboard 需要展示的关键顶层快捷键。"
  (custom/help--extract-dashboard-bindings))

(defun custom/dashboard-insert-shortcuts (_list-size)
  "在 dashboard 中插入居中的快捷键速查。
显示最关键的 Emacs 风格前缀与直达键。"
  (let* ((prefix-bindings (custom/dashboard--extract-top-level-bindings))
         (static-bindings
         '(("F1 ?" . "完整快捷键帮助")
           ("C-h / C-j / C-k / C-l" . "左 / 下 / 上 / 右移动")
           ("C-S-c / C-v" . "复制 / 粘贴")
           ("C-a / C-/" . "全选 / 注释")
           ("右键 / C-<mouse-1>" . "上下文菜单 / 跳转定义")
           ("C-S-p / F2" . "命令面板 / 重命名")))
         (all-items (append prefix-bindings static-bindings))
         (max-key-len (apply #'max (or (mapcar (lambda (b) (string-width (car b))) all-items) '(0))))
         (col-width (+ max-key-len 4))
         (max-line-width
          (+ 2 col-width
             (apply #'max (or (mapcar (lambda (b) (string-width (cdr b))) all-items) '(0)))))
         (padding (max 0 (/ (- (window-width) max-line-width) 2))))
    (insert "\n")
    (custom/dashboard-center-line
     (concat (propertize "快捷键速查" 'face 'dashboard-heading)
             (propertize "  (F1 ? 查看完整帮助)" 'face 'font-lock-doc-face)))
    (insert "\n")
     ;; 前缀分类
     (when prefix-bindings
       (insert (make-string padding ?\s)
               (propertize "关键前缀键" 'face 'dashboard-heading)
               "\n")
      (dolist (item prefix-bindings)
        (let* ((key-raw (car item))
               (desc (cdr item))
               (key-display (propertize key-raw 'face 'font-lock-keyword-face))
               (fill (max 0 (- col-width (string-width key-raw)))))
          (insert (make-string padding ?\s)
                  "  " key-display (make-string fill ?\s) desc "\n")))
      (insert "\n"))
    ;; 静态直达键
    (when static-bindings
      (insert (make-string padding ?\s)
              (propertize "其他操作" 'face 'dashboard-heading)
              "\n")
      (dolist (item static-bindings)
        (let* ((key-raw (car item))
               (desc (cdr item))
               (key-display (propertize key-raw 'face 'font-lock-keyword-face))
               (fill (max 0 (- col-width (string-width key-raw)))))
          (insert (make-string padding ?\s)
                  "  " key-display (make-string fill ?\s) desc "\n")))
      (insert "\n"))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Dashboard 配置
;; ═════════════════════════════════════════════════════════════════════════════

(use-package dashboard
  :demand t
  :custom
  (dashboard-startup-banner nil)
  (dashboard-set-navigator t)
  (dashboard-items '((recents . 10)
                     (projects . 8)
                     (bookmarks . 8)
                     (shortcuts . 1)))
  (dashboard-set-heading-icons nil)   ; 由 custom/apply-frame-appearance 按 display 类型覆盖
  (dashboard-set-file-icons nil)      ; 由 custom/apply-frame-appearance 按 display 类型覆盖
  :config
  ;; 抑制 dashboard 按钮点击后的 overlay 无效报错
  ;; 原因：按钮 action 中 find-file 切换了当前 buffer，
  ;; widget-button--check-and-call-button 返回时 overlay 已失效
  (define-advice widget-button--check-and-call-button (:around (fn &rest args) suppress-overlay-error)
    "抑制 overlay 相关的 wrong-type-argument 错误。"
    (condition-case err
        (apply fn args)
      (wrong-type-argument
       (unless (eq (cadr err) 'overlayp)
         (signal (car err) (cdr err))))))
  ;; 插入自定义居中 ASCII banner
  (advice-add 'dashboard-insert-banner :override #'custom/dashboard-insert-ascii-banner)
  ;; 注册自定义项目生成器
  (add-to-list 'dashboard-item-generators '(shortcuts . custom/dashboard-insert-shortcuts))
  (add-to-list 'dashboard-item-generators '(recents . custom/dashboard-insert-recents))
  (add-to-list 'dashboard-item-generators '(projects . custom/dashboard-insert-projects))
  (add-to-list 'dashboard-item-generators '(bookmarks . custom/dashboard-insert-bookmarks))
  (dashboard-setup-startup-hook))

(defun custom/dashboard--placeholder-buffer-p (buffer)
  "判断 BUFFER 是否仍是 client frame 的占位缓冲区。"
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (and (not (minibufferp buffer))
           (not buffer-file-name)
           (or (member (buffer-name buffer)
                       '(" *server*" "*scratch*" "*Messages*"))
               (derived-mode-p 'fundamental-mode 'special-mode))))))

(defun custom/dashboard--display-in-frame (frame)
  "在 FRAME 中显示并按需刷新 dashboard。"
  (when (frame-live-p frame)
    (with-selected-frame frame
      (when (fboundp 'dashboard-open)
        (dashboard-open)
        (when-let ((dashboard-buffer (get-buffer "*dashboard*")))
          (when (fboundp 'dashboard-refresh-buffer)
            (with-current-buffer dashboard-buffer
              (dashboard-refresh-buffer)))
          (when-let ((window (frame-selected-window frame)))
            (set-window-buffer window dashboard-buffer)))))))

(defconst custom:dashboard-open-idle-delay 0.05
  "新建 client frame 后等待 dashboard 判定的 idle 秒数。")

(defconst custom:dashboard-open-retries 2
  "若首次判定过早，dashboard 允许追加重试的次数。")

(defun custom/dashboard--frame-startup-state (frame)
  "返回 FRAME 当前的启动缓冲区状态。"
  (if-let* ((window (and (frame-live-p frame)
                         (frame-selected-window frame)))
            (buffer (window-buffer window)))
      (with-current-buffer buffer
        (cond
         ((derived-mode-p 'dashboard-mode) 'dashboard)
         ((buffer-file-name) 'file)
         ((custom/dashboard--placeholder-buffer-p buffer) 'placeholder)
         (t 'pending)))
    'pending))

(defun custom/dashboard--run-open-check (frame retries-left)
  "根据 FRAME 当前状态决定是否显示或重试 dashboard。"
  (when (frame-live-p frame)
    (set-frame-parameter frame 'custom-dashboard-open-scheduled nil)
    (pcase (custom/dashboard--frame-startup-state frame)
      ('placeholder
       (custom/dashboard--display-in-frame frame))
      ((or 'dashboard 'file)
       nil)
      (_
       (when (> retries-left 0)
         (custom/dashboard--schedule-open-for-frame
          frame
          (1- retries-left)))))))

(defun custom/dashboard--schedule-open-for-frame (frame retries-left)
  "为 FRAME 安排一次 dashboard 打开检查。RETRIES-LEFT 为剩余重试次数。"
  (when (and (frame-live-p frame)
             (not (frame-parameter frame 'custom-dashboard-open-scheduled)))
    ;; daemon 场景下 after-make-frame 与 server-after-make-frame 可能对同一 frame 连续触发。
    ;; 用 frame 参数避免并发重复调度，但在每轮检查结束后允许重新调度。
    (set-frame-parameter frame 'custom-dashboard-open-scheduled t)
    (run-with-idle-timer
     custom:dashboard-open-idle-delay nil
     (lambda (idle-frame idle-retries-left)
       (when (frame-live-p idle-frame)
         (custom/dashboard--run-open-check idle-frame idle-retries-left)))
     frame retries-left)))

(defun custom/dashboard-open-for-client-frame (&optional frame)
  "在 daemon 创建的 client FRAME 中打开 dashboard。
仅当该 frame 仍停留在占位缓冲区时接管，避免覆盖 `emacsclient FILE`。"
  (custom/dashboard--schedule-open-for-frame
   (or frame (selected-frame))
   custom:dashboard-open-retries))

(custom/register-daemon-frame-hook #'custom/dashboard-open-for-client-frame)

(provide 'dashboard)
;;; dashboard.el ends here
