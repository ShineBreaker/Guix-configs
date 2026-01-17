(use-modules (gnu)
             (gnu home)
             (gnu home services)
             (gnu home services shells)
             (gnu home services desktop)
             (gnu home services dotfiles)
             (gnu home services fontutils)
             (gnu home services gnupg)
             (gnu home services shepherd)
             (gnu home services niri)
             (gnu home services sound)
             (gnu home services desktop)
             (gnu home services fontutils)
             (gnu home services syncthing)
             (gnu home services guix)

             (gnu packages)

             (gnu services)
             (gnu system shadow)

             (guix gexp)
             (guix utils)

             (jeans packages java)

             (nongnu packages game-client)
             (nongnu packages productivity)

             (px packages activitywatch)
             (px packages desktop-tools)
             (px packages editors)
             (px packages networking)
             (px packages node)
             (px packages version-control)

             (radix packages gnupg)

             (rosenthal packages games)
             (rosenthal services desktop)
             (rosenthal services shellutils)
             (rosenthal utils packages)

             (saayix packages binaries)

             (selected-guix-works packages rust-apps))

(use-package-modules emacs
                     freedesktop
                     gnupg
                     gnome
                     golang-crypto
                     guile-xyz
                     libreoffice
                     librewolf
                     linux
                     node
                     video
                     wm)
