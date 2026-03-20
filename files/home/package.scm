;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (guix build-system trivial)
             (guix gexp)
             ((guix licenses) #:prefix license:)
             (guix packages))

(use-package-modules bash)

(load "../home/services/programs/emacs.scm")
(load "../home/services/programs/fish.scm")

(define termide
  (package
    (name "termide")
    (version "0.1.0")
    (source (local-file "../configs/files/termide"))
    (build-system trivial-build-system)
    (arguments
     (list #:modules '((guix build utils))
           #:builder
           #~(begin
               (use-modules (guix build utils))
               (let* ((out (assoc-ref %outputs "out"))
                      (bin (string-append out "/bin"))
                      (target (string-append bin "/termide")))
                 (mkdir-p bin)
                 (copy-file #$source target)
                 (patch-shebang target (list (string-append #$bash-minimal "/bin")))
                 (chmod target #o555)))))
    (inputs (list bash-minimal))
    (synopsis "VSCode-like tmux workspace helper")
    (description
     "termide launches and controls the tmuxifier-based terminal IDE session.")
    (home-page "https://github.com/BrokenShine/Guix-configs")
    (license license:gpl3)))

(define %packages-list-extended
  (cons* termide
         (specs->pkgs+out
          ;; AI related.
          "claude-code"
          "codex"
          "opencode"

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
          "broot"
          "btop"
          "freerdp@3"
          "just"
          "maak"
          "postgresql"
          "tmux"
          "tmuxifier"
          "tmux-xpanes"
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
          "openjdk@25"
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
