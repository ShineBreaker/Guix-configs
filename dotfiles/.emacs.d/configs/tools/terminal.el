;;; terminal.el --- 终端模拟器 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 vterm 终端模拟器。

;;; Code:

;; Vterm（高性能终端模拟器）
(use-package vterm
  :commands vterm
  :bind ("C-c v t" . vterm))

(provide 'terminal)
;;; terminal.el ends here
