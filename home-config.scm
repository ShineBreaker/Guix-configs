(load "./configs/channel.scm")

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

(use-package-modules freedesktop
                     gnupg
                     gnome
                     java
                     libreoffice
                     librewolf
                     linux
                     node
                     video
                     wm)

(define home-config
  (home-environment
    (packages (append (specs->pkgs+out
                       ;; Desktop
                       "activitywatch"
                       "cliphist"
                       "fcitx5"
                       "fuzzel"
                       "keepassxc"
                       "mako"

                       ;; Utility
                       "git-credential-keepassxc"
                       "libreoffice"
                       "nomacs"
                       "obs"
                       "obsidian"
                       "seahorse"
                       "sniffnet"
                       "sops"
                       "zen-browser-bin"

                       ;; Entertain
                       "openjdk"
                       "prismlauncher-dolly"
                       "steam"

                       ;; Themes
                       "adwaita-icon-theme"
                       "bibata-cursor-theme"
                       "orchis-theme"
                       "papirus-icon-theme"

                       ;; Programming
                       "gh"
                       "node"
                       "pnpm"
                       "rust-analyzer"
                       "zed")))

    (services
     (append (list (service home-blueman-applet-service-type)
                   (service home-dbus-service-type)
                   (service home-fish-service-type)
                   (service home-fish-plugin-atuin-service-type)
                   (service home-fish-plugin-direnv-service-type)
                   (service home-fish-plugin-zoxide-service-type)
                   (service home-mako-service-type)
                   (service home-niri-service-type)

                   (service home-dotfiles-service-type
                            (home-dotfiles-configuration (directories '("./dotfiles"))))

                   (service home-fcitx5-service-type
                            (home-fcitx5-configuration (themes (specs->pkgs
                                                                "fcitx5-material-color-theme"))
                                                       (input-method-editors (specs->pkgs
                                                                              "fcitx5-rime"))))

                   (service home-files-service-type
                            `((".guile" ,%default-dotguile)
                              (".Xdefaults" ,%default-xdefaults)))

                   (service home-gpg-agent-service-type
                            (home-gpg-agent-configuration (pinentry-program (file-append
                                                                             pinentry-fuzzel
                                                                             "/bin/pinentry-fuzzel"))
                                                          (ssh-support? #t)))

                   (service home-pipewire-service-type
                            (home-pipewire-configuration (wireplumber
                                                          wireplumber)
                                                         (enable-pulseaudio?
                                                          #t)))

                   (service home-xdg-configuration-files-service-type
                            `(("gdb/gdbinit" ,%default-gdbinit)
                              ("nano/nanorc" ,%default-nanorc)))

                   (simple-service 'fish-greeting
                                   home-xdg-configuration-files-service-type
                                   `(("fish/conf.d/greeting.fish" ,(plain-file
                                                                    "greeting.fish"
                                                                    "set --global fish_greeting 日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。"))))

                   (simple-service 'extend-fontconfig
                                   home-fontconfig-service-type
                                   (list "~/.local/share/fonts"
                                         (let ((sans "Sarasa Gothic SC")
                                               (serif "Sarasa Gothic SC")
                                               (mono "Maple Mono NF CN")
                                               (emoji "Noto Color Emoji"))
                                           `((alias (family "sans-serif")
                                                    (prefer (family ,sans)
                                                            (family ,emoji)))
                                             (alias (family "serif")
                                                    (prefer (family ,serif)
                                                            (family ,emoji)))
                                             (alias (family "monospace")
                                                    (prefer (family ,mono)
                                                            (family ,emoji)))
                                             (alias (family "emoji")
                                                    (prefer (family ,emoji)))))))

                   (simple-service 'xdg-desktop-portal
                                   home-shepherd-service-type
                                   (list (shepherd-service (provision '(xdg-desktop-portal))
                                                           (requirement '(dbus))
                                                           (start #~(make-forkexec-constructor
                                                                     (list #$(file-append
                                                                              xdg-desktop-portal
                                                                              "/bin/xdg-desktop-portal"))
                                                                     #:log-file
                                                                     (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/xdg-desktop-portal.log")))
                                                           (respawn? #t)
                                                           (auto-start? #t))))

                   (simple-service 'xdg-desktop-portal-gtk
                                   home-shepherd-service-type
                                   (list (shepherd-service (provision '(xdg-desktop-portal-gtk))
                                                           (requirement '(xdg-desktop-portal))
                                                           (start #~(make-forkexec-constructor
                                                                     (list #$(file-append
                                                                              xdg-desktop-portal-gtk
                                                                              "/libexec/xdg-desktop-portal-gtk"))
                                                                     #:log-file
                                                                     (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/xdg-desktop-portal-gtk.log")))
                                                           (respawn? #t)
                                                           (auto-start? #t))))

                   (simple-service 'environment-variables
                                   home-environment-variables-service-type
                                   `(("EDITOR" . "hx")
                                     ("GDK_BACKEND" . "wayland")
                                     ("GUIX_PROFILE" . "$HOME/.guix-home/profile/etc/profile")
                                     ("HTTP_PROXY" . "http://127.0.0.1:7890")
                                     ("HTTPS_PROXY" . "$HTTP_PROXY")
                                     ("PATH" unquote
                                      (string-append "$HOME/.local/bin:"
                                                     (or (getenv "PATH") "")))
                                     ("QT_AUTO_SCREEN_SCALE_FACTOR" . #t)
                                     ("QT_QPA_PLATFORMTHEME" . "qt5ct")
                                     ("QT_PLUGIN_PATH" unquote
                                      (string-append
                                       "/run/current-system/profile/lib/qt5/plugins:"
                                       "/run/current-system/profile/lib/qt6/plugins:"
                                       (or (getenv "QT_PLUGIN_PATH") "")))
                                     ("_JAVA_AWT_WM_NONREPARENTING" . #t))))

             %base-home-services))))

home-config
