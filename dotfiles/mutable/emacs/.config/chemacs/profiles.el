;;; .config/chemacs/profiles.el --- chemacs2 profile 表 -*- emacs-lisp -*-
;;
;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT
;;
;; chemacs2 引导层（~/.config/emacs/{init,early-init,chemacs}.el）启动时读这个文件，
;; 按 profile 名查到 user-emacs-directory，把控制权交给该配置树的 init.el。
;;
;; profile 字段说明：
;;   user-emacs-directory  必填，配置树根（chemacs 会把 user-emacs-directory 设成它）
;;   server-name           选填，daemon socket 名（多 daemon 共存时用 emacsclient -s <name>）
;;   env                   选填，启动时 setenv 的环境变量 alist
;;
;; 注意：本文件改完后必须 `blue stow --restow emacs' 才生效（链接到 ~/.config/chemacs/）。

(("general" . ((user-emacs-directory . "~/.config/emacs/general-config")))
 ("literal" . ((user-emacs-directory . "~/.config/emacs/literal-config"))))
