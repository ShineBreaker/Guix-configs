;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; Emacs 包清单。
;; 安装方式：guix package -m emacs.scm
;; 或将其加入 home-config.org 的 packages 列表中。

;;; Code:

(packages->manifest
 (list
  ;; === Java 开发 ===

  ;; LSP 服务器：Eclipse JDT Language Server
  ;; 需要 jeans 频道
  (specification->package "jdtls-bin")

   ;; 非 LSP 导航 fallback：基于 ripgrep 的跳转到定义
   ;; LSP 索引未完成时提供即时导航能力
   (specification->package "emacs-dumb-jump")

   ;; Eglot 协议扩展：snippet TextEdit、编码协商、额外引用方法等
   ;; 支持所有语言的 LSP 扩展，Java 项目中尤其有用
   (specification->package "")))

;;; emacs.scm ends here
