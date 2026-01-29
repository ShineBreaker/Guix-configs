;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(load "../information.scm")

(use-modules (ice-9 match))

(define %mapped-devices-config
  (list (mapped-device
          (source (uuid "327f2e02-1e4f-48b2-87f0-797c481850c9"))
          (target "root")
          (type luks-device-mapping)
          (arguments '(#:key-file "/cryptroot.key")))))

(define %tmpfs-on-root
  (file-system
    (mount-point "/")
    (device "tmpfs")
    (type "tmpfs")
    (options "mode=0755,nr_inodes=1m,size=25%")
    (check? #f)))

(define %persist-filesystem
  (map (match-lambda
         ((subvol mount-point)
          (file-system
            (device (file-system-label "Linux"))
            (mount-point mount-point)
            (type "btrfs")
            (dependencies %mapped-devices-config)
            (options (string-append "subvol=" subvol ",compress=zstd:6"))
            (create-mount-point? #t)
            (needed-for-boot?
             (member mount-point '("/gnu" "/var/guix")))
            (check? (string=? mount-point "/gnu")))))
       %btrfs-subvolumes))

(define %data-filesystem
  (file-system
    (device (file-system-label "Linux"))
    (mount-point "/data")
    (type "btrfs")
    (dependencies %mapped-devices-config)
    (options (string-append "subvol=" %btrfs-subvol-data ",compress=zstd:6"))
    (create-mount-point? #t)))

(define %bind-mounts
  (map (lambda (dirs)
           (file-system
             (mount-point (string-append "/home/" username "/" dirs))
             (device (string-append "/data/" dirs))
             (type "none")
             (flags '(bind-mount))
             (dependencies (list %data-filesystem))
             (create-mount-point? #t)))
  %data-dirs))

(define %file-systems-config
  (append
    %persist-filesystem
    %bind-mounts
    (list
     %tmpfs-on-root
     %data-filesystem
     (file-system
       (device (uuid "9699-52A2" 'fat))
       (mount-point "/efi")
       (type "vfat")
       (create-mount-point? #t)))
   %base-file-systems))
