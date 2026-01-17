(define %mapped-devices-config
  (list (mapped-device
          (source (uuid "327f2e02-1e4f-48b2-87f0-797c481850c9"))
          (target "root")
          (type luks-device-mapping)
          (arguments '(#:key-file "/cryptroot.key")))))
