;; -*- no-byte-compile: t -*-
;;; modules/ui/notification/packages.el

(package! alert :pin "abc123...")
(package! notifications
  :pin "def456..."
  :recipe (:host github :repo "jml/notify.el"))
