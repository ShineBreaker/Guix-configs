#!/usr/bin/env guile
!#

;; Compatibility wrapper. The sidebar implementation lives in sidebar-render.scm.

(let ((script (string-append (getenv "HOME") "/.config/tmux/scripts/sidebar-render.scm")))
  (setenv "GUILE_AUTO_COMPILE" "0")
  (execlp "guile" "guile" "--no-auto-compile" "-s" script "git"))
