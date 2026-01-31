;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (guix channels))

(define guix-channels
  (append (list (channel
                  (name 'cast)
                  (branch "main")
                  (url "https://codeberg.org/vnpower/cast")
                  (introduction
                   (make-channel-introduction
                    "fab73647fd9f0f2167d9ef9d42cddd77500fffb3"
                    (openpgp-fingerprint
                     "D430 1F59 A65F 49DA 918A  3C0D 8D4C 3248 29DE D156"))))
                (channel
                  (name 'jeans)
                  (branch "main")
                  (url "https://codeberg.org/BrokenShine/jeans.git")
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
                  (name 'panther)
                  (branch "master")
                  (url "https://codeberg.org/gofranz/panther")
                  (introduction
                   (make-channel-introduction
                    "54b4056ac571611892c743b65f4c47dc298c49da"
                    (openpgp-fingerprint
                     "A36A D41E ECC7 A871 1003  5D24 524F EB1A 9D33 C9CB"))))
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
                  (name 'rosenthal)
                  (url "https://codeberg.org/hako/rosenthal.git")
                  (branch "trunk")
                  (introduction
                   (make-channel-introduction
                    "7677db76330121a901604dfbad19077893865f35"
                    (openpgp-fingerprint
                     "13E7 6CD6 E649 C28C 3385  4DF5 5E5A A665 6149 17F7"))))
                (channel
                  (name 'saayix)
                  (branch "main")
                  (url "https://codeberg.org/look/saayix")
                  (introduction
                   (make-channel-introduction
                    "12540f593092e9a177eb8a974a57bb4892327752"
                    (openpgp-fingerprint
                     "3FFA 7335 973E 0A49 47FC  0A8C 38D5 96BE 07D3 34AB"))))
                (channel
                  (name 'selected-guix-works)
                  (url "https://github.com/gs-101/selected-guix-works.git")
                  (branch "main")
                  (introduction
                   (make-channel-introduction
                    "5d1270d51c64457d61cd46ec96e5599176f315a4"
                    (openpgp-fingerprint
                     "C780 21F7 34E4 07EB 9090  0CF1 4ACA 6D6F 89AB 3162"))))
                (channel
                  (inherit (car %default-channels))
                  (branch "master")))

          %default-channels))

guix-channels
