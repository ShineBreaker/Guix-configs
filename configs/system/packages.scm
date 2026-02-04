;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %packages-config
  (append (specs->pkgs+out
           ;; Desktop
           "bluez"
           "brightnessctl"
           "gnome-keyring"
           "gvfs"
           "libnotify"
           "niri"
           "poweralertd"
           "swayidle"
           "waybar"
           "xdg-desktop-portal-gnome"
           "xdg-desktop-portal-gtk"
           "xdg-dbus-proxy"
           "xdg-utils"
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
           "libgnome-keyring"
           "libsecret"
           "mihomo"
           "polkit-gnome"
           "qt5ct"
           "qt6ct"
           "qtsvg"
           "xdg-user-dirs"

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
           "alsa-utils"
           "bluez"
           "curl"
           "cryptsetup"
           "flatpak"
           "flatpak-xdg-utils"
           "git"
           "git-filter-repo"
           "git-lfs"
           "gzip"
           "nix"
           "ntfs-3g"
           "pinentry"
           "postgresql"
           "python"
           ;; "rtkit"
           "strace"
           "tpm2-abrmd"
           "tpm2-pkcs11"
           "tpm2-tools"
           "tpm2-tss"
           "unzip"
           "wget"
           "zip") %base-packages))
