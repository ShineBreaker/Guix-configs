;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define username "brokenshine")

(define %data-dirs
  '(".gnupg"
    ".local/share/PrismLauncher"
    ".var/app"
    "Desktop"
    "Documents"
    "Downloads"
    "Games"
    "Music"
    "Pictures"
    "Programs"
    "Public"
    "Templates"))

(define %btrfs-subvol-data "DATA/Share")

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
    ("SYSTEM/NixOS/@nix"            "/nix")
    ("DATA/Flatpak"                 "/var/lib/flatpak")))
