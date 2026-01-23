(use-modules (gnu packages firmware)

             (nongnu packages firmware)
             (nongnu packages linux)
             (nongnu system linux-initrd))

(define %initrd-config
  microcode-initrd)
(define %firmware-config
  (list linux-firmware sof-firmware bluez-firmware ovmf-x86-64))
(define %kernel-config
  linux-xanmod)
(define %kernel-arguments-config
  (cons* "kernel.sysrq=1" "zswap.enabled=1" "zswap.max_pool_percent=90"
         "modprobe.blacklist=amdgpu,pcspkr,hid_nintendo"
         %default-kernel-arguments))
