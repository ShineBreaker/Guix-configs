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
          "nomacs"
          "obs"
          "obsidian"
          "seahorse"
          "zen-browser-bin"

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
