;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %packages-list
  (cons* (specs->pkgs+out
          ;; Audio & Video
          "easyeffects"
          "helvum"
          "mpv"
          "nomacs"
          "obs-with-cef"
          "obs-pipewire-audio-capture"
          "obs-vkcapture"

          ;; Desktop Environment
          "baobab"
          "cliphist"
          "dex"
          "fcitx5"
          "fuzzel"
          "wl-clipboard"
          "xclip"

          ;; Communication
          "kdeconnect"
          "telegram-desktop"
          "tailscale"

          ;; Productivity
          "gimp"
          "keepassxc"
          "git-credential-keepassxc"
          "libreoffice"
          "seahorse"
          "virt-manager"
          "zen-browser-bin"

          ;; Entertainment
          "heroic"
          "mangohud"
          "osu-lazer-tachyon-bin"
          "prismlauncher-dolly"
          "steam"

          ;; System & Utilities
          "age"
          "amule"
          "btop"
          "freerdp@3"
          "winapps"

          ;; Themes & Appearance
          "adw-gtk3-theme"
          "adwaita-icon-theme"
          "bibata-cursor-theme"
          "papirus-icon-theme"

          ;; Development
          "ccls"
          "clang"
          "emacs-pgtk"
          "helix"
          "maven"
          "node"
          "openjdk@21"
          "package-version-server"
          "python-black"
          "python-jsbeautifier"
          "python-lsp-black"
          "python-lsp-server"
          "python-pylsp-mypy"
          "reuse"
          "rust-analyzer"
          "zed"

          ;; Qt Framework
          "qt5ct"
          "qt6ct"
          "qtmultimedia"
          "qtsvg")))
