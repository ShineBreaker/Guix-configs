(load "./configs/channel.scm")

(use-modules (gnu)
             (gnu home)
             (gnu home services)
             (gnu home services shells)
             (gnu home services desktop)
             (gnu home services dotfiles)
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

             (nongnu packages game-client)

             (rosenthal packages games)
             (rosenthal services desktop)
             (rosenthal utils packages))

(use-package-modules freedesktop
                     gnupg
                     java
                     libreoffice
                     librewolf
                     linux
                     wm)

(define home-config
  (home-environment
    (packages (specifications->packages (list 
                                         "cliphist"
                                         "fcitx5"
                                         "fuzzel"
                                         "keepassxc"
                                         "libreoffice"
                                         "mako"
                                         "nomacs"
                                         "openjdk"
                                         "prismlauncher-dolly"
                                         "steam"
                                         "swww"
                                         "waybar"
                                         "zen-browser-bin"

                                         "librewolf"
                                         "adaptive-tab-bar-colour-icecat"
                                         "browserpass-native"
                                         "keepassxc-browser-icecat"
                                         "privacy-redirect-icecat"
                                         "ublock-origin-icecat")))
    (services
     (append (list (service home-dotfiles-service-type
                            (home-dotfiles-configuration (directories '("./dotfiles"))))

                   (service home-syncthing-service-type)
                   (service home-mako-service-type)
                   (service home-dbus-service-type)

                   (service home-blueman-applet-service-type)

                   (service home-fcitx5-service-type
                            (home-fcitx5-configuration (themes (specs->pkgs
                                                                "fcitx5-material-color-theme"))
                                                       (input-method-editors (specs->pkgs
                                                                              "fcitx5-rime"))))
                   (service home-gpg-agent-service-type
                            (home-gpg-agent-configuration (pinentry-program (file-append
                                                                             pinentry-tty
                                                                             "/bin/pinentry-tty"))
                                                          (ssh-support? #t)))

                   (service home-pipewire-service-type
                            (home-pipewire-configuration (wireplumber
                                                          wireplumber)
                                                         (enable-pulseaudio?
                                                          #t)))

                   (service home-fish-service-type)
  
                   (simple-service 'fish-greeting
                                   home-xdg-configuration-files-service-type
                                   `(("fish/conf.d/greeting.fish" ,(plain-file
                                                                    "greeting.fish"
                                                                    "set --global fish_greeting 日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。"))))

                   (service home-files-service-type
                            `((".guile" ,%default-dotguile)
                              (".Xdefaults" ,%default-xdefaults)))

                   (service home-xdg-configuration-files-service-type
                            `(("gdb/gdbinit" ,%default-gdbinit)
                              ("nano/nanorc" ,%default-nanorc)))

                   (service home-niri-service-type)

                   (simple-service 'extend-fontconfig
                                   home-fontconfig-service-type
                                   (let ((sans "Sarasa Gothic SC")
                                         (serif "Sarasa Gothic SC")
                                         (mono "Iosevka Nerd Font Mono")
                                         (emoji "Noto Color Emoji"))
                                     `((alias (family "sans-serif")
                                              (prefer (family ,sans)
                                                      (family
                                                       "Sarasa Gothic SC")
                                                      (family ,emoji)))
                                       (alias (family "serif")
                                              (prefer (family ,serif)
                                                      (family
                                                       "Sarasa Gothic SC")
                                                      (family ,emoji)))
                                       (alias (family "monospace")
                                              (prefer (family ,mono)
                                                      (family
                                                       "Iosevka Nerd Font Mono"
                                                       "Sarasa Mono SC")
                                                      (family ,emoji)))
                                       (alias (family "emoji")
                                              (prefer (family ,emoji)
                                                      (family
                                                       "Noto Color Emoji"
                                                       "FontAwesome"))))))

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

                   ;; GTK 后端
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
