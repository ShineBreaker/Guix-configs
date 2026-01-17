(define %desktop-services
  (list (service home-fish-service-type)
        (service home-fish-plugin-atuin-service-type)
        (service home-fish-plugin-direnv-service-type)
        (service home-fish-plugin-zoxide-service-type)
        (service home-mako-service-type)
        (service home-niri-service-type)
        (service home-syncthing-service-type)
        (service home-waybar-service-type)
        (service home-fcitx5-service-type
                 (home-fcitx5-configuration (themes (specs->pkgs
                                                     "fcitx5-material-color-theme"))
                                            (input-method-editors (specs->pkgs
                                                                   "fcitx5-rime"))))

        (service home-gpg-agent-service-type
                 (home-gpg-agent-configuration (pinentry-program (file-append
                                                                  pinentry-fuzzel
                                                                  "/bin/pinentry-fuzzel"))
                                               (ssh-support? #t)))
        (simple-service 'xdg-desktop-portal home-shepherd-service-type
                        (list (shepherd-service (provision '(xdg-desktop-portal))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   xdg-desktop-portal
                                                                   "/bin/xdg-desktop-portal"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/xdg-desktop-portal.log")))
                                                (respawn? #t))))

        (simple-service 'xdg-desktop-portal-gtk home-shepherd-service-type
                        (list (shepherd-service (provision '(xdg-desktop-portal-gtk))
                                                (requirement '(xdg-desktop-portal))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   xdg-desktop-portal-gtk
                                                                   "/libexec/xdg-desktop-portal-gtk"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/xdg-desktop-portal-gtk.log")))
                                                (respawn? #t))))))
