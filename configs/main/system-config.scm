;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(load "../information.scm")

(load "../system/modules.scm")
(load "../system/kernel.scm")
(load "../system/users.scm")
(load "../system/bootloader.scm")
(load "../system/filesystems.scm")
(load "../system/packages.scm")
(load "../system/services.scm")

(operating-system
  (initrd %initrd-config)
  (firmware %firmware-config)
  (kernel %kernel-config)
  (kernel-arguments %kernel-arguments-config)

  (timezone %timezone-config)
  (locale %locale-config)
  (host-name %host-name-config)

  (users %users-config)

  (bootloader %bootloader-config)

  (mapped-devices %mapped-devices-config)
  (file-systems %file-systems-config)

  (packages %packages-config)

  (services %services-config)

  (name-service-switch %mdns-host-lookup-nss))
