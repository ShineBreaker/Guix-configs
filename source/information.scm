;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

(use-modules (bytestructures guile bytevectors)
             (gcrypt base16)
             (gcrypt hash)
             (guix channels)
             (guix gexp))

(define username "brokenshine")

(define guix-channels
  (include "./channel.lock"))

(define (generate-machine-id username)
  (let* ((input (string->utf8 username))
         (hash (md5 input))
         (hex-string (bytevector->base16-string hash)))
    (string-downcase hex-string)))

(define fixed-machine-id (generate-machine-id username))

(define %data-dirs
  '(;; --- dotfile 持久化（tmpfs /home 启动后自动 bind-mount）---
    ".local/share/gnupg"
    ".local/share/keyrings"
    ".local/share/fish"
    ".local/share/atuin"
    ".local/share/direnv"
    ".local/share/nix"
    ".local/share/flatpak"
    ".local/share/osu"
    ".local/share/PrismLauncher"
    ".local/share/Sandbox"
    ".local/state"
    ".ssh"
    ".config/dconf"
    ".config/Element"
    ".config/QQ"

    ;; --- XDG 目录 ---
    "Desktop"
    "Documents"
    "Downloads"
    "Games"
    "Music"
    "Pictures"
    "Programs"
    "Projects"
    "Public"
    "Templates"
    "Videos"))

(define %btrfs-subvol-data "DATA/Share")

(define %btrfs-subvolumes
  '(("SYSTEM/Guix/@boot"                   "/boot")
    ("SYSTEM/Guix/@data"                   "/var/lib")
    ("SYSTEM/Guix/@gnu"                    "/gnu")
    ("SYSTEM/Guix/@nix"                    "/nix")

    ("SYSTEM/Guix/@persist/cache/root"     "/root/.cache")
    ("SYSTEM/Guix/@persist/cache/var"      "/var/cache")
    ("SYSTEM/Guix/@persist/db"             "/var/db")
    ("SYSTEM/Guix/@persist/guix"           "/var/guix")
    ("SYSTEM/Guix/@persist/log"            "/var/log")
    ("SYSTEM/Guix/@persist/mihomo"         "/.config")
    ("SYSTEM/Guix/@persist/tmp"             "/var/tmp")

    ("SYSTEM/Guix/@etc/guix"               "/etc/guix")
    ("SYSTEM/Guix/@etc/ipsec.secrets"      "/etc/ipsec.secrets")
    ("SYSTEM/Guix/@etc/libvirt"            "/etc/libvirt")
    ("SYSTEM/Guix/@etc/NetworkManager"     "/etc/NetworkManager")

    ("DATA/Flatpak"                        "/var/lib/flatpak")
    ("DATA/Home/Guix"                      "/home")
    ("DATA/LibVirt"                        "/var/lib/libvirt")))
