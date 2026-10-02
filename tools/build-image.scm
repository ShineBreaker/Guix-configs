;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; build-image.scm — guix system image 产物落地助手
;; 调用方（blueprint.scm 的 build-iso-command）已套 guix time-machine 锁频道；
;; 本脚本自身不锁频道、不需要 sudo。
;; 文档：docs/scripts/blue-helpers.md §build-image.scm

(use-modules (ice-9 match)
             (guix build utils)
             (guix scripts system))

(match (command-line)
  [(_ dst . args)
   (let* ([output
           (with-output-to-string
             (lambda ()
               (apply guix-system "image" args)))]
          [src (string-trim-both output)])
     (when (file-exists? src)
       (mkdir-p (dirname dst))
       (copy-file src dst)
       (make-file-writable dst)))]
  [_ (format (current-error-port)
             "usage: guix repl -- build-image.scm DST [IMAGE-ARGS]...\n")
     (exit 1)])
