;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(load "../information.scm")

(load "../system/services/base.scm")
(load "../system/services/desktop.scm")
(load "../system/services/filesystem.scm")
(load "../system/services/kernel.scm")
(load "../system/services/networking.scm")
(load "../system/services/nix.scm")
(load "../system/services/udev.scm")
(load "../system/services/virtualization.scm")

(define %services-config
  (append %base-services
          %udev-services
          %networking-services
          %virtualization-services
          %kernel-services
          %nix-services
          %filesystem-services
          %desktop-services))
