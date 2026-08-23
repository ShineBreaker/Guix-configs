;;; block-extract.el —— 从 Org 文件抽取单个 #+NAME 代码块
;;;
;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;; SPDX-License-Identifier: MIT
;;;
;;; 由 blueprint.scm 的 blue block-show 经 %run-elisp 调用：
;;;   emacs-minimal --script block-extract.el FILE NAME
;;; stdout 输出三段："lang\nnoweb|plain\n<body>"（body 已 trim 首尾换行），
;;; 未找到块时打 [ERROR] 并以退出码 1 结束。

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
