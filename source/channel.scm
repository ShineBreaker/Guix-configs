;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

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
                  "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))
              (channel
               (name 'pantherx)
               (url "https://codeberg.org/gofranz/panther.git")
               (introduction
                (make-channel-introduction
                 "54b4056ac571611892c743b65f4c47dc298c49da"
                 (openpgp-fingerprint
                  "A36A D41E ECC7 A871 1003  5D24 524F EB1A 9D33 C9CB"))))
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
               (name 'sops-guix)
               (url "https://github.com/fishinthecalculator/sops-guix.git")
               (branch "main")
               ;; Enable signature verification:
               (introduction
                (make-channel-introduction
                 "0bbaf1fdd25266c7df790f65640aaa01e6d2dbc9"
                 (openpgp-fingerprint
                  "8D10 60B9 6BB8 292E 829B  7249 AED4 1CC1 93B7 01E2")))))

       %default-channels)
