;;; startup.el --- 启动与持久化 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置启动行为、GC 策略、持久化等。
;;
;; 优化说明：
;; 1. 恢复文件处理器列表 - early-init.el 中被清空以加速启动
;; 2. GCMH 智能 GC - 空闲时自动垃圾回收，编辑时不打断
;; 3. 延迟加载持久化功能 - 减少启动时间
;; 4. 备份文件集中管理 - 统一存放到 var/backup/，不污染工作目录
;; 5. 自动保存 - 失去焦点时保存所有缓冲区
;; 6. Daemon 预热 - 在后台空闲时预载常用模块，减少首帧延迟
;; 7. 自动编译 - 保存时自动编译配置，不再编译 Guix 路径
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

(defgroup custom/startup nil
  "启动与 daemon 运行时相关设置。"
  :group 'convenience)

(defcustom custom/desktop-enable-in-daemon nil
  "非 nil 时在 daemon 模式下启用 desktop 会话恢复。

长期驻留的 Emacs daemon 本身就是会话载体，默认不再恢复上一轮
desktop，避免把旧窗口/缓冲区状态恢复成本转移到 daemon 启动阶段。"
  :type 'boolean
  :group 'custom/startup)

(defcustom custom/daemon-preload-delay 0.5
  "daemon 空闲多久后开始预热常用功能。"
  :type 'number
  :group 'custom/startup)

(defcustom custom/daemon-preload-features
  '(savehist
    recentf
    bookmark
    consult
    embark
    embark-consult
    which-key
    helpful
    corfu
    corfu-popupinfo
    ef-themes)
  "daemon 启动后在后台预热的 feature 列表。

这些模块原先主要依赖延迟加载，适合 standalone 冷启动；在 daemon 架构下，
预热一次能减少首个 `emacsclient' 会话遇到的即时加载开销。"
  :type '(repeat symbol)
  :group 'custom/startup)

(defvar custom--daemon-preload-timer nil
  "当前 daemon 预热流程使用的 idle timer。")

(defun custom/daemon-runtime-p ()
  "返回当前是否为可交互的 daemon 会话。"
  (and (daemonp) (not noninteractive)))

(defun custom/daemon-preload-common-features ()
  "在 daemon 空闲时预热常用功能。"
  (setq custom--daemon-preload-timer nil)
  (when (custom/daemon-runtime-p)
    (dolist (feature custom/daemon-preload-features)
      (unless (featurep feature)
        (condition-case err
            (require feature nil t)
          (error
           (message "[daemon-preload] %s 加载失败: %s"
                    feature
                    (error-message-string err))))))))

(defun custom/daemon-schedule-preload ()
  "在 daemon 启动后安排一次后台预热。"
  (when (custom/daemon-runtime-p)
    (when (timerp custom--daemon-preload-timer)
      (cancel-timer custom--daemon-preload-timer))
    (setq custom--daemon-preload-timer
          (run-with-idle-timer custom/daemon-preload-delay
                               nil
                               #'custom/daemon-preload-common-features))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 启动后恢复设置
;; ═════════════════════════════════════════════════════════════════════════════

;; 恢复文件处理器列表（在 early-init.el 中被清空）
(add-hook 'emacs-startup-hook
          (lambda ()
            (when (boundp 'file-name-handler-alist-original)
              (setq file-name-handler-alist file-name-handler-alist-original))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 垃圾回收优化
;; ═════════════════════════════════════════════════════════════════════════════

;; GCMH - 智能垃圾回收管理
;; 工作原理：
;; - 编辑时：提高 GC 阈值，减少 GC 打断
;; - 空闲时：自动执行 GC，清理内存
;;
;; 配置说明：
;; - gcmh-idle-delay: 'auto 表示自动计算空闲延迟
;; - gcmh-auto-idle-delay-factor: 延迟因子，越大越不频繁 GC
;; - gcmh-high-cons-threshold: 编辑时的 GC 阈值（32MB，daemon 长运行优化）
(use-package gcmh
  :demand t
  :custom
  (gcmh-idle-delay 'auto)                      ; 自动计算空闲延迟
  (gcmh-auto-idle-delay-factor 10)             ; 延迟因子
  (gcmh-high-cons-threshold (* 32 1024 1024))  ; 32MB 阈值（优化长运行）
  :config
  (gcmh-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; 自动编译优化
;; ═════════════════════════════════════════════════════════════════════════════

;; auto-compile - 自动编译 Emacs Lisp 文件为字节码
;; 配置说明：
;; - auto-compile-on-load-mode: 加载文件时自动编译
;; - auto-compile-on-save-mode: 保存文件时自动编译
;; - auto-compile-directory-predicate: 限制只编译用户配置目录（不编译 Guix store）
(use-package auto-compile
  :defer t
  :config
  (setq auto-compile-on-load-mode t)
  (setq auto-compile-on-save-mode t)
  (setq auto-compile-use-mode-line nil)
  ;; 只对用户配置文件目录生效，不编译 Guix store 中的包
  (setq auto-compile-directory-predicate
        (lambda (dir)
          (string-prefix-p (expand-file-name "~/.config/emacs/") dir))))

;; ═════════════════════════════════════════════════════════════════════════════
;; LSP 通信优化
;; ═════════════════════════════════════════════════════════════════════════════

;; 提高进程输出读取上限（从默认的 4KB 提升到 4MB）
;; 这对 LSP 服务器通信非常重要，可以显著提升响应速度
;; 如果 LSP 响应慢，可以尝试进一步提高这个值
(setq read-process-output-max (* 4 1024 1024)       ; 4MB
      process-adaptive-read-buffering nil          ; 禁用 IO 自适应缓冲（防止卡顿）
      fast-but-imprecise-scrolling t)               ; 快速滚动，减少字体渲染开销

;; ═════════════════════════════════════════════════════════════════════════════
;; 基础启动体验
;; ═════════════════════════════════════════════════════════════════════════════

;; 禁用启动画面和消息
(setq inhibit-startup-screen t          ; 不显示启动画面
      initial-scratch-message nil       ; *scratch* 缓冲区不显示欢迎消息
      ring-bell-function 'ignore        ; 禁用响铃（包括视觉响铃）
      confirm-kill-emacs nil            ; 退出 Emacs 时不需要确认
      confirm-kill-processes nil)       ; 关闭进程时不需要确认

;; ═════════════════════════════════════════════════════════════════════════════
;; 文件管理 - no-littering
;; ═════════════════════════════════════════════════════════════════════════════

;; no-littering - 统一管理缓存和配置文件
;; 作用：将各种包生成的文件统一放到 var/ 和 etc/ 目录
;; - var/: 运行时数据（自动保存、备份等）
;; - etc/: 配置数据（custom.el 等）
;;
;; 维护说明：
;; - 如果某个包的缓存文件位置不对，检查是否需要手动配置
;; - 可以通过 (no-littering-expand-var-file-name "path") 获取 var 路径
;; - 可以通过 (no-littering-expand-etc-file-name "path") 获取 etc 路径
(use-package no-littering
  :demand t
  :config
  ;; 备份文件统一放到 var/backup/ 目录，避免在原文件旁产生 ~ 后缀文件
  (setq backup-directory-alist
        `((".*" . ,(no-littering-expand-var-file-name "backup/"))))

  ;; 自动保存文件统一放到 var/auto-save/ 目录
  (setq auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t)))

  ;; Custom 配置文件位置（通过 M-x customize 修改的设置）
  (setq custom-file (no-littering-expand-etc-file-name "custom.el"))

  ;; 如果 custom.el 存在则加载（不报错）
  (when (file-exists-p custom-file)
    (load custom-file t)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 历史记录持久化
;; ═════════════════════════════════════════════════════════════════════════════

;; savehist - 保存命令历史、搜索历史等
;; 延迟 0.5 秒加载，避免影响启动速度
(use-package savehist
  :defer 0.5
  :config
  (savehist-mode 1))

;; recentf - 记录最近打开的文件
;; 延迟 1 秒加载，进一步减少启动时间
(use-package recentf
  :defer 1
  :custom
  (recentf-max-saved-items 300)  ; 最多保存 300 个文件记录
  :config
  (recentf-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; 自动保存
;; ═════════════════════════════════════════════════════════════════════════════

;; 失去焦点时自动保存所有缓冲区
;; 使用场景：切换到浏览器/终端时自动保存，避免忘记保存
(add-function :after after-focus-change-function
              (lambda ()
                (unless (frame-focus-state)
                  (save-some-buffers t))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 会话恢复
;; ═════════════════════════════════════════════════════════════════════════════

;; desktop - 保存和恢复 Emacs 会话（打开的文件、窗口布局等）
;; 延迟 1 秒加载，避免影响启动
;;
;; 使用说明：
;; - desktop-save-mode 1: 启用自动保存会话
;; - desktop-restore-eager 5: 启动时立即恢复前 5 个缓冲区，其余延迟加载
;; - desktop-save nil: 退出时不询问是否保存（自动保存）
;;
;; 如果不需要会话恢复功能，可以注释掉这段配置
(use-package desktop
  :if (or (not (daemonp))
          custom/desktop-enable-in-daemon)
  :defer 1
  :custom
  (desktop-restore-eager 5)  ; 立即恢复前 5 个缓冲区
  (desktop-save nil)         ; 退出时自动保存，不询问
  :config
  (desktop-save-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Emacs Server
;; ═════════════════════════════════════════════════════════════════════════════

;; 启用 server-mode，允许 emacsclient 连接到当前 Emacs 会话。
;; 配合 terminal.el 中的 EDITOR 设置，终端命令可直接在当前 Emacs 中打开文件。
;; daemon 模式下 server 已由 Emacs 自身管理，无需重复启动。
(unless (or (daemonp) noninteractive)
  (server-mode 1))

;; daemon 模式下将常用交互模块转移到后台预热，换取更稳定的 emacsclient 首帧响应。
(add-hook 'emacs-startup-hook #'custom/daemon-schedule-preload)

(provide 'startup)
;;; startup.el ends here
