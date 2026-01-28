;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (gnu packages firmware)

             (nongnu packages firmware)
             (nongnu packages linux)
             (nongnu system linux-initrd))

(define %initrd-config
  microcode-initrd)
(define %firmware-config
  (list linux-firmware sof-firmware bluez-firmware ovmf-x86-64))
(define %kernel-config
  linux-xanmod)
(define %kernel-arguments-config
  (cons* "kernel.sysrq=1" "zswap.enabled=1" "zswap.max_pool_percent=90"
         "modprobe.blacklist=amdgpu,pcspkr,hid_nintendo"
         "snd-intel-dspcfg.dsp_driver=3"
         %default-kernel-arguments))
