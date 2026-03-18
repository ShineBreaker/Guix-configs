;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (gnu home services shells))
(define %fish-packages-list
  (cons* (specs->pkgs+out "atuin"
                          "bat"
                          "direnv"
                          "fd"
                          "ripgrep"
                          "fzf"
                          "lolcat"
                          "zoxide")))

(define %fish-services
  (list (simple-service 'fish-configs home-xdg-configuration-files-service-type
          (list `("fish/conf.d/10-source.fish" ,(computed-substitution-with-inputs "config.fish"
                 (plain-file "10-source.fish"
                   "status is-interactive
                    and begin

                      $$bin/atuin$$ init fish | source
                      $$bin/direnv$$ hook fish | source
                      $$bin/fzf$$ --fish | source
                      $$bin/zoxide$$ init fish | source

                    end")
                 (specs->pkgs "atuin" "direnv" "fzf" "zoxide")))))

        (simple-service 'fish-functions
                        home-xdg-configuration-files-service-type
                        (list `("fish/functions/fenv.main.fish" ,(file-append
                                                                  fish-foreign-env
                                                                  "/share/fish/functions/fenv.main.fish"))
                              `("fish/functions/fenv.fish" ,(file-append
                                                             fish-foreign-env
                                                             "/share/fish/functions/fenv.fish"))))))
