;;; literal-frame.el --- daemon/client frame 生命周期工具 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai004@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 替代旧配置的 `custom/register-daemon-frame-hook'。
;;
;; 在 daemon/client 架构下，所有依赖窗口 / display 的初始化（主题、字体、
;; childframe、tab-line、dashboard 等）都必须在每个新 frame 创建时触发，
;; 而不能只在 init.el 加载时跑一次。
;;
;; Emacs 29+ 提供了两个互补的 hook：
;; - `after-make-frame-functions'：所有 frame 创建时触发（含 daemon 第一个 GUI frame）
;; - `server-after-make-frame-hook'：emacsclient 创建 frame 时触发
;;
;; 本模块提供 `literal/add-frame-hook'，在 daemon 模式下同时挂两个 hook
;; （覆盖 `emacs --fg-daemon' + `emacsclient' 两条路径），非 daemon 模式
;; 下立即用当前 frame 调用一次函数（standalone 冷启动）。
;;
;; 使用范式：
;;   (literal/add-frame-hook #'my-setup-display)
;; 而不是手写 (add-hook 'after-make-frame-functions ...)。

;;; Code:

(defun literal/add-frame-hook (function)
  "注册 FUNCTION 在每个新 frame 创建时执行。
- daemon 模式：同时挂 `after-make-frame-functions' 和 `server-after-make-frame-hook'
- 非 daemon 模式：立即对当前 frame 调用一次（standalone 冷启动）
FUNCTION 接受一个可选参数 FRAME。"
  (if (daemonp)
      (progn
        (add-hook 'after-make-frame-functions function)
        (when (boundp 'server-after-make-frame-hook)
          (add-hook 'server-after-make-frame-hook function)))
    ;; standalone：当前 frame 已存在，直接跑一次
    (funcall function (selected-frame))))

(defun literal/remove-frame-hook (function)
  "移除 FUNCTION 的 frame hook 注册。"
  (remove-hook 'after-make-frame-functions function)
  (when (boundp 'server-after-make-frame-hook)
    (remove-hook 'server-after-make-frame-hook function)))

(defun literal/daemon-runtime-p ()
  "返回当前是否为可交互的 daemon 会话（用于延迟预热等场景）。"
  (and (daemonp) (not noninteractive)))

(provide 'literal-frame)
;;; literal-frame.el ends here
