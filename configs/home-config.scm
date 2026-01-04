(load "./channel.scm")

(use-modules (gnu home)
             (gnu home services)
             (gnu home services shells)
             (gnu home services dotfiles)
             (gnu home services shepherd)
             (gnu home services niri)
             (gnu home services sound)
             (gnu home services desktop)
             (gnu home services fontutils)
             (gnu home services syncthing)
             (gnu home services guix)

             (gnu packages linux)
             (gnu packages wm)

             (gnu services)
             (gnu system shadow)

             (guix gexp)

             (rosenthal packages games)
             (rosenthal services desktop)
             (rosenthal utils packages))

(define home-envs
  (home-environment
    (packages (specifications->packages (list "cliphist"
                                              "fcitx5"
                                              "fuzzel"
                                              "keepassxc"
                                              "mako"
                                              "nomacs"
                                              "prismlauncher-dolly"
                                              "swww"
                                              "waybar"
                                              "zen-browser-bin")))
    (services
     (append (list (service home-dotfiles-service-type
                            (home-dotfiles-configuration (directories '("../dotfiles"))))

                   (service home-syncthing-service-type)

                   (service home-dbus-service-type)
                   (service home-blueman-applet-service-type)

                   (service home-fcitx5-service-type
                            (home-fcitx5-configuration (themes (specs->pkgs
                                                                "fcitx5-material-color-theme"))
                                                       (input-method-editors (specs->pkgs
                                                                              "fcitx5-rime"))))

                   (service home-pipewire-service-type
                            (home-pipewire-configuration (wireplumber
                                                          wireplumber)
                                                         (enable-pulseaudio?
                                                          #t)))

                   (service home-fish-service-type)

                   (service home-files-service-type
                            `((".guile" ,%default-dotguile)
                              (".Xdefaults" ,%default-xdefaults)))

                   (service home-xdg-configuration-files-service-type
                            `(("gdb/gdbinit" ,%default-gdbinit)
                              ("nano/nanorc" ,%default-nanorc)))

                   (service home-niri-service-type)

                   (simple-service 'variant-packages-service
                                   home-channels-service-type guix-channels)

                   (simple-service 'extend-fontconfig
                                   home-fontconfig-service-type
                                   (let ((sans "Sarasa Gothic SC")
                                         (serif "Sarasa Gothic SC")
                                         (mono "FiraCode Nerd Font")
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
                                                      (family "Sarasa Mono SC"
                                                       "FiraCode Nerd Font")
                                                      (family ,emoji)))
                                       (alias (family "ui-serif")
                                              (prefer (family ,serif)
                                                      (family "serif")))
                                       (alias (family "ui-monospace")
                                              (prefer (family ,mono)
                                                      (family "monospace"))))))

                   (simple-service 'environment-variables
                                   home-environment-variables-service-type
                                   `(("EDITOR" . "hx")
                                     ("GDK_BACKEND" . "wayland")
                                     ("MOZ_ENABLE_WAYLAND" . #t)
                                     ("QT_AUTO_SCREEN_SCALE_FACTOR" . #t)
                                     ("QT_QPA_PLATFORMTHEME" . "qt5ct")
                                     ("_JAVA_AWT_WM_NONREPARENTING" . #t))))

             %base-home-services))))
