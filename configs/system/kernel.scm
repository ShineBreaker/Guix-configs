;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (gnu packages firmware)

             (nongnu packages firmware)
             (nongnu packages linux)
             (nongnu system linux-initrd))

(define %initrd-config
  microcode-initrd)

(define %firmware-config
  (list bluez-firmware linux-firmware ovmf-x86-64 sof-firmware))

(define %kernel-config
  linux-xanmod)

(define %kernel-arguments-config
  (cons* "kernel.sysrq=1"
         "snd-intel-dspcfg.dsp_driver=3"
         "usbcore.autosuspend=120"
         "zswap.enabled=1"
         "zswap.max_pool_percent=90"
         %default-kernel-arguments))
