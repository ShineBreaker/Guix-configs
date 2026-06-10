;;; modules/ui/notification/doctor.el -*- lexical-binding: t; -*-

;; doctor 范式: 在用户跑 `bin/doom doctor` 时执行健康检查。
;; 用来检测这个模块的外部依赖是否齐全。

(assert! (or (not (eq system-type 'gnu/linux))
             (executable-find "notify-send"))
         "On Linux, install `libnotify-bin` for desktop notifications.")
