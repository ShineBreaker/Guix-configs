;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (gnu home services guix)
             (guix channels)

             (px services audio))

(use-service-modules authentication
                     desktop
                     linux
                     sound)

(define %base-services
  (append (map (lambda (tty)
                 (service kmscon-service-type
                          (kmscon-configuration (virtual-terminal tty)
                                                (font-engine "pango")
                                                (font-size 24))))
               '("tty2" "tty3" "tty4" "tty5" "tty6"))

          (list (service fprintd-service-type)
                (service gnome-keyring-service-type)
                (service gvfs-service-type)
                (service rtkit-daemon-service-type)


                (simple-service 'home-channels home-channels-service-type
                                guix-channels)

                (simple-service 'root-services shepherd-root-service-type
                                      (list (shepherd-timer '(guix-gc)
                                                            #~(calendar-event
                                                               #:days-of-week '
                                                               (sunday)
                                                               #:hours '
                                                               (18)
                                                               #:minutes '
                                                               (0))
                                                            #~("/run/current-system/profile/bin/guix"
                                                               "gc"
                                                               "--delete-generations=14d")
                                                            #:requirement '(user-processes
                                                                            guix-daemon)))))))
