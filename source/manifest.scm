;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; 仓库引导依赖清单。
;; 用法：guix time-machine -C source/channel.lock -- shell -m source/manifest.scm
;; time-machine 提供锁定的频道（含 bluebox），manifest 从中挑出 blue。
;; 将来自制 ISO 的 live 配置可直接引用本文件，把 blue 烤进 live profile。
(specifications->manifest '("blue"))
