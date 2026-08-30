;;; modules/25-fonts.lisp — SDL2 前端字体与字号
;;;
;;; 关键时序：SDL2 前端在 setup 阶段打开字体，早于 init.lisp 加载，
;;; 故本模块的 (setf lem:config ...) 不影响本次启动，只负责持久化到
;;; lem-home 的 config.lisp（幂等，重复 setf 无副作用），自下一次
;;; 启动生效。ncurses 前端不读这些键，无副作用。
;;;
;;; 主字体 = Maple Mono NF CN（与 kitty 同字体；Nerd 码点齐全，修复
;;; SDL2 下 Explorer/终端图标豆腐）；CJK 槽同指 Maple（CN 版含完整
;;; 中文，两槽同字体保证自洽）。字号 26px：3072x1920 高分屏上默认
;;; 15px 过小（SDL2 的字号是物理像素，不像 kitty 走 DPI 缩放）。

(in-package :lem-user)

(defun vs-first-existing-file (&rest paths)
  "返回第一个存在的路径名字符串；全缺则 nil。"
  (some (lambda (p) (and (probe-file p) (namestring p))) paths))

(let* ((home (user-homedir-pathname))
       (regular (vs-first-existing-file
                 (merge-pathnames ".guix-home/profile/share/fonts/truetype/MapleMono-NF-CN-Regular.ttf" home)
                 (merge-pathnames ".local/share/fonts/MapleMono-NF-CN-Regular.ttf" home)))
       (bold (vs-first-existing-file
              (merge-pathnames ".guix-home/profile/share/fonts/truetype/MapleMono-NF-CN-Bold.ttf" home)
              (merge-pathnames ".local/share/fonts/MapleMono-NF-CN-Bold.ttf" home))))
  (when regular
    (setf (lem:config :sdl2-normal-font) regular
          (lem:config :sdl2-cjk-normal-font) regular))
  (when bold
    (setf (lem:config :sdl2-bold-font) bold
          (lem:config :sdl2-cjk-bold-font) bold))
  (setf (lem:config :sdl2-font-size) 26))
