;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %modprobe-services
  (list ;modprobed-db 配置文件
        (simple-service 'modprobed-db-config home-files-service-type
                        `((".config/modprobed-db/modprobed-db.conf" ,(plain-file
                                                                      "modprobed-db.conf"
                                                                      "IGNORE=(hid-uclogic wacom)"))))

        ;; modprobed-db 激活时运行（一次性初始化）
        (simple-service 'modprobed-db-activation home-activation-service-type
                        #~(begin
                            (use-modules (guix build utils))
                            ;; 确保配置目录存在
                            (mkdir-p (string-append (getenv "HOME")
                                                    "/.config/modprobed-db"))
                            ;; 运行 modprobed-db store 记录当前模块
                            (system* #$(file-append modprobed-db
                                                    "/bin/modprobed-db")
                                     "storesilent")))))
