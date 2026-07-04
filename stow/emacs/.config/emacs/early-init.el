;;; early-init.el --- chemacs2 引导层 early-init -*- lexical-binding: t; -*-
;;
;; SPDX-FileCopyrightText: 2021 Arne Brasseur <arne@arnebrasseur.net>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; 来源：https://github.com/plexus/chemacs2
;; commit: c2d700b784c793cc82131ef86323801b8d6e67bb (master)
;;
;; 在选定 profile（设置 user-emacs-directory）后，加载该 profile 配置树下的 early-init.el。

(require 'chemacs
         (expand-file-name "chemacs.el"
                           (file-name-directory
                            (file-truename load-file-name))))
(chemacs-load-user-early-init)
