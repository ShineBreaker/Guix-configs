;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (rosenthal bootloader uki))

(define %bootloader-config
  (bootloader-configuration
    (bootloader uefi-uki-removable-bootloader)
    (theme (grub-theme (inherit (grub-theme))
                       (gfxmode '("1024x786x32"))))
    (targets '("/efi"))
    (extra-initrd "/SYSTEM/Guix/@boot/cryptroot.cpio")))
