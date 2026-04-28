;;; guix.el --- Guix 特定集成 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; Guix 环境检测和特定优化。

;;; Code:

;; Guix 环境变量继承
(when custom:in-guix-environment-p
  (message "检测到 Guix 环境: %s" custom:guix-profile))

;; 确保 Guix profile 的 bin 在 PATH 中
(when (file-directory-p (expand-file-name "bin" custom:guix-profile))
  (add-to-list 'exec-path (expand-file-name "bin" custom:guix-profile)))

(provide 'guix)
;;; guix.el ends here
