;;; block-extract.el --- 从 Org 文件抽取单个 #+NAME 代码块 -*- lexical-binding: t -*-
;;;
;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;; SPDX-License-Identifier: MIT
;;;
;;; 用法与输出协议：docs/scripts/org-block-tools.md（协议面向 blueprint.scm，勿改）

(let* ((file (nth 0 command-line-args-left))
       (name (nth 1 command-line-args-left))
       lang body has-noweb)
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (when (re-search-forward
           (concat "^#[+]NAME:[[:space:]]+" (regexp-quote name) "[[:space:]]*$") nil t)
      (forward-line 1)
      (when (re-search-forward "^#[+]begin_src[[:space:]]+\\([^[:space:]\n]+\\)" nil t)
        (setq lang (match-string-no-properties 1))
        (forward-line 1)
        (let ((body-start (point)))
          (when (re-search-forward "^#[+]end_src" nil t)
            (setq body (buffer-substring-no-properties
                        body-start (line-beginning-position)))
            (setq has-noweb (string-match-p "<<[^>]+>>" body))))))
    (unless body
      (princ (format "[ERROR] 未找到代码块 %s\n" name))
      (kill-emacs 1))
    (princ (format "%s\n%s\n" (or lang "") (if has-noweb "noweb" "plain")))
    (princ (string-trim body "\n" "\n")))
  (kill-emacs 0))
