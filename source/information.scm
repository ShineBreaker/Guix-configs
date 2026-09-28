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
  (let* ([input (string->utf8 username)]
         [hash (md5 input)]
         [hex-string (bytevector->base16-string hash)])
    (string-downcase hex-string)))

(define fixed-machine-id (generate-machine-id username))

(define %data-dirs
  '(;; --- dotfile 持久化（tmpfs /home 启动后自动 bind-mount）---
    ".local/share/containers"
    ".local/share/gnupg"
    ".local/share/keyrings"
    ".local/share/fish"
    ".local/share/atuin"
    ".local/share/direnv"
    ".local/share/hermes"
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

;; --- 磁盘拓扑（分区 UUID / 解锁名 / 挂载参数）---
;; 本段是全仓库分区标识的单一真源：config.org 引用这些变量，
;; tools/rescue-chroot.sh 在 live 环境用 sed/grep 做受限文本解析（那里
;; 没有 guile），因此保持一行一个 (define %var "...") 的顶格格式。换机
;; 时只改本段。
(define %luks-uuid "327f2e02-1e4f-48b2-87f0-797c481850c9") ; LUKS2 分区（本机: /dev/nvme0n1p2）
(define %luks-mapper "root") ; 解锁名，解锁后 Btrfs 位于 /dev/mapper/<解锁名>
(define %esp-uuid "9699-52A2") ; ESP vfat 短 UUID（本机: /dev/nvme0n1p1）
(define %swap-uuid "169557cc-00a4-448c-9bb6-7bd80fc2b023") ; 明文 swap，休眠镜像所在（禁 mkswap/格式化）
(define %btrfs-label "Linux") ; LUKS 内 Btrfs 卷标
(define %btrfs-mount-opts "compress=zstd:3") ; 与系统日常挂载一致的 Btrfs 选项
(define %repo-in-data "/data/Projects/Config/Guix-configs") ; 配置仓库物理路径（Projects 在 %data-dirs）

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
    ("SYSTEM/Guix/@persist/tmp"            "/var/tmp")
    ("SYSTEM/Guix/@tmp"                     "/tmp")

    ("SYSTEM/Guix/@etc/guix"               "/etc/guix")
    ("SYSTEM/Guix/@etc/libvirt"            "/etc/libvirt")
    ("SYSTEM/Guix/@etc/NetworkManager"     "/etc/NetworkManager")
    ("SYSTEM/Guix/@etc/ssh"                "/etc/ssh")

    ("DATA/Flatpak"                        "/var/lib/flatpak")
    ("DATA/Home/Guix"                      "/home")
    ("DATA/LibVirt"                        "/var/lib/libvirt")))
