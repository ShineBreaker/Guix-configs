;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %packages-list
  (cons* (specs->pkgs+out
          ;; Desktop
          "baobab"
          "cliphist"
          "cursor"
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
          "btop"
          "git-credential-keepassxc"
          "kdeconnect"
          "libreoffice"
          "obsidian"
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
          "openjdk@25"
          "osu-lazer-tachyon-bin"
          "prismlauncher-dolly"
          "steam"

          ;; Themes
          "adw-gtk3-theme"
          "adwaita-icon-theme"
          "bibata-cursor-theme"
          "papirus-icon-theme"

          ;; Programming
          "emacs-pgtk"
          "node"
          "pandoc"
          "pnpm"
          "reuse"
          "rust-analyzer"
          "shellcheck"
          "vscode"
          "zed")))
