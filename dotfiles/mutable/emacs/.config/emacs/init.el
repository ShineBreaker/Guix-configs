;;; init.el --- literal-config bootstrap(按需 tangle emacs.org → main.el) -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 本文件是 literal-config 的固定 bootstrap 入口,**不由 emacs.org tangle 生成**,
;; 永久纳入 git 跟踪。chemacs2 在选定 literal profile 后会加载本文件。
;;
;; 职责(且仅此三步):
;;   1. 检测 emacs.org 是否比 main.el 新(或 main.el 不存在)
;;   2. 是则调用 `org-babel-tangle-file' 重新生成 main.el
;;   3. load main.el(真正的配置,由 emacs.org tangle 生成)
;;
;; 为何不直接把 tangle 产物命名为 init.el?
;;   → 那样 tangle 会覆盖本 bootstrap,机制就自杀了。
;;   → 拆成 init.el(固定入口) + main.el(tangle 产物)是 literate config 的标准做法。
;;
;; tangle 只在 emacs.org 变更后第一次重启时发生,平时直接 load 现有 main.el,
;; 启动开销与无 literate 配置一致(不加载 org)。

;;; Code:

;; chemacs2 已把 user-emacs-directory 指向本目录(literal-config/)。
(let* ((org-file (expand-file-name "emacs.org" user-emacs-directory))
       (main-file (expand-file-name "main.el" user-emacs-directory)))

  ;; 按需 tangle:main.el 缺失,或 emacs.org 比 main.el 新
  (when (or (not (file-exists-p main-file))
            (file-newer-than-file-p org-file main-file))
    (require 'org)
    (require 'ob-tangle)
    ;; Emacs 28+ 在 daemon/批处理下 org-babel-tangle 可能触发 GC 抖动,
    ;; 推高阈值以加速(启动后由 gcmh 复位)。
    (let ((gc-cons-threshold most-positive-fixnum))
      (message "[literal] tangling emacs.org → main.el ...")
      (org-babel-tangle-file org-file main-file "emacs-lisp")
      (message "[literal] tangle done.")))

  ;; 加载真正的配置
  (load main-file nil t))

(provide 'literal-bootstrap-init)
;;; init.el ends here
