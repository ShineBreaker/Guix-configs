(define %bootloader-config
  (bootloader-configuration
    (bootloader uefi-uki-removable-bootloader)
    (theme (grub-theme (inherit (grub-theme))
                       (gfxmode '("1024x786x32"))))
    (targets '("/efi"))
    (extra-initrd "/SYSTEM/Guix/@/boot/cryptroot.cpio")))
