;;; modules/ui/notification/config.el -*- lexical-binding: t; -*-

;; 这是 doom 风格自建模块的 config.el 模板。
;; 关键范式:
;;   1. 用 defcustom 暴露用户可调选项
;;   2. 用 (modulep! :category module +flag) 读 flag
;;   3. 用 use-package! 配置,带 :hook / :commands / :config
;;   4. 用 map! 绑键(替代散落的 global-set-key)
;;   5. 用 :when (executable-find ...) 之类检测外部依赖


;;
;;; User-facing customizations
;;

(defcustom +notification-default-timeout 5
  "Default timeout (in seconds) for desktop notifications."
  :type 'integer
  :group '+notification)

(defcustom +notification-icon nil
  "Path to an icon to use in notifications. nil = use Emacs icon."
  :type '(choice file (const nil))
  :group '+notification)


;;
;;; Packages
;;

;; 基础包 alert
(use-package! alert
  :commands (alert +notification/notify +notification/notify-done)
  :preface
  (defvar +notification--last-title nil
    "Title of the last notification, for the `+notification/notify-done' command.")

  :config
  ;; 配置 alert 默认参数
  (setq alert-default-style
        (cond ((modulep! +alerts) 'notifications)
              ((eq system-type 'darwin) 'osx-notification-center')
              ((eq system-type 'windows-nt) 'toast)
              (t 'libnotify)))

  (when (modulep! +alerts)
    ;; +alerts flag 启用时加载更高级的包
    (use-package! notifications
      :when (and (executable-find "notify-send")
                 (eq system-type 'gnu/linux))
      :config
      (notifications-notify :title "Emacs" :body "ready")))

  ;; 用户命令
  (defun +notification/notify (title body)
    "Send a desktop notification with TITLE and BODY."
    (interactive
     (list (read-string "Title: " (or +notification--last-title ""))
           (read-string "Body: ")))
    (setq +notification--last-title title)
    (alert (concat title "\n" body)
           :title title
           :timeout +notification-default-timeout
           :icon +notification-icon))

  (defun +notification/notify-done (&optional msg)
    "Send a 'done' notification, re-using the last title."
    (interactive "P")
    (let ((msg (if msg
                   (read-string "Done message: ")
                 "done")))
      (+notification/notify
       (or +notification--last-title "Emacs")
       msg))))


;;
;;; Keybindings
;;

(map! :leader
      :desc "Notifications"
      "t n n" #'+notification/notify
      :desc "Notify done"
      "t n d" #'+notification/notify-done)
