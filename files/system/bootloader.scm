;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (rosenthal bootloader limine))

(define %bootloader-config
  (bootloader-configuration
    (bootloader limine-efi-removable-bootloader)
    (targets '("/boot"))))
