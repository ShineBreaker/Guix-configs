;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-package-modules android
                     games)

(use-service-modules linux)

(define %udev-services
  (list (udev-rules-service 'android android-udev-rules
                            #:groups '("adbusers"))
        (udev-rules-service 'steam-devices steam-devices-udev-rules)
        (udev-rules-service 'controller
                            (udev-rule
                             "60-controller-permission.rules"
                             "KERNEL==\"event*\", ATTRS{idVendor}==\"045e\", ATTRS{idProduct}==\"028e\", MODE=\"0660\", GROUP=\"users\""))
        (udev-rules-service 'cpu-dma
                            (udev-rule "99-cpu-dma-latency.rules"
                             "DEVPATH==\"/devices/virtual/misc/cpu_dma_latency\", OWNER=\"root\", GROUP=\"audio\", MODE=\"0660\""))))
