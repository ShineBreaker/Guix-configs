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
          "xsel"

          ;; Communication
          "kdeconnect"
          "telegram-desktop"
          "tailscale"

          ;; Productivity
          "gimp"
          "keepassxc"
          "git-credential-keepassxc"
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
          "opentabletdriver-bin"
          "winapps"

          ;; Themes & Appearance
          "adw-gtk3-theme"
          "adwaita-icon-theme"
          "bibata-cursor-theme"
          "papirus-icon-theme"

          ;; Development
          "ccls"
          "clang"
          "codex"
          "gradle"
          "helix"
          "maven"
          "node"
          "openjdk@21"
          "package-version-server"
          "pnpm@10"
          "python-black"
          "python-jsbeautifier"
          "python-lsp-black"
          "python-lsp-server"
          "python-pylsp-mypy"
          "reuse"
          "rust-analyzer"
          "sdkmanager"
          "uv"
          "zed"

          ;; Qt Framework
          "pinentry-qt"
          "qt5ct"
          "qt6ct")))
