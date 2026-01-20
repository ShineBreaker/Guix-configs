(use-package-modules emacs
                     freedesktop
                     gnupg
                     gimp
                     gnome
                     golang-crypto
                     guile-xyz
                     libreoffice
                     librewolf
                     linux
                     node
                     video
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

          ;; Utility
          "age"
          "git-credential-keepassxc"
          "libreoffice"
          "obsidian"
          "seahorse"
          "zen-browser-bin"

          ;; Graphic
          "gimp"
          "nomacs"
          "obs-with-cef"
          "obs-pipewire-audio-capture"
          "obs-vkcapture"

          ;; Entertain
          "openjdk@25"
          "prismlauncher-dolly"
          "steam"

          ;; Themes
          "adwaita-icon-theme"
          "bibata-cursor-theme"
          "orchis-theme"
          "papirus-icon-theme"

          ;; Programming
          "emacs-pgtk"
          "guile-studio"
          "node"
          "pnpm"
          "rust-analyzer"
          "zed")))
