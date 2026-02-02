;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (gnu home services desktop)
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

             (rosenthal services desktop))

(use-package-modules freedesktop
                     gnupg
                     kde-internet
                     linux
                     polkit
                     wm)

(define %desktop-services
  (list (service home-mako-service-type)
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

        (service home-niri-service-type
                 (home-niri-configuration (config (computed-substitution-with-inputs
                                                   "niri.kdl"
                                                   (local-file
                                                    "../configs/files/config.kdl")
                                                   (specs->pkgs
                                                    "brightnessctl"
                                                    "cliphist"
                                                    "dex"
                                                    "foot"
                                                    "fish"
                                                    "fuzzel"
                                                    "gtklock"
                                                    "niri"
                                                    "waypaper"
                                                    "wl-clipboard"
                                                    "xwayland-satellite")))))

        (simple-service 'essential-desktop-services home-shepherd-service-type
                        (list (shepherd-service (provision '(kdeconnectd))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   kdeconnect
                                                                   "/bin/kdeconnectd"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/kdeconnectd.log")))
                                                (respawn? #t))

                              (shepherd-service (provision '(polkit-gnome))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   polkit-gnome
                                                                   "/libexec/polkit-gnome-authentication-agent-1"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/polkit-gnome.log")))
                                                (respawn? #t))

                              (shepherd-service (provision '(poweralertd))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   poweralertd
                                                                   "/bin/poweralertd"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/poweralertd.log")))
                                                (respawn? #t))

                              (shepherd-service (provision '(swayidle))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   swayidle
                                                                   "/bin/swayidle"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/swayidle.log")))
                                                (respawn? #t))

                              (shepherd-service (provision '(swww-daemon))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   swww
                                                                   "/bin/swww-daemon"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/swww-daemon.log")))
                                                (respawn? #t))

                              (shepherd-service (provision '(xdg-desktop-portal))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   xdg-desktop-portal
                                                                   "/libexec/xdg-desktop-portal"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/xdg-desktop-portal.log")))
                                                (respawn? #t))

                              (shepherd-service (provision '(xdg-desktop-portal-gtk))
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
