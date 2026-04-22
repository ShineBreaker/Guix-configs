;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (guix channels))

(define guix-channels
  (append (list (channel
                  (inherit (car %default-channels))
                  (branch "master"))

                (channel
                  (name 'jeans)
                  (branch "main")
                  (url "https://github.com/ShineBreaker/jeans.git")
                  (introduction
                   (make-channel-introduction
                    "1e30ccbcaef375169d453d89d8186137bc32d9e8"
                    (openpgp-fingerprint
                     "6271 1D5E 9CCD EC69 07CA  DBF8 8637 1322 2257 1907"))))
                (channel
                  (name 'nonguix)
                  (branch "master")
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
                     "13E7 6CD6 E649 C28C 3385  4DF5 5E5A A665 6149 17F7")))))

          %default-channels))

guix-channels
