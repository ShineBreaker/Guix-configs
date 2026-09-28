;;; demo-inject.el --- 录制环境补丁（用户 init 之前 --load） -*- lexical-binding: t; -*-
;;; Commentary: advice-add 对未定义符号合法，main.el 定义后 advice 依然生效。
;;; 已验证生效：eglot 拦截 / 失焦保存拦截 / apheleia 拦截。
;;; 已知未解：真实 daemon 占用 "server" socket 导致的 server warning 仍会弹
;;; （fset server-mode / server-start 均未能拦截）；出现在画面底部约三行，
;;; 接受后期裁剪，录前先抽帧确认底部干净。

;; 1) 关闭失焦自动保存：Xvfb 无 WM，frame-focus-state 恒 nil → 失焦保存循环
(when (fboundp 'advice-add)
  (advice-add 'custom/schedule-focus-save :override #'ignore
              '((name . "demo-disable-focus-save"))))

;; 2) 关闭 eglot 自动启动：pylsp 连接会把 buffer 弄脏成 unsaved
(advice-add 'eglot-ensure :override #'ignore
            '((name . "demo-disable-eglot")))

;; 3) 关闭 apheleia：保存后异步格式化让 buffer 永远 modified
(advice-add 'apheleia-global-mode :override #'ignore
            '((name . "demo-disable-apheleia")))

;; 4) 静音无害 warning 弹窗
(setq warning-minimum-level :error)

;;; demo-inject.el ends here
