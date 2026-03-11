;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %trash-services
  (list
   (simple-service 'setup-trash-dirs home-activation-service-type
     #~(begin
         (use-modules (guix build utils))
         (let* ((uid (getuid))
                (trash-dir-name (string-append ".Trash-" (number->string uid)))
                (data-dirs '#$%data-dirs))
           (for-each
            (lambda (dir)
              (let ((trash-path (string-append "/data/" dir "/" trash-dir-name)))
                (when (file-exists? (string-append "/data/" dir))
                  (mkdir-p trash-path)
                  (chmod trash-path #o700))))
            data-dirs))))))
