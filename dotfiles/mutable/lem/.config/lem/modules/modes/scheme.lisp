;;; modules/modes/scheme.lisp — Scheme/Guile（Guix 配置主力语言）
;;;
;;; scheme-mode 镜像内建（自带语法缩进 / REPL / swank 客户端，
;;; 文件类型 scm/sld/rkt/ss 自动关联）。LSP 走 guile-lsp-server。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-scheme-mode "SCHEME-MODE")
             "scheme"
             '(".git" "guix.scm" "hall.scm")
             '("guile-lsp-server"))

(vs-paredit (vs$ :lem-scheme-mode "SCHEME-MODE"))

;; Guix channel.lock 内容即 scheme（(list (channel ...) ...)），但 .lock
;; 后缀无 mode 关联、打开是 Fundamental（真机截图实测：注释与代码同色
;; 无高亮）。经 *find-file-hook*（buffer 单参，explorer 同款通道）补关联。
(defun vs-scheme-lock-hook (buffer)
  (ignore-errors
    (let ((file (buffer-filename buffer))
          (mode (vs$ :lem-scheme-mode "SCHEME-MODE"))
          (change (vs$ :lem "CHANGE-BUFFER-MODE")))
      (when (and file mode change
                 (let ((name (string-downcase file)))
                   (and (> (length name) 5)
                        (string= (subseq name (- (length name) 5)) ".lock"))))
        (funcall change buffer mode)))))

(let ((hook (vs$ :lem/buffer/file "*FIND-FILE-HOOK*")))
  (when hook
    (vs-hook-add hook 'vs-scheme-lock-hook)))
