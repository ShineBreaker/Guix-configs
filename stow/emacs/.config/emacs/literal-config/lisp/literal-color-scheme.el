;;; literal-color-scheme.el --- 系统颜色方案自动适配 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai004@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 自动跟随 Darkman 的颜色方案（深色/浅色模式）。
;; 通过 D-Bus 监听 nl.whynothugo.darkman 的 ModeChanged 信号。
;; 使用状态文件缓存当前模式，供 early-init.el 防闪屏使用。
;;
;; Daemon/Client 模式优化：
;; 在 daemon 模式下，初始化被延迟到首个 GUI 帧创建时执行，
;; 避免在没有 display 环境时过早加载 ef-themes 导致非法 frame 错误。

;;; Code:

(require 'dbus)
(require 'literal-bootstrap)
(require 'literal-frame)

;; ═════════════════════════════════════════════════════════════════════════════
;; 配置变量
;; ═════════════════════════════════════════════════════════════════════════════

(defcustom literal/color-scheme-light-theme 'ef-cyprus
  "浅色模式下加载的主题。"
  :type 'symbol
  :group 'appearance)

(defcustom literal/color-scheme-dark-theme 'ef-owl
  "深色模式下加载的主题。"
  :type 'symbol
  :group 'appearance)

(defcustom literal/color-scheme-light-bg "#f5f5f5"
  "浅色模式的背景色（用于防闪屏）。"
  :type 'string
  :group 'appearance)

(defcustom literal/color-scheme-dark-bg "#0a0a0a"
  "深色模式的背景色（用于防闪屏）。"
  :type 'string
  :group 'appearance)

(defconst literal/color-scheme-state-file
  (expand-file-name "var/color-scheme-state.el" user-emacs-directory)
  "颜色方案状态文件路径。")

(defvar literal/color-scheme-current-mode nil
  "当前颜色方案模式（'light 或 'dark）。")

(defvar literal/color-scheme--initialized nil
  "颜色方案模块是否已完成初始化。")

(defvar literal/color-scheme--applying-theme nil
  "是否正在执行主题切换，避免 frame hook 重入。")

(defun literal/color-scheme-clear-bootstrap-frame-colors ()
  "移除 early-init 为防闪屏注入的占位前景/背景色。"
  (dolist (alist-var '(default-frame-alist initial-frame-alist))
    (set alist-var
         (assq-delete-all
          'background-color
          (assq-delete-all 'foreground-color (symbol-value alist-var))))))

(defun literal/color-scheme-read-state ()
  "从状态文件读取当前模式。返回 'light 或 'dark，文件不存在或读取失败时返回 nil。"
  (condition-case err
      (when (file-exists-p literal/color-scheme-state-file)
        (let ((content (with-temp-buffer
                         (insert-file-contents literal/color-scheme-state-file)
                         (buffer-string))))
          (cond
           ((string-match-p "dark" content) 'dark)
           ((string-match-p "light" content) 'light)
           (t nil))))
    (error
     (message "[color-scheme] 无法读取状态文件: %s" (error-message-string err))
     nil)))

(defun literal/color-scheme-save-state (mode)
  "将当前模式保存到状态文件。MODE 为 'light 或 'dark。"
  (condition-case err
      (let ((dir (file-name-directory literal/color-scheme-state-file)))
        (unless (file-exists-p dir)
          (make-directory dir t))
        (with-temp-buffer
          (insert ";; color-scheme-state.el -*- lexical-binding: t; -*-\n")
          (insert ";; 自动生成，勿手动修改\n")
          (insert (format "(setq literal/color-scheme-current-mode '%s)\n" mode))
          (insert (format "(setq literal/color-scheme-current-bg \"%s\")\n"
                          (if (eq mode 'light)
                              literal/color-scheme-light-bg
                            literal/color-scheme-dark-bg)))
          (write-region (point-min) (point-max) literal/color-scheme-state-file)))
    (error
     (message "[color-scheme] 无法保存状态文件: %s" (error-message-string err)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; D-Bus 接口常量
;; ═════════════════════════════════════════════════════════════════════════════

(defconst literal/color-scheme-dbus-service "nl.whynothugo.darkman"
  "Darkman D-Bus 服务名称。")

(defconst literal/color-scheme-dbus-path "/nl/whynothugo/darkman"
  "Darkman D-Bus 对象路径。")

(defconst literal/color-scheme-dbus-interface "nl.whynothugo.darkman"
  "Darkman D-Bus 接口。")

;; ═════════════════════════════════════════════════════════════════════════════
;; 核心函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/color-scheme-get-from-dbus ()
  "通过 D-Bus 获取当前 Darkman 模式。返回 'light、'dark 或 nil。"
  (condition-case err
      (when (featurep 'dbus)
        (let ((mode (dbus-get-property
                     :session
                     literal/color-scheme-dbus-service
                     literal/color-scheme-dbus-path
                     literal/color-scheme-dbus-interface
                     "Mode")))
          (cond
           ((string= mode "light") 'light)
           ((string= mode "dark") 'dark)
           (t nil))))
    (error
     (message "[color-scheme] D-Bus 获取失败: %s" (error-message-string err))
     nil)))

(defun literal/color-scheme-apply-theme (mode)
  "根据 MODE 加载对应的主题并保存状态。
MODE 为 'light 或 'dark。
终端 standalone 模式仅记录状态；daemon 模式下只要存在 GUI frame 即加载主题。"
  (setq literal/color-scheme-current-mode mode)
  (literal/color-scheme-save-state mode)
  (unless literal/color-scheme--applying-theme
    (let ((literal/color-scheme--applying-theme t)
          (target-theme (pcase mode
                          ('dark literal/color-scheme-dark-theme)
                          ('light literal/color-scheme-light-theme)
                          (_ nil))))
      (when target-theme
        (when (or (display-graphic-p)
                  (and (daemonp) (literal/graphic-frame-exists-p)))
          (unless (eq (car custom-enabled-themes) target-theme)
            (ef-themes-load-theme target-theme))
          (literal/color-scheme-clear-bootstrap-frame-colors)
          (message "[color-scheme] 已同步主题: %s" target-theme))))))

(defun literal/color-scheme-sync ()
  "手动同步系统颜色方案到 Emacs 主题（交互式命令）。"
  (interactive)
  (let ((mode (literal/color-scheme-get-from-dbus)))
    (if mode
        (literal/color-scheme-apply-theme mode)
      (message "[color-scheme] 无法获取 Darkman 模式"))))

;; ═════════════════════════════════════════════════════════════════════════════
;; D-Bus 信号监听
;; ═════════════════════════════════════════════════════════════════════════════

(defvar literal/color-scheme-dbus-handler nil
  "D-Bus 信号监听器的注册 ID。")

(defun literal/color-scheme-register-listener ()
  "注册 D-Bus 信号监听器，响应 Darkman 模式变化。"
  (condition-case err
      (when (and (featurep 'dbus)
                 (not literal/color-scheme-dbus-handler))
        (setq literal/color-scheme-dbus-handler
              (dbus-register-signal
               :session
               literal/color-scheme-dbus-service
               literal/color-scheme-dbus-path
               literal/color-scheme-dbus-interface
               "ModeChanged"
               (lambda (mode)
                 (let ((new-mode (cond
                                  ((string= mode "light") 'light)
                                  ((string= mode "dark") 'dark))))
                   (when (and new-mode
                              (not (eq new-mode literal/color-scheme-current-mode)))
                     (message "[color-scheme] Darkman 模式变化: %s" mode)
                     (literal/color-scheme-apply-theme new-mode))))))
        (message "[color-scheme] 已注册 D-Bus 监听器"))
    (error
     (message "[color-scheme] 无法注册 D-Bus 监听器: %s" (error-message-string err))
     nil)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 初始化
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/graphic-frame-exists-p ()
  "返回当前会话中是否存在任意 GUI frame。"
  (catch 'found
    (dolist (frame (frame-list))
      (when (display-graphic-p frame)
        (throw 'found t)))
    nil))

(defun literal/color-scheme-init ()
  "初始化颜色方案适配：
1. 先从状态文件读取模式，立即应用主题
2. 异步验证 D-Bus，不一致则更新
3. 注册 D-Bus 监听器"
  (let ((initial-mode (or (literal/color-scheme-read-state)
                          (literal/color-scheme-get-from-dbus)
                          'dark)))
    (literal/color-scheme-apply-theme initial-mode)
    (setq literal/color-scheme--initialized t)
    (literal/color-scheme-register-listener)
    (run-with-idle-timer 1 nil
                         (lambda ()
                           (let ((dbus-mode (literal/color-scheme-get-from-dbus)))
                             (when (and dbus-mode
                                        (not (eq dbus-mode literal/color-scheme-current-mode)))
                               (message "[color-scheme] 状态文件与 D-Bus 不一致，更新为 %s" dbus-mode)
                               (literal/color-scheme-apply-theme dbus-mode)))))))

(defun literal/color-scheme-apply-for-frame (&optional frame)
  "在 FRAME 可用时补齐与主题相关的 frame 初始化。
主题是全局状态，不能在每个新 frame 上重复 `load-theme`，否则多 client
几乎同时创建 frame 时容易在 PGTK/GTK 初始化路径中崩溃。"
  (with-selected-frame (or frame (selected-frame))
    (when (display-graphic-p)
      (when (fboundp 'ef-themes-take-over-modus-themes-mode)
        (ef-themes-take-over-modus-themes-mode 1))
      (if (not literal/color-scheme--initialized)
          (literal/color-scheme-init)
        (let ((target-theme (pcase literal/color-scheme-current-mode
                              ('dark literal/color-scheme-dark-theme)
                              ('light literal/color-scheme-light-theme)
                              (_ nil))))
          (when (and target-theme
                     (not (eq (car custom-enabled-themes) target-theme)))
            (ef-themes-load-theme target-theme)
            (literal/color-scheme-clear-bootstrap-frame-colors)
            (message "[color-scheme] 新 frame 同步主题: %s" target-theme)))))))

(defun literal/color-scheme-delayed-init (&optional frame)
  "延迟初始化颜色方案（daemon 模式首帧创建时触发）。
仅执行一次，之后自动移除自身。"
  (when (and frame
             (display-graphic-p frame)
             (not literal/color-scheme--initialized))
    (with-selected-frame frame
      (require 'ef-themes)
      (literal/color-scheme-init)))
  (literal/remove-frame-hook #'literal/color-scheme-delayed-init))

;; daemon 模式：延迟到首帧创建时再加载主题和初始化
;; 非 daemon 模式：帧已存在，立即初始化
(if (daemonp)
    (progn
      (literal/add-frame-hook #'literal/color-scheme-delayed-init)
      (literal/add-frame-hook #'literal/color-scheme-apply-for-frame))
  (require 'ef-themes)
  (literal/color-scheme-init))

;; ═════════════════════════════════════════════════════════════════════════════
;; 自定义 face 颜色同步
;; ═════════════════════════════════════════════════════════════════════════════

(require 'modus-themes)
(defun literal/color-scheme-apply-custom-face-colors ()
  "主题切换后重新应用自定义 face 颜色（使用 ef-themes 调色板标识符）。"
  (modus-themes-with-colors
    (when (facep 'custom-help-section-title)
      (set-face-attribute 'custom-help-section-title nil :foreground blue))
    (when (facep 'dashboard-card)
      (set-face-attribute 'dashboard-card nil :background bg-alt))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 主题切换后的级联刷新
;; ═════════════════════════════════════════════════════════════════════════════

(defvar literal/theme-refresh-functions nil
  "主题切换后需要调用的刷新函数列表。")

(defun literal/register-theme-refresh! (fn)
  "注册 FN 为主题切换后调用的刷新函数（幂等）。"
  (unless (memq fn literal/theme-refresh-functions)
    (setq literal/theme-refresh-functions
          (append literal/theme-refresh-functions (list fn)))))

(defun literal/run-theme-refresh ()
  "执行所有已注册的主题切换刷新函数。"
  (dolist (fn literal/theme-refresh-functions)
    (condition-case err
        (funcall fn)
      (error
       (message "[color-scheme] theme-refresh %S failed: %S"
                fn (error-message-string err))))))

(defvar literal/theme-buffer-refreshers nil
  "Alist of (MAJOR-MODE . REFRESH-FN) pairs。")

(defun literal/register-buffer-refresh! (mode refresh-fn)
  "为 MAJOR-MODE 注册主题切换后的 buffer 重渲染函数 REFRESH-FN。幂等。"
  (let ((entry (assq mode literal/theme-buffer-refreshers)))
    (unless (and entry (eq (cdr entry) refresh-fn))
      (if entry
          (setcdr entry refresh-fn)
        (push (cons mode refresh-fn) literal/theme-buffer-refreshers)))))

(defun literal/color-scheme-refresh-registered-buffers ()
  "重新渲染所有可见窗口中已注册 mode 的缓冲区。"
  (dolist (window (window-list nil 'no-minibuf))
    (when (window-live-p window)
      (let ((buffer (window-buffer window)))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (let ((refresher (cdr (assq major-mode literal/theme-buffer-refreshers))))
              (when (and refresher (functionp refresher))
                (condition-case err
                    (with-selected-window window
                      (funcall refresher))
                  (error
                   (message "[color-scheme] buffer-refresh %s failed: %S"
                            major-mode (error-message-string err))))))))))))

(literal/register-theme-refresh! #'literal/color-scheme-apply-custom-face-colors)
(literal/register-theme-refresh! #'literal/color-scheme-refresh-registered-buffers)
(add-hook 'ef-themes-after-load-theme-hook #'literal/run-theme-refresh)
(literal/run-theme-refresh)

(provide 'literal-color-scheme)
;;; literal-color-scheme.el ends here
