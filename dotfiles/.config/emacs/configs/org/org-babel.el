;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; org-babel.el --- Org Babel 文学编程配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Org Babel 文学编程系统，支持代码块执行、Tangle、Noweb 等。

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; Babel 语言支持
;; ═════════════════════════════════════════════════════════════════════════════

(use-package org
  :config
  ;; 激活 Babel 语言
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (shell . t)
     (python . t)
     (scheme . t)
     (js . t)
     (lua . t)
     (sql . t)
     (dot . t)
     (plantuml . t)
     (C . t)
     (java . t)
     (latex . t)
     (org . t)))

  ;; 安全执行，不提示确认
  (setq org-confirm-babel-evaluate nil)

  ;; 默认代码块头参数
  (setq org-babel-default-header-args
        '((:session . "none")
          (:results . "replace output")
          (:exports . "code")
          (:cache . "no")
          (:noweb . "no")
          (:hlines . "no")
          (:tangle . "no"))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Babel 执行函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun my/org-babel-execute-current-block ()
  "执行当前代码块。"
  (interactive)
  (org-babel-execute-src-block))

(defun my/org-babel-execute-and-next ()
  "执行当前代码块并跳转到下一个。"
  (interactive)
  (org-babel-execute-src-block)
  (org-babel-next-src-block))

(defun my/org-babel-execute-all ()
  "执行当前缓冲区所有代码块。"
  (interactive)
  (org-babel-execute-buffer))

;; ═════════════════════════════════════════════════════════════════════════════
;; Babel Tangle 函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun my/org-babel-tangle-current-block ()
  "Tangle 当前代码块。"
  (interactive)
  (let ((current-prefix-arg '(4)))
    (call-interactively #'org-babel-tangle)))

(defun my/org-babel-tangle-file ()
  "将整个文件 tangle 到指定目录。"
  (interactive)
  (org-babel-tangle))

;; ═════════════════════════════════════════════════════════════════════════════
;; Babel 导航与编辑
;; ═════════════════════════════════════════════════════════════════════════════

(defun my/org-babel-goto-block ()
  "跳转到下一个代码块。"
  (interactive)
  (org-babel-next-src-block))

(defun my/org-babel-goto-previous-block ()
  "跳转到上一个代码块。"
  (interactive)
  (org-babel-previous-src-block))

(defun my/org-babel-demarcate-block ()
  "将当前代码块分割为两个。"
  (interactive)
  (org-babel-demarcate-block))

(defun my/org-babel-edit-src-code ()
  "在专用缓冲区编辑代码块。"
  (interactive)
  (org-edit-src-code))

;; ═════════════════════════════════════════════════════════════════════════════
;; 快速插入代码块模板
;; ═════════════════════════════════════════════════════════════════════════════

(defun my/org-insert-elisp-block ()
  "插入 Emacs Lisp 代码块。"
  (interactive)
  (insert "#+begin_src emacs-lisp\n\n#+end_src")
  (forward-line -1))

(defun my/org-insert-shell-block ()
  "插入 Shell 代码块。"
  (interactive)
  (insert "#+begin_src shell\n\n#+end_src")
  (forward-line -1))

(defun my/org-insert-python-block ()
  "插入 Python 代码块。"
  (interactive)
  (insert "#+begin_src python\n\n#+end_src")
  (forward-line -1))

(defun my/org-insert-scheme-block ()
  "插入 Scheme 代码块。"
  (interactive)
  (insert "#+begin_src scheme\n\n#+end_src")
  (forward-line -1))

(defun my/org-insert-js-block ()
  "插入 JavaScript 代码块。"
  (interactive)
  (insert "#+begin_src js\n\n#+end_src")
  (forward-line -1))

(defun my/org-insert-dot-block ()
  "插入 Graphviz 代码块。"
  (interactive)
  (insert "#+begin_src dot :file diagram.png :cmdline -Tpng\n\n#+end_src")
  (forward-line -1))

(defun my/org-insert-plantuml-block ()
  "插入 PlantUML 代码块。"
  (interactive)
  (insert "#+begin_src plantuml :file diagram.png\n\n#+end_src")
  (forward-line -1))

(provide 'org-babel)
;;; org-babel.el ends here
