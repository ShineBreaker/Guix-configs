;;; init.el --- Emacs 主入口（Guix 版） -*- lexical-binding: t; -*-

;;; Commentary:
;; 本配置遵循以下原则：
;; 1. 包管理完全交给 Guix（不使用 package.el 自动安装）。
;; 2. 在不破坏现有功能的前提下，进行模块化与现代化改造。
;; 3. 以中文注释维护，便于长期演进。

;;; Code:

;; 将 `lisp/` 纳入加载路径（兼容正常启动与字节编译场景）。
(let ((base-dir
       (file-name-directory
        (or load-file-name
            (bound-and-true-p byte-compile-current-file)
            buffer-file-name
            default-directory))))
  (add-to-list 'load-path (expand-file-name "lisp" base-dir)))

(require 'core-startup)
(require 'core-ui)
(require 'core-keybindings)
(require 'core-completion)
(require 'core-editing)
(require 'core-dev)
(require 'core-workspace)

(message "[init] 配置加载完成，用时 %.2fs，GC 次数 %d"
         (float-time (time-subtract after-init-time before-init-time))
         gcs-done)

(provide 'init)
;;; init.el ends here
