;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(load "../home/services/programs/emacs.scm")
(load "../home/services/programs/fish.scm")

(define %packages-list-extended
  (cons* (specs->pkgs+out
          ;; AI related.
          "claude-code"
          "codex"

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
          "nautilus"
          "wl-clipboard"
          "xsel"

          ;; Communication
          "kdeconnect"
          "notmuch"
          "telegram-desktop"

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
          "osu-lazer-bin"
          "prismlauncher-dolly"
          "steam"

          ;; System & Utilities
          "age"
          "amule"
          "btop"
          "freerdp@3"
          "just"
          "maak"
          "postgresql"
          "tmux"
          "tmuxifier"
          "winapps"

          ;; Themes & Appearance
          "adw-gtk3-theme"
          "adwaita-icon-theme"
          "bibata-cursor-theme"
          "papirus-icon-theme"

          ;; Development
          "ccls"
          "clang"
          "gradle"
          "helix"
          "maven"
          "node"
          "openjdk@21"
          "pandoc"
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

(define %packages-list
  (append %packages-list-extended
          %emacs-packages-list
          %fish-packages-list))
