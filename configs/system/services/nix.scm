;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-service-modules nix
                     shepherd)

(define %nix-services
  (list (service nix-service-type
                 (nix-configuration (extra-config (list (string-append
                                                         "trusted-users"
                                                         " = root "
                                                         username)))))

        (simple-service 'non-nixos-gpu shepherd-root-service-type
                        (list (shepherd-service (documentation
                                                 "Install GPU drivers for running GPU accelerated programs from Nix.")
                                                (provision '(non-nixos-gpu))
                                                (requirement '(nix-daemon))
                                                (start #~(make-forkexec-constructor '
                                                          ("/run/current-system/profile/bin/ln"
                                                           "-nsf"
                                                           "/var/lib/non-nixos-gpu"
                                                           "/run/opengl-driver")))
                                                (stop #~(make-kill-destructor))
                                                (auto-start? #t)
                                                (one-shot? #t))))))
