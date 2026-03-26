;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; startup.el --- 启动与持久化 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置启动行为、GC 策略、持久化等。
;;
;; 优化说明：
;; 1. 恢复文件处理器列表 - early-init.el 中被清空以加速启动
;; 2. GCMH 智能 GC - 空闲时自动垃圾回收，编辑时不打断
;; 3. 延迟加载持久化功能 - 减少启动时间
;; 4. 自动保存 - 失去焦点时保存所有缓冲区

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 启动后恢复设置
;; ═════════════════════════════════════════════════════════════════════════════

;; 恢复文件处理器列表（在 early-init.el 中被清空）
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist file-name-handler-alist-original)))

;; 优先加载较新的源文件（.el 比 .elc 新时加载 .el）
(setq load-prefer-newer t)

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
;; - gcmh-high-cons-threshold: 编辑时的 GC 阈值（64MB）
(use-package gcmh
  :demand t
  :custom
  (gcmh-idle-delay 'auto)                      ; 自动计算空闲延迟
  (gcmh-auto-idle-delay-factor 10)             ; 延迟因子
  (gcmh-high-cons-threshold (* 64 1024 1024))  ; 64MB 阈值
  :config
  (gcmh-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; LSP 通信优化
;; ═════════════════════════════════════════════════════════════════════════════

;; 提高进程输出读取上限（从默认的 4KB 提升到 3MB）
;; 这对 LSP 服务器通信非常重要，可以显著提升响应速度
;; 如果 LSP 响应慢，可以尝试进一步提高这个值
(setq read-process-output-max (* 3 1024 1024))  ; 3MB

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
  :defer 1
  :custom
  (desktop-restore-eager 5)  ; 立即恢复前 5 个缓冲区
  (desktop-save nil)         ; 退出时自动保存，不询问
  :config
  (desktop-save-mode 1))

(provide 'startup)
;;; startup.el ends here
