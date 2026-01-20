(use-modules (cast packages gtklock)

             (jeans packages fonts)

             (px packages document)
             (px packages tpm)

             (radix packages freedesktop)

             (rde packages fonts)
             (rosenthal packages networking)
             (rosenthal packages rust-apps)

             (saayix packages binaries)
             (saayix packages fonts))

(use-package-modules admin
                     audio
                     bash
                     bootloaders
                     compression
                     containers
                     cinnamon
                     curl
                     cryptsetup
                     fcitx5
                     fonts
                     freedesktop
                     games
                     glib
                     gnome
                     gnome-xyz
                     gnupg
                     hardware
                     kde-frameworks
                     image-viewers
                     linux
                     package-management
                     password-utils
                     polkit
                     python
                     qt
                     rust-apps
                     terminals
                     text-editors
                     shellutils
                     syncthing
                     version-control
                     wget
                     wm
                     xdisorg
                     xfce
                     xorg)

(define %packages-config
  (append (list ;Desktop
                bluez
                brightnessctl
                glib
                gnome-keyring
                gsettings-desktop-schemas
                gtklock
                gvfs
                libnotify
                niri
                poweralertd
                swayidle
                swww
                waybar
                wl-clipboard
                xdg-desktop-portal
                xdg-desktop-portal-gnome
                xdg-desktop-portal-gtk
                xdg-dbus-proxy
                xdg-utils
                xdg-terminal-exec
                xwayland-satellite

                ;; Essential
                dconf-editor
                easyeffects
                exo
                file-roller
                kvantum
                libgnome-keyring
                libsecret
                mihomo
                pipewire
                polkit-gnome
                qt5ct
                qt6ct
                qtsvg
                thunar
                thunar-archive-plugin
                thunar-media-tags-plugin
                thunar-volman
                wireplumber
                xdg-user-dirs

                ;; Fonts
                font-awesome
                font-google-noto-emoji
                font-iosevka-nerd
                font-maple-font-nf-cn
                font-nerd-noto
                font-sarasa-gothic

                ;; Terminal
                bat
                btop
                distrobox
                fastfetch
                fish
                foot
                fzf
                helix
                starship

                ;; System
                bluez
                curl
                cryptsetup
                flatpak
                flatpak-xdg-utils
                git
                git-filter-repo
                git-lfs
                gzip
                nix
                ntfs-3g
                pinentry
                podman
                podman-compose
                python
                tpm2-abrmd
                tpm2-pkcs11
                tpm2-tools
                tpm2-tss
                unzip
                wget) %base-packages))
