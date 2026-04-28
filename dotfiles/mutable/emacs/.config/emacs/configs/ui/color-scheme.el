;;; color-scheme.el --- 系统颜色方案自动适配 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 自动跟随 Darkman 的颜色方案（深色/浅色模式）。
;; 通过 D-Bus 监听 nl.whynothugo.darkman 的 ModeChanged 信号。
;; 使用状态文件缓存当前模式，供 early-init.el 防闪屏使用。
;;
;; Daemon/Client 模式优化：
;; 在 daemon 模式下，初始化被延迟到首个 GUI 帧创建时执行，
;; 避免在没有 display 环境时过早加载 ef-themes 导致非法 frame 错误。
;; 新 frame 的主题同步与延迟初始化都通过
;; `custom/register-daemon-frame-hook' 统一注册。
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

(require 'dbus)

;; ═════════════════════════════════════════════════════════════════════════════
;; 配置变量
;; ═════════════════════════════════════════════════════════════════════════════

(defcustom custom/color-scheme-light-theme 'ef-cyprus
  "浅色模式下加载的主题。"
  :type 'symbol
  :group 'appearance)

(defcustom custom/color-scheme-dark-theme 'ef-owl
  "深色模式下加载的主题。"
  :type 'symbol
  :group 'appearance)

(defcustom custom/color-scheme-light-bg "#f5f5f5"
  "浅色模式的背景色（用于防闪屏）。"
  :type 'string
  :group 'appearance)

(defcustom custom/color-scheme-dark-bg "#0a0a0a"
  "深色模式的背景色（用于防闪屏）。"
  :type 'string
  :group 'appearance)

;; ═════════════════════════════════════════════════════════════════════════════
;; 状态文件
;; ═════════════════════════════════════════════════════════════════════════════

(defconst custom/color-scheme-state-file
  (expand-file-name "var/color-scheme-state.el" user-emacs-directory)
  "颜色方案状态文件路径。")

(defvar custom/color-scheme-current-mode nil
  "当前颜色方案模式（'light 或 'dark）。")

(defvar custom/color-scheme--initialized nil
  "颜色方案模块是否已完成初始化。")

(defvar custom/color-scheme--applying-theme nil
  "是否正在执行主题切换，避免 frame hook 重入。")

(defun custom/color-scheme-clear-bootstrap-frame-colors ()
  "移除 early-init 为防闪屏注入的占位前景/背景色。

这些颜色只应该服务于首个 GUI frame 的冷启动防闪屏；一旦真实主题已加载，
若继续保留在 `default-frame-alist' 中，后续新建 client frame 会继承占位色，
导致它们显示成“首帧正常、后续帧错色”的状态。"
  (dolist (alist-var '(default-frame-alist initial-frame-alist))
    (set alist-var
         (assq-delete-all
          'background-color
          (assq-delete-all 'foreground-color (symbol-value alist-var))))))

(defun custom/color-scheme-read-state ()
  "从状态文件读取当前模式。
返回 'light 或 'dark，文件不存在或读取失败时返回 nil。"
  (condition-case err
      (when (file-exists-p custom/color-scheme-state-file)
        (let ((content (with-temp-buffer
                         (insert-file-contents custom/color-scheme-state-file)
                         (buffer-string))))
          (cond
           ((string-match-p "dark" content) 'dark)
           ((string-match-p "light" content) 'light)
           (t nil))))
    (error
     (message "[color-scheme] 无法读取状态文件: %s" (error-message-string err))
     nil)))

(defun custom/color-scheme-save-state (mode)
  "将当前模式保存到状态文件。
MODE 为 'light 或 'dark。"
  (condition-case err
      (let ((dir (file-name-directory custom/color-scheme-state-file)))
        (unless (file-exists-p dir)
          (make-directory dir t))
        (with-temp-buffer
          (insert ";; color-scheme-state.el -*- lexical-binding: t; -*-\n")
          (insert ";; 自动生成，勿手动修改\n")
          (insert (format "(setq custom/color-scheme-current-mode '%s)\n" mode))
          (insert (format "(setq custom/color-scheme-current-bg \"%s\")\n"
                          (if (eq mode 'light)
                              custom/color-scheme-light-bg
                            custom/color-scheme-dark-bg)))
          (write-region (point-min) (point-max) custom/color-scheme-state-file)))
    (error
     (message "[color-scheme] 无法保存状态文件: %s" (error-message-string err)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; D-Bus 接口常量
;; ═════════════════════════════════════════════════════════════════════════════

(defconst custom/color-scheme-dbus-service "nl.whynothugo.darkman"
  "Darkman D-Bus 服务名称。")

(defconst custom/color-scheme-dbus-path "/nl/whynothugo/darkman"
  "Darkman D-Bus 对象路径。")

(defconst custom/color-scheme-dbus-interface "nl.whynothugo.darkman"
  "Darkman D-Bus 接口。")

;; ═════════════════════════════════════════════════════════════════════════════
;; 核心函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/color-scheme-get-from-dbus ()
  "通过 D-Bus 获取当前 Darkman 模式。
返回 'light、'dark 或 nil。"
  (condition-case err
      (when (featurep 'dbus)
        (let ((mode (dbus-get-property
                     :session
                     custom/color-scheme-dbus-service
                     custom/color-scheme-dbus-path
                     custom/color-scheme-dbus-interface
                     "Mode")))
          (cond
           ((string= mode "light") 'light)
           ((string= mode "dark") 'dark)
           (t nil))))
    (error
     (message "[color-scheme] D-Bus 获取失败: %s" (error-message-string err))
     nil)))

(defun custom/color-scheme-apply-theme (mode)
  "根据 MODE 加载对应的主题并保存状态。
MODE 为 'light 或 'dark。
终端 standalone 模式仅记录状态；daemon 模式下只要存在 GUI frame 即加载主题。"
  (custom/diag "color-scheme" "应用主题: mode=%s" mode)
  (setq custom/color-scheme-current-mode mode)
  (custom/color-scheme-save-state mode)
  (unless custom/color-scheme--applying-theme
    (let ((custom/color-scheme--applying-theme t)
          (target-theme (pcase mode
                          ('dark custom/color-scheme-dark-theme)
                          ('light custom/color-scheme-light-theme)
                          (_ nil))))
      (when target-theme
        ;; 主题是全局状态。daemon + 多 client 下 D-Bus 信号可能在 TTY frame
        ;; 被选中时到达，但只要存在 GUI frame 就必须更新，否则 GUI client
        ;; 显示过时配色。
        (when (or (display-graphic-p)
                  (and (daemonp) (custom/graphic-frame-exists-p)))
          (unless (eq (car custom-enabled-themes) target-theme)
            (ef-themes-load-theme target-theme))
          (custom/color-scheme-clear-bootstrap-frame-colors)
          (message "[color-scheme] 已同步主题: %s" target-theme))))))

(defun custom/color-scheme-sync ()
  "手动同步系统颜色方案到 Emacs 主题（交互式命令）。"
  (interactive)
  (custom/diag "color-scheme" "同步颜色方案")
  (let ((mode (custom/color-scheme-get-from-dbus)))
    (if mode
        (custom/color-scheme-apply-theme mode)
      (message "[color-scheme] 无法获取 Darkman 模式"))))

;; ═════════════════════════════════════════════════════════════════════════════
;; D-Bus 信号监听
;; ═════════════════════════════════════════════════════════════════════════════

(defvar custom/color-scheme-dbus-handler nil
  "D-Bus 信号监听器的注册 ID。")

(defun custom/color-scheme-register-listener ()
  "注册 D-Bus 信号监听器，响应 Darkman 模式变化。"
  (custom/diag "color-scheme" "注册 DBus 监听")
  (condition-case err
      (when (and (featurep 'dbus)
                 (not custom/color-scheme-dbus-handler))
        (setq custom/color-scheme-dbus-handler
              (dbus-register-signal
               :session
               custom/color-scheme-dbus-service
               custom/color-scheme-dbus-path
               custom/color-scheme-dbus-interface
               "ModeChanged"
               (lambda (mode)
                 (let ((new-mode (cond
                                  ((string= mode "light") 'light)
                                  ((string= mode "dark") 'dark))))
                   (when (and new-mode
                              (not (eq new-mode custom/color-scheme-current-mode)))
                     (message "[color-scheme] Darkman 模式变化: %s" mode)
                     (custom/color-scheme-apply-theme new-mode))))))
        (message "[color-scheme] 已注册 D-Bus 监听器"))
    (error
     (message "[color-scheme] 无法注册 D-Bus 监听器: %s" (error-message-string err))
     nil)))

(defun custom/color-scheme-unregister-listener ()
  "取消 D-Bus 信号监听器。"
  (when custom/color-scheme-dbus-handler
    (dbus-unregister-object custom/color-scheme-dbus-handler)
    (setq custom/color-scheme-dbus-handler nil)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 初始化
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/color-scheme-init ()
  "初始化颜色方案适配：
1. 先从状态文件读取模式，立即应用主题
2. 异步验证 D-Bus，不一致则更新
3. 注册 D-Bus 监听器"
  (custom/diag "color-scheme" "初始化颜色方案")
  ;; 优先使用缓存状态；缓存不存在时回退到 D-Bus，再回退到 dark。
  ;; 这样即使状态文件被误删，也能自愈并重新写回缓存供 early-init 防闪屏。
  (let ((initial-mode (or (custom/color-scheme-read-state)
                          (custom/color-scheme-get-from-dbus)
                          'dark)))
    (custom/color-scheme-apply-theme initial-mode)
    (setq custom/color-scheme--initialized t)
    ;; 无论是否存在缓存文件都注册监听器
    (custom/color-scheme-register-listener)
    ;; 异步验证 D-Bus 状态（1秒后）
     (run-with-idle-timer 1 nil
                          (lambda ()
                            (let ((dbus-mode (custom/color-scheme-get-from-dbus)))
                              (when (and dbus-mode
                                         (not (eq dbus-mode custom/color-scheme-current-mode)))
                                (message "[color-scheme] 状态文件与 D-Bus 不一致，更新为 %s" dbus-mode)
                                (custom/color-scheme-apply-theme dbus-mode)))))))

(defun custom/color-scheme-apply-for-frame (&optional frame)
  "在 FRAME 可用时补齐与主题相关的 frame 初始化。

注意：主题是全局状态，这里不能在 daemon 的每个新 frame 上重复执行
`load-theme`，否则多 client 几乎同时创建 frame 时容易在 PGTK/GTK
初始化路径中崩溃。"
  (with-selected-frame (or frame (selected-frame))
    (when (display-graphic-p)
      (when (fboundp 'ef-themes-take-over-modus-themes-mode)
        (ef-themes-take-over-modus-themes-mode 1))
      (if (not custom/color-scheme--initialized)
          (progn
            (custom/color-scheme-init))
        ;; 已初始化时确保主题与当前模式一致
        ;; （可能在无 GUI frame 期间发生了模式变化）
        (let ((target-theme (pcase custom/color-scheme-current-mode
                              ('dark custom/color-scheme-dark-theme)
                              ('light custom/color-scheme-light-theme)
                              (_ nil))))
          (when (and target-theme
                     (not (eq (car custom-enabled-themes) target-theme)))
            (ef-themes-load-theme target-theme)
            (custom/color-scheme-clear-bootstrap-frame-colors)
            (message "[color-scheme] 新 frame 同步主题: %s" target-theme)))))))

(defun custom/color-scheme-delayed-init (&optional frame)
  "延迟初始化颜色方案（daemon 模式首帧创建时触发）。
确保 ef-themes 已加载，然后执行完整初始化（读状态、应用主题、注册 D-Bus）。
仅执行一次，之后自动移除自身。"
  (when (and frame
             (display-graphic-p frame)
             (not custom/color-scheme--initialized))
    (with-selected-frame frame
      (require 'ef-themes)
      (custom/color-scheme-init)))
  (custom/unregister-daemon-frame-hook #'custom/color-scheme-delayed-init))

;; daemon 模式：延迟到首帧创建时再加载主题和初始化
;; 非 daemon 模式：帧已存在，立即初始化
(if (daemonp)
    (progn
      (custom/register-daemon-frame-hook #'custom/color-scheme-delayed-init)
      (custom/register-daemon-frame-hook #'custom/color-scheme-apply-for-frame))
  (require 'ef-themes)
  (custom/color-scheme-init))

(provide 'color-scheme)
;;; color-scheme.el ends here
