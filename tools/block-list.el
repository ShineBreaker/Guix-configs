;;; block-list.el —— 一次性枚举 Org 文件中所有 #+NAME 代码块
;;;
;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;; SPDX-License-Identifier: MIT
;;;
;;; 由 blueprint.scm 的 blue check（%extract-all-blocks）经 %run-elisp 调用：
;;;   emacs-minimal --script block-list.el FILE
;;; 一次遍历导出全部命名块（避免每块起一个 emacs 进程），输出记录格式用
;;; >>> / <<< 作分隔，避免与 body 内任意文本冲突：
;;;   >>>name=<n>\tlang=<l>\tnoweb=plain|noweb
;;;   <body 第 1 行>
;;;   ...
;;;   <<<
;;; body 已 trim 首尾换行。与 block-extract.el / block-replace.el 共用同一套
;;; 正则风格，可对照阅读。

(let* ((file (nth 0 command-line-args-left))
       (name-re "^#[+]NAME:[[:space:]]+\\([^[:space:]\n]+\\)")
       (begin-re "^#[+]begin_src[[:space:]]+\\([^[:space:]\n]+\\)")
       (end-re "^#[+]end_src")
       name lang body-start has-noweb)
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (while (re-search-forward name-re nil t)
      (setq name (match-string-no-properties 1))
      (forward-line 1)
      (when (re-search-forward begin-re nil t)
        (setq lang (match-string-no-properties 1))
        (forward-line 1)
        (setq body-start (point))
        (when (re-search-forward end-re nil t)
          (let ((body (buffer-substring-no-properties
                       body-start (line-beginning-position))))
            (setq has-noweb (string-match-p "<<[^>]+>>" body))
            (princ (format ">>>name=%s\tlang=%s\tnoweb=%s\n"
                           name (or lang "")
                           (if has-noweb "noweb" "plain")))
            (princ (string-trim body "\n" "\n"))
            (princ "\n<<<\n"))))))
  (kill-emacs 0))
