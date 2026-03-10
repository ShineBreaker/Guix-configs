;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-service-modules desktop)

(define %filesystem-services
  (list (simple-service 'fixed-machine-id etc-service-type
                        (list `("machine-id" ,(plain-file "machine-id"
                                               fixed-machine-id))))

        (simple-service 'fix-var-tmp-perms activation-service-type
                        #~(begin
                            (use-modules (guix build utils))
                            (mkdir-p "/var/tmp")
                            (chmod "/var/tmp" #o1777)))

        (simple-service 'fix-data-perms activation-service-type
                        #~(begin
                            (use-modules (guix build utils))
                            (mkdir-p "/data")
                            (chmod "/data" #o1777)))

        (simple-service 'create-xdg-dirs activation-service-type
                        (with-imported-modules
                          (source-module-closure '((guix build utils)))
                            #~(begin (use-modules (guix build utils))
                                        (let* ((pw (getpwnam #$username))
                                          (uid (passwd:uid pw))
                                          (gid (passwd:gid pw))
                                          (home (string-append "/home/" #$username)))
                                          (for-each (lambda (dir)
                                            (let ((path
                                              (string-append home "/" dir)))
                                              (mkdir-p path)
                                              (chown path uid gid)
                                              (chmod path #o755)))
                                          '#$%data-dirs)))))))
