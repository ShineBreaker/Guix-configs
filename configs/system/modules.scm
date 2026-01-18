(use-modules (gnu)
             (gnu home services guix)
             (gnu system nss)
             (gnu system accounts)

             (guix channels)

             (nonguix transformations)
             (nongnu packages firmware)
             (nongnu packages linux)
             (nongnu system linux-initrd)

             (cast packages gtklock)

             (jeans packages fonts)

             (px packages document)
             (px packages tpm)

             (radix packages freedesktop)

             (rde packages fonts)

             (rosenthal)
             (rosenthal bootloader grub)
             (rosenthal packages networking)
             (rosenthal packages rust-apps)

             (saayix packages binaries)
             (saayix packages fonts))

(use-service-modules authentication
                     containers
                     dbus
                     linux
                     networking
                     pm
                     sddm
                     syncthing
                     sysctl
                     xorg)

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
                     shells
                     shellutils
                     syncthing
                     version-control
                     wget
                     wm
                     xdisorg
                     xfce
                     xorg)
