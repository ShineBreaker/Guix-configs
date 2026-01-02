(use-modules (guix channels))

(define guix-channels
  (append (list (channel
                  (inherit (car %default-channels))
                  (url "https://mirror.sjtu.edu.cn/git/guix.git"))
                (channel
                  (name 'nonguix)
                  (url "https://gitlab.com/nonguix/nonguix")
                  (introduction
                   (make-channel-introduction
                    "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
                    (openpgp-fingerprint
                     "2A39 3FFF 68F4 OPEF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))
                (channel
                  (name 'rosenthal)
                  (url "https://codeberg.org/hako/rosenthal.git")
                  (branch "trunk")
                  (introduction
                   (make-channel-introduction
                    "7677db76330121a901604dfbad19077893865f35"
                    (openpgp-fingerprint
                     "13E7 6CD6 E649 C28C 3385  4DF5 5E5A A665 6149 17F7"))))
                (channel
                  (name 'radix)
                  (url "https://codeberg.org/anemofilia/radix.git")
                  (branch "main")
                  (introduction
                   (make-channel-introduction
                    "f9130e11e35d2c147c6764ef85542dc58dc09c4f"
                    (openpgp-fingerprint
                     "F164 709E 5FC7 B32B AEC7  9F37 1F2E 76AC E3F5 31C8"))))
                (channel
                  (name 'saayix)
                  (branch "main")
                  (url "https://codeberg.org/look/saayix")
                  (introduction
                   (make-channel-introduction
                    "12540f593092e9a177eb8a974a57bb4892327752"
                    (openpgp-fingerprint
                     "3FFA 7335 973E 0A49 47FC  0A8C 38D5 96BE 07D3 34AB")))))

          %default-channels))
