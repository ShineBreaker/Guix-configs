;;; block-replace.el —— 替换 Org 文件中单个 #+NAME 代码块的 body
;;;
;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;; SPDX-License-Identifier: MIT
;;;
;;; 由 blueprint.scm 的 blue block-replace 经 %run-elisp 调用：
;;;   emacs-minimal --script block-replace.el FILE NAME BODY-FILE OUT-FILE
;;; 把 FILE 中名为 NAME 的块 body 换成 BODY-FILE 的内容，结果写 OUT-FILE。
;;; stdout 打印 "lang=..."（外层据此对 scheme 块做括号验证）；
;;; 未找到块时打 [ERROR] 并以退出码 1 结束。

(let* ((file (nth 0 command-line-args-left))
       (name (nth 1 command-line-args-left))
       (body-file (nth 2 command-line-args-left))
       (out-file (nth 3 command-line-args-left))
       (new-body (with-temp-buffer
                   (insert-file-contents body-file)
                   (buffer-string))))
  (find-file file)
  (goto-char (point-min))
  (let (lang replaced)
    (when (re-search-forward
           (concat "^#[+]NAME:[[:space:]]+" (regexp-quote name) "[[:space:]]*$") nil t)
      (forward-line 1)
      (when (re-search-forward "^#[+]begin_src[[:space:]]+\\([^[:space:]\n]+\\)" nil t)
        (setq lang (match-string-no-properties 1))
        (forward-line 1)
        (let ((body-start (point)))
          (when (re-search-forward "^#[+]end_src" nil t)
            (delete-region body-start (line-beginning-position))
            (goto-char body-start)
            (insert (string-trim-right new-body "\n") "\n")
            (setq replaced t)))))
    (if replaced
        (progn
          (write-region (point-min) (point-max) out-file)
          (princ (format "lang=%s\n" (or lang ""))))
      (progn
        (princ (format "[ERROR] 未找到代码块 %s\n" name))
        (kill-emacs 1)))))
