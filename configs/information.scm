;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (guix channels)
             (guix gexp))

(define username "brokenshine")

(define guix-channels
  (include "./channel.lock"))

(define %data-dirs
  '(".gnupg"
    ".var"

    "Desktop"
    "Documents"
    "Downloads"
    "Games"
    "Music"
    "Pictures"
    "Programs"
    "Public"
    "Templates"
    "Videos"))

(define %btrfs-subvol-data "DATA/Share")

(define %btrfs-subvolumes
  '(("SYSTEM/Guix/@boot"                   "/boot")
    ("SYSTEM/Guix/@data"                   "/var/lib")
    ("SYSTEM/Guix/@gnu"                    "/gnu")

    ("SYSTEM/Guix/@persist/cache/root"     "/root/.cache")
    ("SYSTEM/Guix/@persist/cache/var"      "/var/cache")
    ("SYSTEM/Guix/@persist/db"             "/var/db")
    ("SYSTEM/Guix/@persist/guix"           "/var/guix")
    ("SYSTEM/Guix/@persist/log"            "/var/log")
    ("SYSTEM/Guix/@persist/mihomo"         "/.config")
    ("SYSTEM/Guix/@persist/tmp"            "/var/tmp")

    ("SYSTEM/Guix/@etc/guix"               "/etc/guix")
    ("SYSTEM/Guix/@etc/ipsec.secrets"      "/etc/ipsec.secrets")
    ("SYSTEM/Guix/@etc/libvirt"            "/etc/libvirt")
    ("SYSTEM/Guix/@etc/NetworkManager"     "/etc/NetworkManager")

    ("DATA/Flatpak"                        "/var/lib/flatpak")
    ("DATA/Home/Guix"                      "/home")

    ("SYSTEM/NixOS/@nix"                   "/nix")))

(define %tmpfs-list
  '(("/"     "mode=0755,nr_inodes=1m,size=10%")
    ("/tmp"  "mode=1777,nr_inodes=1m,size=75%")))
