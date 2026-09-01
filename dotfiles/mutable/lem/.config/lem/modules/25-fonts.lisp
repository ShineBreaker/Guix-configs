;;; modules/25-fonts.lisp — 图形前端字体与字号
;;;
;;; 上游 nightly（2025-08 起）图形前端由 SDL2 换为 webview（WebKitGTK +
;;; Canvas/JS 渲染）：:sdl2-*-font / :sdl2-font-size 等 config 键已无读者，
;;; 字体只能经运行时 API set-font-name / set-font-size 设置（JS 端默认
;;; Monospace 18px），且 webview 不持久化字号——每次启动都必须在此设置。
;;; 语义差异：SDL2 字号是物理像素；webview 字号是 CSS 逻辑像素，物理
;;; 尺寸 = N × DPR。2x 屏（3072x1920）上 13 逻辑像素 ≈ 旧 SDL2 的
;;; 26 物理像素观感。
;;; 部署 config.lisp 里遗留的 :SDL2-* 键无人读取，无害残留，勿再新增。
;;; ncurses 前端无字体概念，调用报错由 ignore-errors 吞掉。

(in-package :lem-user)

;; 字体族名走 fontconfig 家族名（CSS font-family 语义），不再是 ttf 路径；
;; CN 版含完整中文字形，单族名即覆盖 CJK，无需多字体槽。
(ignore-errors (vs-call :lem "SET-FONT-NAME" "Maple Mono NF CN"))
(ignore-errors (vs-call :lem "SET-FONT-SIZE" 13))
