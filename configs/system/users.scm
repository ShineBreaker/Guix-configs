;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (gnu packages shells))

(define %timezone-config
  "Asia/Shanghai")
(define %locale-config
  "zh_CN.utf8")
(define %host-name-config
  "BrokenShine-Desktop")
(define %users-config
  (cons* (user-account
           (inherit %root-account)
           (password #f)
           (shell (file-append (spec->pkg "fish") "/bin/fish")))
         (user-account
           (name username)
           (group "users")
           (password
            "$6$C2H4Td9gJHEa4qFi$fN.tnh2XibU1aqHpwcq.zewxyMeHR83EyP0r8UROzjj6l88VijpOogCbVarmrlCnig8k967wT7ifcJAZunZ.l.")
           (supplementary-groups '("audio"
                                   "cgroup"
                                   "kvm"
                                   "libvirt"
                                   "netdev"
                                   "video"
                                   "wheel"))
           (shell (file-append (spec->pkg "fish") "/bin/fish"))) %base-user-accounts))
