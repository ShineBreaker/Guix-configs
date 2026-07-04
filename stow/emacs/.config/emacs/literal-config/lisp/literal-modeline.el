;;; modeline.el --- 自写 starship 风格 mode-line -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 自写 mode-line，starship 风格的「· 分隔 + Nerd Font 图标 + 语义 face」提示条。
;;
;; 设计目标：
;; - 不依赖 doom-modeline / mini-echo / spaceline 等第三方 mode-line 包。
;; - 所有 buffer 都显示 mode-line，dashboard / ghostel / magit / help 等视图类
;;   buffer 不再特殊隐藏。
;; - 复用 Emacs 内建 `mode-line-format' 与 `:eval' 实现动态段，并根据
;;   `window-width' 在 wide / medium / narrow / compact 四档内收缩信息密度。
;; - 右段通过 `mode-line-format-right-align' 对齐，避免 `%-' 生成连字符填充。
;; - GUI + nerd-icons 可用时显示 Nerd Font 图标；TTY 或包不可用时图标降级为空，
;;   segment 文本仍然可读。
;;
;; 段结构：
;;   左段（文件相关，从左到右）：
;;     路径 · 文件图标+文件名 · VCS 分支 · Git 状态 · 编码 · 位置/大小 · 行列位置
;;   右段（Emacs / 系统 / 插件状态）：
;;     Flycheck · Eglot · global-mode-string · major-mode · 电池 · 时间
;;
;; 宽度档：
;; - wide   (>= 120): 显示完整信息。
;; - medium (100-119): 保留核心编辑信息，压缩 Eglot / Flycheck 等段。
;; - narrow  (80-99): 保留短路径、文件名、VCS、Git 状态、major-mode、行列、时间。
;; - compact (< 80): 只显示 major-mode，避免小窗口 mode-line 互相挤压。
;;
;; 性能约束：
;; - `mode-line-format' 会在 redisplay 中频繁求值，segment 函数必须轻量且返回
;;   字符串，不能返回 nil。
;; - Flycheck 错误数由 hook 刷新到 buffer-local 缓存，mode-line 只读缓存。
;; - Eglot server 信息由 hook / segment 内轻量刷新缓存，避免未加载时引用未定义符号。
;; - Project 名称在当前 buffer 缓存，保存和切换 major-mode 时失效。
;; - 电池显示复用 `display-battery-mode' 的 timer，不在 redisplay 中调用
;;   `battery-update'。
;;
;; 加载顺序：`appearance.el' → `modeline.el' → `coding/*'。
;; 本文件早于 flycheck / eglot 加载，所以所有相关段必须使用 `fboundp' /
;; `bound-and-true-p' 守卫。
;; `appearance.el' 提供 spacious-padding 间距控制，本文件只提供内容。

;;; Code:

(require 'battery)
(require 'project)
(require 'seq)
(require 'subr-x)

(declare-function nerd-icons-icon-for-file "nerd-icons")
(declare-function nerd-icons-icon-for-mode "nerd-icons")
(declare-function nerd-icons-giticon "nerd-icons")
(declare-function nerd-icons-faicon "nerd-icons")
(declare-function nerd-icons-mdicon "nerd-icons")
(declare-function jsonrpc-running-p "jsonrpc")
(defvar flycheck-current-errors)
(defvar mode-line-format-right-align)

;; ═════════════════════════════════════════════════════════════════════════════
;; 常量与缓存
;; ═════════════════════════════════════════════════════════════════════════════

(defvaralias 'literal:modeline-name-max-width 'literal:modeline-path-max-width)

(defgroup literal-modeline nil
  "自写 starship 风格 mode-line。"
  :group 'mode-line)

(defcustom literal:modeline-show-time t
  "是否在 mode-line 右段显示当前时间。"
  :type 'boolean)

(defcustom literal:modeline-show-vcs t
  "是否在 mode-line 右段显示 VCS 分支。"
  :type 'boolean)

(defcustom literal:modeline-path-max-width 40
  "路径段最大显示宽度。超过部分截断为省略号。"
  :type 'integer)

(defvar literal:modeline--nerd-icons-available
  (require 'nerd-icons nil t)
  "启动期一次性缓存 nerd-icons 是否可用。")

(defvar-local literal:modeline--flycheck-counts '(0 0)
  "当前 buffer 的 Flycheck 计数缓存，格式为 (ERRORS WARNINGS)。")

(defvar-local literal:modeline--eglot-info nil
  "当前 buffer 的 Eglot 缓存，格式为 (SERVER-NAME STATUS)。")

(defvar-local literal:modeline--project-cache :unknown
  "当前 buffer 的 project 缓存。
值为 :unknown 表示未计算；nil 表示不在项目中；否则为 (ROOT NAME)。")

(defvar-local literal:modeline--vc-state-cache :unknown
  "当前 buffer 的 VC 状态缓存。
值为 :unknown 表示未计算；nil 表示不在 VC 控制下；否则为 `vc-state' 返回值。")

;; ═════════════════════════════════════════════════════════════════════════════
;; 基础辅助函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/modeline-tier ()
  "根据当前窗口宽度返回 `wide'、`medium'、`narrow' 或 `compact'。"
  (let ((width (window-width)))
    (cond
     ((>= width 120) 'wide)
     ((>= width 100) 'medium)
     ((>= width 80) 'narrow)
     (t 'compact))))

(defun literal/modeline-wide-p ()
  "当前 mode-line 是否处于 wide 档。"
  (eq (literal/modeline-tier) 'wide))

(defun literal/modeline-medium-p ()
  "当前 mode-line 是否处于 medium 档。"
  (eq (literal/modeline-tier) 'medium))

(defun literal/modeline-narrow-p ()
  "当前 mode-line 是否处于 narrow 档。"
  (eq (literal/modeline-tier) 'narrow))

(defun literal/modeline-compact-p ()
  "当前 mode-line 是否处于 compact 档。"
  (eq (literal/modeline-tier) 'compact))

(defun literal/modeline--graphic-icons-p ()
  "当前 frame 是否适合显示 nerd-icons 图标。"
  (and (display-graphic-p)
       literal:modeline--nerd-icons-available))

(defun literal/modeline-icon (kind name &optional file)
  "返回 KIND 类型的 nerd-icons 图标 NAME。
FILE 只在 KIND 为 `file' 时使用。图标不可用或出错时返回空串。"
  (if (literal/modeline--graphic-icons-p)
      (or (ignore-errors
            (pcase kind
              ('file (nerd-icons-icon-for-file (or file name)))
              ('mode (nerd-icons-icon-for-mode major-mode))
              ('git (nerd-icons-giticon name))
              ('md (nerd-icons-mdicon name))
              ('fa (if (string-prefix-p "nf-md-" name)
                       (nerd-icons-mdicon name)
                     (nerd-icons-faicon name)))
              (_ (nerd-icons-faicon name))))
          "")
    ""))

(defun literal/modeline--escape-percent (text)
  "转义 TEXT 中的 %，避免 mode-line 把它当格式控制。"
  (replace-regexp-in-string "%" "%%" (or text "") nil t))

(defun literal/modeline--with-icon (icon text)
  "拼接 ICON 与 TEXT，任一为空时只返回另一项。"
  (let ((safe-icon (or icon ""))
        (safe-text (or text "")))
    (cond
     ((string-empty-p safe-icon) safe-text)
     ((string-empty-p safe-text) safe-icon)
     (t (concat safe-icon " " safe-text)))))

(defun literal/modeline--segment (text &optional face)
  "返回带 FACE 的 TEXT；TEXT 为空时返回空串。"
  (let ((safe-text (or text "")))
    (if (string-empty-p safe-text)
        ""
      (if face
          (propertize safe-text 'face face)
        safe-text))))

(defun literal/modeline--separator-before (text)
  "TEXT 非空时在前面加分隔符。"
  (if (string-empty-p (or text ""))
      ""
    (concat " · " text)))

(defun literal/modeline--truncate (text width)
  "把 TEXT 截断到 WIDTH。"
  (truncate-string-to-width (or text "") width 0 nil t))

(defun literal/modeline--file-in-directory-p (file directory)
  "判断 FILE 是否在 DIRECTORY 内。"
  (let ((file-dir (file-name-directory (expand-file-name file)))
        (root (file-name-as-directory (expand-file-name directory))))
    (and file-dir (file-in-directory-p file-dir root))))

(defun literal/modeline--path-component-initial (component)
  "返回路径 COMPONENT 的首字母。
隐藏目录名保留点，例如 .config 显示为 .c。"
  (let* ((trimmed (string-trim component))
         (hidden (string-prefix-p "." trimmed))
         (body (if hidden
                   (replace-regexp-in-string "\\`[.[:space:]]+" "" trimmed)
                 trimmed)))
    (cond
     ((string-empty-p body) "")
     (hidden (concat "." (substring body 0 1)))
     (t (substring body 0 1)))))

(defun literal/modeline--initials-path (path)
  "把 PATH 中每个目录名缩成首字母。"
  (let* ((remote-prefix (or (file-remote-p path) ""))
         (local-name (or (file-remote-p path 'localname) path))
         (abbrev (abbreviate-file-name local-name))
         (without-home (if (string-prefix-p "~/" abbrev)
                           (substring abbrev 2)
                         abbrev))
         (parts (split-string without-home "/" t))
         (initials (seq-remove
                    #'string-empty-p
                    (mapcar #'literal/modeline--path-component-initial parts))))
    (concat remote-prefix (string-join initials "/"))))

(defun literal/modeline--project-info ()
  "返回当前 buffer 的 project 缓存，格式为 (ROOT NAME) 或 nil。"
  (when (eq literal:modeline--project-cache :unknown)
    (setq literal:modeline--project-cache
          (condition-case nil
              (when-let* ((project (project-current nil))
                          (root (project-root project))
                          (name (file-name-nondirectory
                                 (directory-file-name root))))
                (list root name))
            (error nil))))
  literal:modeline--project-cache)

(defun literal/modeline--reset-project-cache ()
  "失效当前 buffer 的 project 缓存。"
  (setq literal:modeline--project-cache :unknown))

(defun literal/modeline--refresh-vc-state (&rest _)
  "刷新当前 buffer 的 VC 状态缓存。"
  (setq literal:modeline--vc-state-cache
        (if buffer-file-name
            (condition-case nil
                (when-let* ((backend (vc-backend buffer-file-name)))
                  (vc-state buffer-file-name backend))
              (error nil))
          nil)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 缓存刷新 hook
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/modeline--refresh-flycheck-counts (&rest _)
  "刷新当前 buffer 的 Flycheck 错误计数缓存。"
  (setq literal:modeline--flycheck-counts
        (if (and (bound-and-true-p flycheck-mode)
                 (fboundp 'flycheck-count-errors))
            (let* ((counts (ignore-errors (flycheck-count-errors flycheck-current-errors)))
                   (errors (or (cdr (assq 'error counts)) 0))
                   (warnings (or (cdr (assq 'warning counts)) 0)))
              (list errors warnings))
          '(0 0))))

(defun literal/modeline--eglot-server-name (server)
  "返回 SERVER 的简短名称。"
  (cond
   ((and server (fboundp 'eglot--server-nickname))
    (or (ignore-errors (eglot--server-nickname server)) "eglot"))
   (server "eglot")
   (t "")))

(defun literal/modeline--refresh-eglot-info (&rest _)
  "刷新当前 buffer 的 Eglot 状态缓存。"
  (setq literal:modeline--eglot-info
        (if (and (bound-and-true-p eglot--managed-mode)
                 (fboundp 'eglot-current-server))
            (let* ((server (ignore-errors (eglot-current-server)))
                   (name (literal/modeline--eglot-server-name server))
                   (live (and server
                              (or (not (fboundp 'jsonrpc-running-p))
                                  (ignore-errors (jsonrpc-running-p server)))))
                   (status (cond
                            (live 'connected)
                            (server 'connecting)
                            (t 'disconnected))))
              (when (not (string-empty-p name))
                (list name status)))
          nil)))

(with-eval-after-load 'flycheck
  (add-hook 'flycheck-after-syntax-check-hook
            #'literal/modeline--refresh-flycheck-counts)
  (add-hook 'flycheck-mode-hook
            #'literal/modeline--refresh-flycheck-counts))

(with-eval-after-load 'eglot
  (add-hook 'eglot-managed-mode-hook
            #'literal/modeline--refresh-eglot-info)
  (add-hook 'eglot-server-initialized-hook
            #'literal/modeline--refresh-eglot-info))

(add-hook 'after-save-hook #'literal/modeline--reset-project-cache)
(add-hook 'after-change-major-mode-hook #'literal/modeline--reset-project-cache)
(add-hook 'find-file-hook #'literal/modeline--refresh-vc-state)
(add-hook 'after-save-hook #'literal/modeline--refresh-vc-state)
(add-hook 'after-revert-hook #'literal/modeline--refresh-vc-state)

;; ═════════════════════════════════════════════════════════════════════════════
;; 左段：文件相关
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/modeline-file-icon ()
  "返回当前文件类型图标。"
  (if (literal/modeline-compact-p)
      ""
    (literal/modeline-icon 'file "file" (or (buffer-file-name) (buffer-name)))))

(defun literal/modeline-path ()
  "返回简化目录段。文件名由 `literal/modeline-buffer-name' 显示。"
  (cond
   ((literal/modeline-compact-p) "")
   ((not (buffer-file-name)) "")
   (t
    (let* ((file (buffer-file-name))
           (project-info (literal/modeline--project-info))
           (root (car-safe project-info))
           (project-name (cadr project-info))
           (relative (and root
                          (not (file-remote-p file))
                          (literal/modeline--file-in-directory-p file root)
                          (file-relative-name file root)))
           (relative-dir (and relative
                              (file-name-directory relative)))
           (display (cond
                     ((and relative-dir
                           (not (string= relative-dir "./")))
                      (literal/modeline--initials-path
                       (directory-file-name relative-dir)))
                     (relative
                      (literal/modeline--initials-path project-name))
                     (t
                      (when-let* ((directory (file-name-directory file)))
                        (literal/modeline--initials-path
                         (directory-file-name directory))))))
           (icon (literal/modeline-icon 'fa "nf-md-folder_open")))
      (if (and display
               (not (string-empty-p display))
               (not (string= display ".")))
          (literal/modeline--segment
           (literal/modeline--with-icon
            icon
            (literal/modeline--truncate display literal:modeline-path-max-width))
           'shadow)
        "")))))

(defun literal/modeline-buffer-name ()
  "返回带文件类型图标的当前 buffer 文件名或 buffer 名。"
  (if (literal/modeline-compact-p)
      ""
    (let* ((name (if-let* ((file (buffer-file-name)))
                     (file-name-nondirectory file)
                   (buffer-name)))
           (width (pcase (literal/modeline-tier)
                    ('wide 32)
                    ('medium 24)
                    (_ 18))))
      (literal/modeline--segment
       (literal/modeline--with-icon
        (literal/modeline-file-icon)
       (literal/modeline--truncate name width))
       'font-lock-function-name-face))))

(defun literal/modeline-buffer-name-section ()
  "返回文件名段。当前面无路径段时不加前置分隔符。"
  (let ((name (literal/modeline-buffer-name)))
    (cond
     ((string-empty-p name) "")
     ((string-empty-p (literal/modeline-path)) name)
     (t (literal/modeline--separator-before name)))))

(defun literal/modeline-buffer-modified ()
  "返回 buffer 修改标记。已修改显示铅笔图标，否则空字符串。"
  (if (and (not (literal/modeline-compact-p))
           (buffer-modified-p))
      (literal/modeline--segment
       (literal/modeline--with-icon
        (literal/modeline-icon 'fa "nf-md-pencil")
        "modified")
       'warning)
    ""))

(defun literal/modeline-line-ending ()
  "返回当前 buffer 的行尾类型。"
  (if (literal/modeline-wide-p)
      (let* ((eol (coding-system-eol-type buffer-file-coding-system))
             (name (pcase eol
                     (0 "LF")
                     (1 "CRLF")
                     (2 "CR")
                     (_ "None"))))
        (literal/modeline--segment
         (literal/modeline--with-icon
          (literal/modeline-icon 'fa "nf-md-text")
          name)
         'shadow))
    ""))

(defun literal/modeline-flycheck ()
  "返回 Flycheck 错误/警告数。"
  (if (and (not (literal/modeline-compact-p))
           (not (literal/modeline-narrow-p))
           (bound-and-true-p flycheck-mode)
           (fboundp 'flycheck-count-errors))
      (let* ((errors (or (car literal:modeline--flycheck-counts) 0))
             (warnings (or (cadr literal:modeline--flycheck-counts) 0))
             (total (+ errors warnings))
             (tier (literal/modeline-tier))
             (icon (cond
                    ((> errors 0) (literal/modeline-icon 'fa "nf-md-times_circle"))
                    ((> warnings 0) (literal/modeline-icon 'fa "nf-md-alert"))
                    (t (literal/modeline-icon 'fa "nf-md-check_circle"))))
             (text (pcase tier
                     ('wide (format "E:%d W:%d" errors warnings))
                     ('medium (format "%d:%d" errors warnings))
                     (_ (number-to-string total))))
             (face (cond
                    ((> errors 0) 'error)
                    ((> warnings 0) 'warning)
                    (t 'success))))
        (literal/modeline--segment
         (literal/modeline--with-icon icon text)
         face))
    ""))

(defun literal/modeline-eglot ()
  "返回 Eglot 服务器与状态。"
  (when (and (bound-and-true-p eglot--managed-mode)
             (fboundp 'eglot-current-server))
    (literal/modeline--refresh-eglot-info))
  (if-let* ((info literal:modeline--eglot-info)
            (name (car-safe info))
            (status (cadr info)))
      (let* ((point (pcase status
                      ('connected "●")
                      ('connecting "◐")
                      (_ "○")))
             (face (pcase status
                     ('connected 'success)
                     ('connecting 'warning)
                     (_ 'shadow)))
             (text (if (literal/modeline-wide-p)
                       (format "%s %s" name point)
                     point)))
        (if (or (literal/modeline-narrow-p)
                (literal/modeline-compact-p))
            ""
          (literal/modeline--segment
           (literal/modeline--with-icon
            (literal/modeline-icon 'fa "nf-md-server_network")
            text)
           face)))
    ""))

(defun literal/modeline-position ()
  "返回当前光标位置百分比与 buffer 大小。"
  (if (or (literal/modeline-narrow-p)
          (literal/modeline-compact-p))
      ""
    (let* ((range (max 1 (- (point-max) (point-min))))
           (percent (round (* 100.0 (/ (float (- (point) (point-min))) range))))
           (text (if (literal/modeline-wide-p)
                     (format "%s %s"
                             (literal/modeline--with-icon
                              (literal/modeline-icon 'fa "nf-md-flag_checkered")
                              (format "%d%%%%" percent))
                             (literal/modeline--with-icon
                              (literal/modeline-icon 'fa "nf-md-format_list_bulleted")
                              (file-size-human-readable (buffer-size))))
                   (format "%d%%%%" percent))))
      (literal/modeline--segment
       (literal/modeline--with-icon
        (if (literal/modeline-wide-p)
            ""
          (literal/modeline-icon 'fa "nf-md-flag_checkered"))
        text)
       'font-lock-doc-face))))

(defun literal/modeline-major-mode ()
  "返回 major-mode 简化名。"
  (let* ((text (symbol-name major-mode))
         (icon (literal/modeline-icon 'fa "nf-md-code_tags")))
    (literal/modeline--segment
     (literal/modeline--with-icon icon text)
     'font-lock-keyword-face)))

(defun literal/modeline-major-mode-section ()
  "返回 compact 档左侧 major-mode 段。"
  (let ((mode (literal/modeline-major-mode)))
    (if (literal/modeline-compact-p) mode "")))

(defun literal/modeline-right-major-mode ()
  "返回右段 major-mode。compact 档由左侧独占显示。"
  (if (literal/modeline-compact-p)
      ""
    (literal/modeline-major-mode)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 右段：Emacs / 系统 / 插件状态
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/modeline-format-time ()
  "返回格式化的时间字符串。"
  (if (and literal:modeline-show-time
           (not (literal/modeline-compact-p)))
      (let* ((wide (literal/modeline-wide-p))
             (time (format-time-string (if wide "%H:%M:%S" "%H:%M")))
             (icon (literal/modeline-icon
                    'fa "nf-md-clock")))
        (literal/modeline--segment
         (literal/modeline--with-icon icon time)
         'font-lock-string-face))
    ""))

(defun literal/modeline-battery ()
  "返回电池状态。"
  (if (literal/modeline-wide-p)
      (let* ((text (and (boundp 'battery-mode-line-string)
                        (stringp battery-mode-line-string)
                        (string-trim battery-mode-line-string)))
             (percent (and text
                           (string-match "\\([0-9]+\\)%%" text)
                           (string-to-number (match-string 1 text))))
             (face (cond
                    ((not percent) 'font-lock-doc-face)
                    ((>= percent 50) 'success)
                    ((>= percent 20) 'warning)
                    (t 'error))))
        (if (and text (not (string-empty-p text)))
            (literal/modeline--segment
             (literal/modeline--with-icon
              (literal/modeline-icon 'fa "nf-md-battery")
              (literal/modeline--escape-percent text))
             face)
          ""))
    ""))

(defun literal/modeline-global-status ()
  "返回不与自定义段重复的 `global-mode-string' 内容。"
  (if (literal/modeline-compact-p)
      ""
    (let* ((items (and (boundp 'global-mode-string) global-mode-string))
           (filtered (seq-remove
                      (lambda (item)
                        (eq item 'battery-mode-line-string))
                      (if (listp items) items (list items))))
           (text (string-trim (format-mode-line filtered))))
      (if (string-empty-p text) "" text))))

(defun literal/modeline-project ()
  "返回当前 project 短名。"
  (if (or (literal/modeline-narrow-p)
          (literal/modeline-compact-p))
      ""
    (if-let* ((info (literal/modeline--project-info))
              (name (cadr info)))
        (literal/modeline--segment
         (literal/modeline--with-icon
          (literal/modeline-icon 'fa "nf-md-folder")
          name)
         'font-lock-constant-face)
      "")))

(defun literal/modeline-vcs-info ()
  "返回当前 buffer 所在 VCS 分支名。"
  (if (and literal:modeline-show-vcs
           (not (literal/modeline-compact-p)))
      (condition-case nil
          (let ((line (and (bound-and-true-p vc-mode)
                           (stringp vc-mode)
                           vc-mode)))
            (if (and line (string-match "\\(?:Git\\|Hg\\|SVN\\)[-:]\\([^() ]+\\)" line))
                (let ((branch (string-trim (match-string 1 line))))
                  (literal/modeline--segment
                   (literal/modeline--with-icon
                    (literal/modeline-icon 'fa "nf-md-source_branch")
                    branch)
                   'font-lock-type-face))
              ""))
        (error ""))
    ""))

(defun literal/modeline-git-status ()
  "返回当前 buffer 的 Git/VC 状态。"
  (if (or (literal/modeline-compact-p)
          (not buffer-file-name))
      ""
    (when (eq literal:modeline--vc-state-cache :unknown)
      (literal/modeline--refresh-vc-state))
    (let* ((state (cond
                   ((buffer-modified-p) 'buffer-modified)
                   (t literal:modeline--vc-state-cache)))
           (spec (pcase state
                   ('up-to-date (list "clean" "nf-md-check_circle" 'success))
                   ('edited (list "edited" "nf-md-pencil" 'warning))
                   ('buffer-modified (list "unsaved" "nf-md-content_save_alert" 'warning))
                   ('added (list "added" "nf-md-plus_circle" 'success))
                   ('removed (list "removed" "nf-md-minus_circle" 'error))
                   ('missing (list "missing" "nf-md-alert_circle" 'error))
                   ('conflict (list "conflict" "nf-md-alert_octagon" 'error))
                   ('needs-merge (list "merge" "nf-md-source_merge" 'warning))
                   ('needs-update (list "update" "nf-md-cloud_download" 'warning))
                   ('ignored (list "ignored" "nf-md-eye_off" 'shadow))
                   ('unregistered (list "untracked" "nf-md-help_circle" 'warning))
                   (_ nil))))
      (if spec
          (pcase-let ((`(,text ,icon ,face) spec))
            (literal/modeline--segment
             (literal/modeline--with-icon
              (literal/modeline-icon 'fa icon)
              text)
             face))
        ""))))

(defun literal/modeline-coding ()
  "返回当前 buffer 的编码系统缩写名。"
  (if (or (literal/modeline-narrow-p)
          (literal/modeline-compact-p))
      ""
    (let* ((base (coding-system-base buffer-file-coding-system))
           (name (upcase (symbol-name (or base 'undecided)))))
      (literal/modeline--segment
       (literal/modeline--with-icon
        (literal/modeline-icon 'fa "nf-md-lock")
        name)
       'font-lock-string-face))))

(defun literal/modeline-location ()
  "返回当前行列位置。"
  (if (literal/modeline-compact-p)
      ""
    (literal/modeline--segment
     (literal/modeline--with-icon
      (literal/modeline-icon 'fa "nf-md-map_marker")
      "(%l,%c)")
     'shadow)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 默认 mode-line 格式
;; ═════════════════════════════════════════════════════════════════════════════

(defvar literal:modeline-active-format nil
  "自写 starship 风格 mode-line 的 active 格式。")

(defvar literal:modeline-inactive-format nil
  "自写 starship 风格 mode-line 的 inactive 格式。")

(setq literal:modeline-active-format
      '(" "
        (:eval (literal/modeline-path))
        (:eval (literal/modeline-buffer-name-section))
        (:eval (literal/modeline--separator-before (literal/modeline-vcs-info)))
        (:eval (literal/modeline--separator-before (literal/modeline-git-status)))
        (:eval (literal/modeline--separator-before (literal/modeline-coding)))
        (:eval (literal/modeline--separator-before (literal/modeline-position)))
        (:eval (literal/modeline--separator-before (literal/modeline-location)))
        (:eval (literal/modeline-major-mode-section))
        mode-line-format-right-align
        " "
        (:eval (literal/modeline-flycheck))
        (:eval (literal/modeline--separator-before (literal/modeline-eglot)))
        (:eval (literal/modeline--separator-before (literal/modeline-global-status)))
        (:eval (literal/modeline--separator-before (literal/modeline-right-major-mode)))
        (:eval (literal/modeline--separator-before (literal/modeline-battery)))
        (:eval (literal/modeline--separator-before (literal/modeline-format-time)))))

(setq literal:modeline-inactive-format
      '(" "
        (:eval (literal/modeline-path))
        (:eval (literal/modeline-buffer-name-section))
        (:eval (literal/modeline--separator-before (literal/modeline-vcs-info)))
        (:eval (literal/modeline--separator-before (literal/modeline-git-status)))
        (:eval (literal/modeline--separator-before (literal/modeline-location)))
        (:eval (literal/modeline-major-mode-section))
        mode-line-format-right-align
        " "
        (:eval (literal/modeline--separator-before (literal/modeline-right-major-mode)))
        (:eval (literal/modeline--separator-before (literal/modeline-format-time)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 初始化
;; ═════════════════════════════════════════════════════════════════════════════

(setq-default mode-line-format literal:modeline-active-format)
(setq-default mode-line-inactive-format literal:modeline-inactive-format)

(size-indication-mode 1)
(display-battery-mode 1)

;; 主动 line-spacing: 0，避免与 spacious-padding 双重间距叠加。
(setq line-spacing 0)

(provide 'literal-modeline)
;;; modeline.el ends here
