;;; calendar.el --- 日历管理 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 使用 Emacs 内置日历，通过延迟加载优化启动时间。
;;
;; 组件：
;; - calendar：内置日历
;; - calfw-org：以月视图展示 Org 议程
;;
;; 性能优化：仅在调用时加载 calendar / calfw-org，减少基础模块加载负担。
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

(use-package calendar
  :ensure nil
  :commands calendar)

(use-package calfw-org
  :defer t
  :commands cfw:open-org-calendar)

;; 全局快捷键（通过 autoload 首次触发）
(global-set-key (kbd "C-c c") 'calendar)

(provide 'calendar)
;;; calendar.el ends here
