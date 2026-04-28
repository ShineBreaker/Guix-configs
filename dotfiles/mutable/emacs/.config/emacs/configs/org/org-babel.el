;;; org-babel.el --- Org Babel 文学编程配置 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 Org Babel 文学编程系统，支持代码块执行、Tangle、Noweb 等。
;; 作为 org-mode.el 的扩展，延迟加载直到 org 包加载完成。
;;
;; 性能优化：通过 `:after org` 确保 Babel 相关的复杂配置（语言激活、头参数设置）
;; 仅在真正需要使用 Org 功能时才被加载。
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; Babel 语言支持
;; ═════════════════════════════════════════════════════════════════════════════

(use-package org
  :defer t
  :after org
  :config
  ;; 激活 Babel 语言（内置支持）
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)      ; 内置，无需依赖
     (shell . t)           ; 内置，使用 sh/bash
     (python . t)          ; 需要 python
     (scheme . t)          ; 需要 guile
     (js . t)              ; 需要 node
     (lua . t)             ; 需要 lua
     (sql . t)             ; 需要 sqlite/mysql/postgresql
     (C . t)               ; 需要 clang/gcc
     (java . t)            ; 需要 openjdk
     (latex . t)           ; 需要 texlive
     (org . t)             ; 内置
     (lisp . t)            ; 需要 sbcl
     (dot . t)             ; 需要 graphviz
     (plantuml . t)))      ; 需要 plantuml + openjdk

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
          (:tangle . "no")))

  ;; C/C++ 使用 clang 编译
  (setq org-babel-C-compiler "clang"
        org-babel-C++-compiler "clang++")

  ;; Python 解释器
  (setq org-babel-python-command (or (executable-find "python3")
                                     (executable-find "python")
                                     "python")))

;; ═════════════════════════════════════════════════════════════════════════════
;; 额外语言支持（需要额外包）
;; ═════════════════════════════════════════════════════════════════════════════

;; Rust 代码块支持
(use-package ob-rust
  :defer t
  :after org
  :config
  (add-to-list 'org-babel-load-languages '(rust . t))
  (setq org-babel-rust-command "rustc"))

;; TypeScript 代码块支持
(use-package ob-typescript
  :defer t
  :after org
  :config
  (add-to-list 'org-babel-load-languages '(typescript . t)))

;; Kotlin 代码块支持（通过 shell 执行）
(defun org-babel-execute:kotlin (body params)
  "执行 Kotlin 代码块。"
  (let* ((kotlinc (custom/find-executable "kotlinc"))
         (src-file (make-temp-file "kotlin-src" nil ".kt"))
         (out-file (make-temp-file "kotlin-out" nil ".jar")))
    (with-temp-file src-file (insert body))
    (org-babel-eval
     (format "%s %s -include-runtime -d %s && java -jar %s"
             kotlinc src-file out-file out-file)
     "")))

;; ═════════════════════════════════════════════════════════════════════════════
;; Babel 执行函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/org-babel-execute-current-block ()
  "执行当前代码块。"
  (interactive)
  (org-babel-execute-src-block))

(defun custom/org-babel-execute-and-next ()
  "执行当前代码块并跳转到下一个。"
  (interactive)
  (org-babel-execute-src-block)
  (org-babel-next-src-block))

(defun custom/org-babel-execute-all ()
  "执行当前缓冲区所有代码块。"
  (interactive)
  (org-babel-execute-buffer))

;; ═════════════════════════════════════════════════════════════════════════════
;; Babel Tangle 函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/org-babel-tangle-current-block ()
  "Tangle 当前代码块。"
  (interactive)
  (let ((current-prefix-arg '(4)))
    (call-interactively #'org-babel-tangle)))

(defun custom/org-babel-tangle-file ()
  "将整个文件 tangle 到指定目录。"
  (interactive)
  (org-babel-tangle))

;; ═════════════════════════════════════════════════════════════════════════════
;; Babel 导航与编辑
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/org-babel-goto-block ()
  "跳转到下一个代码块。"
  (interactive)
  (org-babel-next-src-block))

(defun custom/org-babel-goto-previous-block ()
  "跳转到上一个代码块。"
  (interactive)
  (org-babel-previous-src-block))

(defun custom/org-babel-demarcate-block ()
  "将当前代码块分割为两个。"
  (interactive)
  (org-babel-demarcate-block))

(defun custom/org-babel-edit-src-code ()
  "在专用缓冲区编辑代码块。"
  (interactive)
  (org-edit-src-code))

;; ═════════════════════════════════════════════════════════════════════════════
;; 快速插入代码块模板
;; ═════════════════════════════════════════════════════════════════════════════

(defcustom custom/org-babel-language-alist
  '(;; 内置支持
    ("emacs-lisp" . nil)
    ("shell" . nil)
    ("python" . nil)
    ("scheme" . nil)
    ("lisp" . nil)             ; Common Lisp (sbcl)
    ("js" . nil)               ; JavaScript (node)
    ;; 扩展语言
    ("typescript" . nil)       ; 需要 ob-typescript
    ("rust" . nil)             ; 需要 ob-rust
    ("C" . nil)                ; C (clang)
    ("C++" . nil)              ; C++ (clang++)
    ("java" . nil)
    ("kotlin" . nil)           ; 需要 kotlinc
    ("lua" . nil)
    ("sql" . nil)
    ("latex" . nil)
    ;; 图表
    ("dot" . ":file diagram.png :cmdline -Tpng")      ; Graphviz
    ("plantuml" . ":file diagram.png"))               ; PlantUML
  "语言与默认参数的映射。
格式为 (语言 . 参数字符串)，若为 nil 则无额外参数。"
  :type '(alist :key-type string :value-type (choice string (const nil))))

(defun custom/org-insert-src-block (language)
  "插入指定语言的代码块。
LANGUAGE 通过补全选择，支持自定义默认参数。"
  (interactive
   (list (completing-read "语言: " (mapcar #'car custom/org-babel-language-alist))))
  (let* ((params (alist-get language custom/org-babel-language-alist nil nil #'string=))
         (header (if params
                     (format "#+begin_src %s %s" language params)
                   (format "#+begin_src %s" language))))
    (insert header)
    (insert "\n\n#+end_src")
    (forward-line -1)
    (indent-according-to-mode)))

(defun custom/org-insert-src-block-inline (language)
  "插入内联代码块。"
  (interactive
   (list (completing-read "语言: " (mapcar #'car custom/org-babel-language-alist))))
  (insert (format "src_%s{}" language))
  (backward-char 1))

(provide 'org-babel)
;;; org-babel.el ends here
