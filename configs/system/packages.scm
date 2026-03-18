;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %packages-config
  (append (specs->pkgs+out
           ;; Core System Tools
           "cpufrequtils"
           "cryptsetup"
           "dialog"
           "iproute2"
           "iptables-nft"
           "pinentry"
           "rtkit"
           "strace"

           ;; Networking & Connectivity
           "adb"
           "bluez"
           "curl"
           "fprintd"
           "mihomo"
           "netcat-openbsd"
           "wget"

           ;; Development Tools
           "gcc-toolchain"
           "git"
           "git-filter-repo"
           "git-lfs"

           ;; Desktop Environment
           "brightnessctl"
           "dconf-editor"
           "gvfs"
           "niri"
           "poweralertd"
           "setxkbmap"
           "swayidle"
           "xdg-dbus-proxy"
           "xdg-desktop-portal-gnome"
           "xdg-desktop-portal-gtk"
           "xdg-user-dirs"
           "xdg-utils"
           "xprop"
           "xwayland-satellite"

           ;; Desktop Services
           "gnome-keyring"
           "libgnome-keyring"
           "libnotify"
           "libsecret"
           "polkit-gnome"

           ;; File Management
           "exo"
           "file-roller"
           "thunar"
           "thunar-archive-plugin"
           "thunar-media-tags-plugin"
           "thunar-volman"
           "thunar-vcs-plugin"
           "tumbler"
           "xfconf"

           ;; Multimedia
           "gstreamer"
           "gst-plugins-base"
           "gst-plugins-good"
           "gst-plugins-bad"
           "gst-plugins-ugly-full"

           ;; Fonts
           "font-awesome"
           "font-google-noto-emoji"
           "font-nerd-fonts-iosevka"
           "font-maple-font-nf-cn"
           "font-sarasa-gothic"

           ;; Terminal & Shell
           "fastfetch-minimal"
           "fish"
           "foot"

           ;; Virtualization & Containers
           "distrobox"
           "libvirt"
           "podman"
           "podman-compose"
           "qemu"
           "runc"
           "spice"

           ;; Package Management
           "flatpak"
           "flatpak-xdg-utils"
           "nix"

           ;; Utilities
           "gzip"
           "ntfs-3g"
           "tpm2-abrmd"
           "tpm2-pkcs11"
           "tpm2-tools"
           "tpm2-tss"
           "unzip"
           "zip") %base-packages))
