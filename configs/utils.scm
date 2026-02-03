(use-modules (gnu packages java))

;; Copied from Hako.
(define %jdk-symlink-activation
  (program-file "symlink-jdk"
                (with-imported-modules '((guix build utils))
                                       #~(begin
                                           (use-modules (guix build utils))
                                           (let ((sdkman (in-vicinity (getenv
                                                                       "HOME")
                                                          ".sdkman/candidates/java")))
                                             (mkdir-p sdkman)
                                             (chdir sdkman))
                                           (for-each (lambda (jdk)
                                                       (let ((link (strip-store-file-name
                                                                    jdk)))
                                                         (false-if-exception (delete-file
                                                                              link))
                                                         (symlink jdk link)))
                                                     '#$(list openjdk25
                                                              openjdk21
                                                              openjdk17))))))
