(define %dotfile-services
  (list (service home-dotfiles-service-type
                 (home-dotfiles-configuration (directories '("../../../dotfiles"))
                                              (excluded '("^.git$"
                                                          "^.gitignore$"
                                                          "^.github$"))))

        (service home-files-service-type
                 `((".guile" ,%default-dotguile)
                   (".Xdefaults" ,%default-xdefaults)))

        (service home-xdg-configuration-files-service-type
                 `(("gdb/gdbinit" ,%default-gdbinit)
                   ("nano/nanorc" ,%default-nanorc)))

        (simple-service 'fish-greeting
                        home-xdg-configuration-files-service-type
                        `(("fish/conf.d/greeting.fish" ,(plain-file
                                                         "greeting.fish"
                                                         "set --global fish_greeting 日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。"))))))
