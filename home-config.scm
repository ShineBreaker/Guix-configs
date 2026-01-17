(load "./configs/channel.scm")
(load "./configs/information.scm")

(load "./configs/home/modules.scm")
(load "./configs/home/package.scm")

(load "./configs/home/services/desktop.scm")
(load "./configs/home/services/dotfile.scm")
(load "./configs/home/services/environment-variables.scm")
(load "./configs/home/services/font.scm")

(define home-config
  (home-environment
    (packages %packages-list)

    (services
     (append %desktop-services
             %dotfile-services
             %environment-variable-services
             %font-services

             (modify-services %rosenthal-desktop-home-services
               (home-pipewire-service-type config =>
                                           (home-pipewire-configuration (wireplumber
                                                                         wireplumber)
                                                                        (enable-pulseaudio?
                                                                         #t))))))))

home-config
