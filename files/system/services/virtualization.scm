;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-service-modules containers
                     dns
                     networking
                     virtualization)

(define %virtualization-services
  (list (service dnsmasq-service-type
                 (dnsmasq-configuration (shepherd-provision '(dnsmasq-virbr0))
                                        (extra-options (list
                                                        "--except-interface=lo"
                                                        "--interface=virbr0"
                                                        "--bind-dynamic"
                                                        "--dhcp-range=192.168.10.2,192.168.10.254"))))

        (service rootless-podman-service-type
                 (rootless-podman-configuration (subuids (list (subid-range
                                                                (name
                                                                 "brokenshine")
                                                                (start
                                                                 100000)
                                                                (count
                                                                 65536))))
                                                (subgids (list (subid-range
                                                                (name
                                                                 "brokenshine")
                                                                (start
                                                                 100000)
                                                                (count
                                                                 65536))))))

        (service static-networking-service-type
                 (list (static-networking (provision '(network-manager))
                                          (links (list (network-link (name
                                                                      "virbr0")
                                                                     (type 'bridge)
                                                                     (arguments '()))))
                                          (addresses (list (network-address
                                                            (device
                                                             "virbr0")
                                                            (value
                                                             "192.168.10.1/24")))))))

        (service libvirt-service-type
                 (libvirt-configuration (unix-sock-group "libvirt")))
        (service virtlog-service-type)))
