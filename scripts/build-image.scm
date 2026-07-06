;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; build-image.scm —— guix system image 产物落地助手
;;
;; 用法:guix repl -- scripts/build-image.scm DST [OS-DEFINITION-OR-ARGS]...
;;
;; 做三件事(等价 Testament/scripts/build-image.scm,只是加 SPDX 头):
;;   1. 调 (guix-system "image" args...) 程序化地生成 ISO
;;   2. 从 stdout 抓 store path(/gnu/store/...-iso9660-image)
;;   3. 复制到 DST(dist/<name>.iso)并 chmod u+w 让后续可签名/读
;;
;; 由 blueprint.scm 的 build-iso-command 通过 %guix 调用(自动套 time-machine
;; 锁定频道)。本身不锁定频道、不需要 sudo。

(use-modules (ice-9 match)
             (guix build utils)
             (guix scripts system))

(match (command-line)
  ((_ dst . args)
   (let* ((output
           (with-output-to-string
             (lambda ()
               (apply guix-system "image" args))))
          (src (string-trim-both output)))
     (when (file-exists? src)
       (mkdir-p (dirname dst))
       (copy-file src dst)
       (make-file-writable dst)))))
