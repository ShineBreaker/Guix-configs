;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (ice-9 match))

(define %mapped-devices-config
  (list (mapped-device
          (source (uuid "327f2e02-1e4f-48b2-87f0-797c481850c9"))
          (target "root")
          (type luks-device-mapping)
          (arguments '(#:key-file "/cryptroot.key")))))

(define %btrfs-subvolumes
  '(("SYSTEM/Guix/@boot"            "/boot")
    ("SYSTEM/Guix/@data"            "/var/lib")

    ("SYSTEM/Guix/@persist/cache/root"     "/root/.cache")
    ("SYSTEM/Guix/@persist/cache/var"      "/var/cache")
    ("SYSTEM/Guix/@persist/db"             "/var/db")
    ("SYSTEM/Guix/@persist/guix"           "/var/guix")
    ("SYSTEM/Guix/@persist/log"            "/var/log")
    ("SYSTEM/Guix/@persist/mihomo"         "/.config")
    ("SYSTEM/Guix/@persist/tmp"            "/var/tmp")

    ("SYSTEM/Guix/@etc"             "/etc")
    ("SYSTEM/Guix/@gnu"             "/gnu")
    ("DATA/Home/Guix"               "/home")
    ("DATA/Share"                   "/data")
    ("SYSTEM/NixOS/@nix"            "/nix")
    ("DATA/Flatpak"                 "/var/lib/flatpak")))

(define %file-systems-config
  (append
    (list
     (file-system
       (device (uuid "9699-52A2" 'fat))
       (mount-point "/efi")
       (type "vfat")
       (create-mount-point? #t))
     (file-system
       (mount-point "/")
       (device "tmpfs")
       (type "tmpfs")
       (options "mode=0755,nr_inodes=1m,size=25%")
       (check? #f)))
   (map (match-lambda
          ((subvol mount-point)
           (file-system
             (device (file-system-label "Linux"))
             (mount-point mount-point)
             (type "btrfs")
             (options (string-append "subvol=" subvol ",compress=zstd:6"))
             (dependencies %mapped-devices-config)
             (create-mount-point? #t)
             (check? (string=? mount-point "/gnu")))))
        %btrfs-subvolumes)
   %base-file-systems))
