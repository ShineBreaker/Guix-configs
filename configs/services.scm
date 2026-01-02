(define mihomo-service
  (shepherd-service (provision '(mihomo))
                    (start #~(make-forkexec-constructor (list #$(file-append
                                                                 mihomo
                                                                 "/bin/mihomo")
                                                         "-f"
                                                         "/home/brokenshine/.config/mihomo/config.yaml")
                                                        #:log-file
                                                        "/var/log/mihomo.log"))
                    (stop #~(make-kill-destructor))
                    (respawn? #t)))

(define mihomo-daemon
  (service-type (name 'mihomo-daemon)
                (extensions (list (service-extension
                                   shepherd-root-service-type
                                   (lambda (_)
                                     (list mihomo-service)))))
                (default-value #t)
                (description "Run the mihomo daemon.")))
