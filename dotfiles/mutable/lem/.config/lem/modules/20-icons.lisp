;;; modules/20-icons.lisp — Nerd Font 图标（codicon 集）
;;;
;;; 依赖：utils（vs$）；被 explorer（树/图标行）/ editor-config（分支图标）依赖。
;;;
;;; 终端字体 Maple Mono NF CN；码点已经 fontTools cmap 逐一验证在册
;;; （cod-git_branch U+EC6F 本字体未收录），PUA 区单宽字形 wcwidth=1，
;;; 无双宽陷阱。
;;; 注意：U+E000–E0FF 落在 lem *char-replacement* 替换表内（渲染成 \数字
;;; 文本），选码点必须避开该段——经典 git-branch 码点 U+E0A0 恰落该段
;;; 不可用，branch 因此用 U+F418。

(in-package :lem-user)

(defparameter *vs-icons*
  '((:files . #xEAF0) (:search . #xEA6D) (:scm . #xEA68) (:debug . #xEB91)
    (:extensions . #xEAE6) (:account . #xEB99) (:gear . #xEAF8)
    (:chevron-right . #xEAB6) (:chevron-down . #xEAB4)
    (:folder . #xEA83) (:folder-opened . #xEAF7)
    (:file . #xEA7B) (:file-code . #xEAE9)
    (:branch . #xF418) (:error . #xEA87) (:warning . #xEA6C)
    (:sync . #xEA77) (:ellipsis . #xEA7C) (:refresh . #xEB37)))

(defun vs-icon (name)
  (let ((code (cdr (assoc name *vs-icons*))))
    (if code (code-char code) #\Space)))

;; 同步注册进 lem icon 系统（icon-string "vscode-folder" 等可查）
(let ((reg (or (vs$ :lem "REGISTER-ICON")
               (vs$ :lem/common/character/icon "REGISTER-ICON"))))
  (when reg
    (dolist (i *vs-icons*)
      (funcall reg (format nil "vscode-~A" (string (car i))) (cdr i)))))
