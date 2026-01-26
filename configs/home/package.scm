;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (jeans packages desktop)
             (jeans packages games)
             (jeans packages theme)

             (nongnu packages video)

             (px packages activitywatch)
             (px packages desktop-tools)
             (px packages editors)
             (px packages networking)
             (px packages node)
             (px packages tools)
             (px packages version-control))

(use-package-modules emacs
                     freedesktop
                     gnupg
                     gimp
                     gnome
                     golang-crypto
                     guile-xyz
                     libreoffice
                     librewolf
                     license
                     linux
                     node
                     polkit
                     shells
                     video
                     virtualization
                     wm)

(define %packages-list
  (cons* (specs->pkgs+out
          ;; Desktop
          "activitywatch"
          "cliphist"
          "fcitx5"
          "fuzzel"
          "keepassxc"
          "mako"
          "mpvpaper"
          "swww"
          "waypaper"

          ;; Utility
          "age"
          "git-credential-keepassxc"
          "libreoffice"
          "obsidian"
          "seahorse"
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
          "mangohud"
          "openjdk@25"
          ;; "prismlauncher-dolly"
          "steam"

          ;; Themes
          "adwaita-icon-theme"
          "bibata-cursor-theme"
          "papirus-icon-theme"
          "orchis-theme"
          "orchis-kvantum-themes"

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
