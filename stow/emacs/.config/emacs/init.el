;;; init.el --- chemacs2 引导层入口 -*- lexical-binding: t; -*-
;;
;; SPDX-FileCopyrightText: 2021 Arne Brasseur <arne@arnebrasseur.net>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; 来源：https://github.com/plexus/chemacs2
;; commit: c2d700b784c793cc82131ef86323801b8d6e67bb (master)
;;
;; 本文件是 Emacs 启动的真正入口，chemacs2 bootloader。
;; 它读取 ~/.config/chemacs/profiles.el + ~/.config/chemacs/profile，
;; 选定 profile 后把 user-emacs-directory 指向对应配置树并加载其 init.el。
;;
;; 当前 profile 布局（见 stow/emacs/.config/chemacs/profiles.el）：
;;   general  -> ~/.config/emacs/general-config/  （旧 submodule 配置，默认）
;;   literal  -> ~/.config/emacs/literal-config/  （新 org literate 配置，待写）
;;
;; 切换默认 profile：改 stow/emacs/.config/chemacs/profile -> blue stow --restow emacs
;; 临时试某 profile：emacs --with-profile literal

(require 'chemacs
         (expand-file-name "chemacs.el"
                           (file-name-directory
                            (file-truename load-file-name))))
(chemacs-load-user-init)
