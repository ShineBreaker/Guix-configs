;;; calendar.el --- 日历管理 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Calfw 日历框架。

;;; Code:

;; Calfw（日历框架）
(use-package calfw
  :commands cfw:open-calendar-buffer
  :bind ("C-c c" . cfw:open-calendar-buffer))

(provide 'calendar)
;;; calendar.el ends here
