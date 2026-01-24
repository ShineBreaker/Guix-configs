(use-modules (cast packages gtklock)

             (jeans packages fonts)
             (jeans packages linux)

             (px packages document)
             (px packages gstreamer)
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
                     gstreamer
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
                     virtualization
                     wget
                     wm
                     xdisorg
                     xfce
                     xorg)

(define %packages-config
  (append (list ;Desktop
                bluez
                brightnessctl
                gnome-keyring
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

                ;; File management
                file-roller
                thunar
                thunar-archive-plugin
                thunar-media-tags-plugin
                thunar-volman
                thunar-vcs-plugin
                xfconf

                ;; Essential
                dconf-editor
                easyeffects
                kvantum
                libgnome-keyring
                libsecret
                mihomo
                pipewire
                polkit-gnome
                qt5ct
                qt6ct
                qtsvg
                wireplumber
                xdg-user-dirs

                ;; gstreamer
                gstreamer
                gst-plugins-ugly-full
                gst-plugins-bad
                gst-plugins-base
                gst-plugins-good

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

                ;;Virtualization & Container
                libvirt
                podman
                podman-compose
                qemu

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
                python
                rtkit
                tpm2-abrmd
                tpm2-pkcs11
                tpm2-tools
                tpm2-tss
                unzip
                wget) %base-packages))
