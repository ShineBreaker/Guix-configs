(define %mapped-devices-config
  (list (mapped-device
          (source (uuid "327f2e02-1e4f-48b2-87f0-797c481850c9"))
          (target "root")
          (type luks-device-mapping)
          (arguments '(#:key-file "/cryptroot.key")))))

(define %file-systems-config
  (append (list (file-system
                  (device (file-system-label "Linux"))
                  (mount-point "/")
                  (type "btrfs")
                  (options "subvol=SYSTEM/Guix/@,compress=zstd:6")
                  (dependencies %mapped-devices-config)
                  (create-mount-point? #t))
                (file-system
                  (device (file-system-label "Linux"))
                  (mount-point "/home")
                  (type "btrfs")
                  (options "subvol=DATA/Home/Guix,compress=zstd:6")
                  (dependencies %mapped-devices-config)
                  (create-mount-point? #t))
                (file-system
                  (device (file-system-label "Linux"))
                  (mount-point "/data")
                  (type "btrfs")
                  (options "subvol=DATA/Share,compress=zstd:6")
                  (dependencies %mapped-devices-config)
                  (create-mount-point? #t))
                (file-system
                  (device (file-system-label "Linux"))
                  (mount-point "/nix")
                  (type "btrfs")
                  (options "subvol=SYSTEM/NixOS/@nix,compress=zstd:6")
                  (dependencies %mapped-devices-config)
                  (create-mount-point? #t))
                (file-system
                  (device (file-system-label "Linux"))
                  (mount-point "/var/lib/flatpak")
                  (type "btrfs")
                  (options "subvol=DATA/Flatpak,compress=zstd:6")
                  (dependencies %mapped-devices-config)
                  (create-mount-point? #t))
                (file-system
                  (device (uuid "9699-52A2"
                                'fat))
                  (mount-point "/efi")
                  (type "vfat")
                  (create-mount-point? #t)))

          %base-file-systems))
