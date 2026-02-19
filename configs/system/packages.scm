;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %packages-config
  (append (specs->pkgs+out
           ;; Desktop
           "bluez"
           "brightnessctl"
           "niri"
           "poweralertd"
           "swayidle"
           "xdg-desktop-portal-gnome"
           "xdg-desktop-portal-gtk"
           "xwayland-satellite"

           ;; File management
           "file-roller"
           "thunar"
           "thunar-archive-plugin"
           "thunar-media-tags-plugin"
           "thunar-volman"
           "thunar-vcs-plugin"
           "xfconf"

           ;; Essential
           "dconf-editor"
           "gnome-keyring"
           "gvfs"
           "libgnome-keyring"
           "libnotify"
           "libsecret"
           "mihomo"
           "pinentry-qt"
           "polkit-gnome"
           "xdg-dbus-proxy"
           "xdg-user-dirs"
           "xdg-utils"

           ;; gstreamer
           "gstreamer"
           "gst-plugins-ugly-full"
           "gst-plugins-bad"
           "gst-plugins-base"
           "gst-plugins-good"

           ;; Fonts
           "font-awesome"
           "font-google-noto-emoji"
           "font-nerd-fonts-iosevka"
           "font-maple-font-nf-cn"
           "font-sarasa-gothic"

           ;; Terminal
           "distrobox"
           "fastfetch"
           "fish"
           "foot"
           "helix"
           "just"

           ;; Virtualization & Container
           "libvirt"
           "podman"
           "podman-compose"
           "qemu"

           ;; System
           "adb"
           "bluez"
           "curl"
           "cryptsetup"
           "dialog"
           "flatpak"
           "flatpak-xdg-utils"
           "fprintd"
           "git"
           "git-filter-repo"
           "git-lfs"
           "gzip"
           "iproute2"
           "iptables-nft"
           "libnotify"
           "netcat-openbsd"
           "ntfs-3g"
           "pinentry"
           "postgresql"
           "python"
           "rtkit"
           "strace"
           "tpm2-abrmd"
           "tpm2-pkcs11"
           "tpm2-tools"
           "tpm2-tss"
           "unzip"
           "wget"
           "zip") %base-packages))
