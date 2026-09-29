;;; block-replace.el --- 替换 Org 文件中单个 #+NAME 代码块的 body -*- lexical-binding: t -*-
;;;
;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;; SPDX-License-Identifier: MIT
;;;
;;; 用法与输出协议：docs/scripts/org-block-tools.md（协议面向 blueprint.scm，勿改）

(let* ((file (nth 0 command-line-args-left))
       (name (nth 1 command-line-args-left))
       (body-file (nth 2 command-line-args-left))
       (out-file (nth 3 command-line-args-left))
       (new-body (with-temp-buffer
                   (insert-file-contents body-file)
                   (buffer-string))))
  ;; 与另两个工具同款：temp buffer 读入，不 find-file——避免激活 org-mode
  ;; 与求值文件局部变量（output 只写 OUT-FILE，不回写 FILE）
  (with-temp-buffer
    (insert-file-contents file)
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
            ;; temp buffer 没有 buffer-file-coding-system（find-file 才有），
            ;; 显式绑 utf-8-unix，避免回退到 locale 默认编码
            (let ((coding-system-for-write 'utf-8-unix))
              (write-region (point-min) (point-max) out-file))
            (princ (format "lang=%s\n" (or lang ""))))
        (progn
          (princ (format "[ERROR] 未找到代码块 %s\n" name))
          (kill-emacs 1))))))
