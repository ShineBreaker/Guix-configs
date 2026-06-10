;;; modules/ui/notification/autoload.el -*- lexical-binding: t; -*-

;; autoload 范式: 在这里定义的函数直到被调用时才会 require 'alert。
;; 适合"实现函数,但不希望在配置加载阶段付出代价"的场景。

;;;###autoload
(defun +notification/notify (title body)
  "Send a desktop notification with TITLE and BODY."
  (interactive
   (list (read-string "Title: " (or +notification--last-title ""))
         (read-string "Body: ")))
  (require 'alert)
  (setq +notification--last-title title)
  (alert (concat title "\n" body)
         :title title
         :timeout +notification-default-timeout
         :icon +notification-icon))

;;;###autoload
(defun +notification/notify-done (&optional msg)
  "Send a 'done' notification, re-using the last title."
  (interactive "P")
  (let ((msg (if msg
                 (read-string "Done message: ")
               "done")))
    (+notification/notify
     (or +notification--last-title "Emacs")
     msg)))
