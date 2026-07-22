;;; init.el --- literal-config bootstrap(按需 tangle emacs.org → main.el) -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 本文件是 literal-config 的固定 bootstrap 入口,**不由 emacs.org tangle 生成**,
;; 永久纳入 git 跟踪。chemacs2 在选定 literal profile 后会加载本文件。
;;
;; chemacs2 迁移后(commit 0ca2c196)说明:已无 chemacs2 引导层,本文件由
;; `emacs' 直接以 user-emacs-directory = 本仓库路径加载。
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
;;
;; Stow 软链陷阱:emacs.org 经 Stow 软链到仓库源,org 的全局 :tangle main.el 相对
;; org 的 truename(仓库源目录)解析,故 tangle 实际落地仓库源 main.el,而非部署目录。
;; TARGET-FILE 参数因每个块都有显式 :tangle 而被忽略。故 tangle 后需同步产物到部署目录
;; (见下方 copy-file)。仓库源 main.el 已 gitignore,不会污染 git 状态。

;;; Code:

(let* ((org-file (expand-file-name "emacs.org" user-emacs-directory))
       (main-file (expand-file-name "main.el" user-emacs-directory)))

  ;; 按需 tangle:main.el 缺失,或 emacs.org 比 main.el 新
  (when (or (not (file-exists-p main-file))
            (file-newer-than-file-p org-file main-file))
    ;; Emacs 31 仍 defvar `byte-compile-root-dir'(见 bytecomp.el:1232),但 bytecomp.el
    ;; 是 lazy-load,默认不在初始环境。`elfeed-link.el' 注册的 `elfeed' org link
    ;; 会被 `org-babel-tangle--unbracketed-link' 通过 `org-store-link' 试探,触发
    ;; autoload → `require 'elfeed-show' → `require 'elfeed'。elfeed.el 内
    ;; `(cl-eval-when (load eval) (unless byte-compile-root-dir ...))' 这段
    ;; byte-code 假设变量已 bound,但 elfeed-3.4.2 不可绕开。预先 defvar 即可
    ;; 让字节码读到 nil 而不是 void-variable;真正根治需升级到 elfeed-4.0.1。
    (when (not (boundp 'byte-compile-root-dir))
      (defvar byte-compile-root-dir nil))
    (require 'org)
    (require 'ob-tangle)
    ;; Emacs 28+ 在 daemon/批处理下 org-babel-tangle 可能触发 GC 抖动,
    ;; 推高阈值以加速(启动后由 gcmh 复位)。
    (let ((gc-cons-threshold most-positive-fixnum))
      (message "[literal] tangling emacs.org → main.el ...")
      ;; Stow 软链陷阱:emacs.org 是软链,user-emacs-directory 下的 main-file 作为
      ;; TARGET-FILE 传给 `org-babel-tangle-file' 时会被忽略——因为 emacs.org 的全局
      ;; #+PROPERTY header-args:emacs-lisp :tangle main.el 给每个块显式指定了输出,
      ;; 该相对路径相对 org 文件的 truename(仓库源目录)解析,而非软链所在部署目录。
      ;; 故 tangle 实际落地到仓库源 main.el,部署目录的 main.el 永不更新、永远 stale。
      ;; 这里保持调用签名不变(契约),tangle 后把仓库源产物同步到部署目录。
      (org-babel-tangle-file org-file main-file "emacs-lisp")
      (let ((truename-main (expand-file-name
                            "main.el"
                            (file-name-directory (file-truename org-file)))))
        (unless (file-equal-p truename-main main-file)
          ;; 仓库源产物 != 部署目标(Stow 软链场景):同步过去
          (copy-file truename-main main-file t)
          (message "[literal] synced tangle product: %s → %s"
                   truename-main main-file)))
      (message "[literal] tangle done.")))

  ;; 加载真正的配置
  (load main-file nil t))

(provide 'literal-bootstrap-init)
;;; init.el ends here
