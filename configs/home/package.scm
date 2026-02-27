;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %packages-list
  (cons* (specs->pkgs+out
          ;; Desktop
          "baobab"
          "cliphist"
          "dex"
          "fcitx5"
          "fuzzel"
          "helvum"
          "keepassxc"
          "mpvpaper"
          "pavucontrol"
          "swww"
          "waypaper"
          "wl-clipboard"

          ;; Utility
          "age"
          "amule"
          "btop"
          "freerdp"
          "git-credential-keepassxc"
          "kdeconnect"
          "libreoffice"
          "seahorse"
          "tailscale"
          "telegram-desktop"
          "virt-manager"
          "zen-browser-bin"

          ;; Graphic
          "gimp"
          "mpv"
          "nomacs"
          "obs-with-cef"
          "obs-pipewire-audio-capture"
          "obs-vkcapture"

          ;; Entertain
          "heroic"
          "mangohud"
          "osu-lazer-tachyon-bin"
          "prismlauncher-dolly"
          "steam"

          ;; Themes
          "adw-gtk3-theme"
          "adwaita-icon-theme"
          "bibata-cursor-theme"
          "papirus-icon-theme"

          ;; Programming
          "ccls"
          "clang"
          "emacs-pgtk"
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

          ;; QT Related
          "qt5ct"
          "qt6ct"
          "qtmultimedia"
          "qtsvg")))
