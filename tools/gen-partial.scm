;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;;; gen-partial.scm — via `guix repl gen-partial.scm TARGET OUT-FILE [COMMIT]`
;;; 在 guix 的 Guile 环境里生成单频道刷新的临时 channels 文件，避免 blue 的
;;; Guile 环境缺少 (guix openpgp)/(gcrypt hash) 等模块导致宏展开失败。
;;; 可选 COMMIT：目标频道 pin 到该 commit（(inherit ...) 函数式覆盖 commit
;;; 字段）；不传则目标保持 channel.scm 的可变定义，跟随 branch 最新。
(use-modules (guix channels) (guix build utils) (ice-9 match) (ice-9 pretty-print) (srfi srfi-1))

(define args (cdr (command-line)))
(unless (<= 2 (length args) 3)
  (format (current-error-port) "usage: guix repl ~a TARGET OUT-FILE [COMMIT]\n" (car (command-line)))
  (exit 1))
(define target (list-ref args 0))
(define out-file (list-ref args 1))
(define pin-commit (and (= (length args) 3) (list-ref args 2)))
(define repo-root (getcwd))
(define channel-scm (string-append repo-root "/source/channel.scm"))
(define channel-lock (string-append repo-root "/source/channel.lock"))

(define (%load-channels file)
  (save-module-excursion
   (lambda ()
     (let ([m (make-fresh-user-module)])
       (module-use! m (resolve-interface '(guix channels)))
       ;; guix openpgp 的 openpgp-fingerprint 宏在展开期需要 openpgp-fingerprint->bytevector
       (module-use! m (resolve-interface '(guix openpgp)))
       (set-current-module m)
       (primitive-load file)))))

(let* ([scm-ch (%load-channels channel-scm)]
       [lock-by (map (lambda (c) (cons (channel-name c) c)) (%load-channels channel-lock))]
       [names (delete-duplicates (map channel-name scm-ch))]
       [t (string->symbol target)]
       [pin-target (lambda (c)
                     (if (and pin-commit (eq? (channel-name c) t))
                         (channel (inherit c) (commit pin-commit))
                         c))])
  (unless (memq t names)
    (format (current-error-port) "update: 未知频道 ~a（可用：~a）\n" target (string-join (map symbol->string names) " "))
    (exit 1))
  (let ([merged
         (let loop ([rest scm-ch] [seen '()] [out '()])
           (match rest
             [() (reverse out)]
             [(c . r)
              (let ([n (channel-name c)])
                (if (memq n seen)
                    (loop r seen out)
                    (loop r (cons n seen)
                          (cons (pin-target
                                 (if (eq? n t) c (or (assq-ref lock-by n) c)))
                                out))))]))])
    (mkdir-p (dirname out-file))
    (call-with-output-file out-file
      (lambda (p) (pretty-print `(list ,@(map channel->code merged)) p)))
    (format #t "已生成单频道刷新文件 ~a（目标: ~a~a，其余 pin）\n"
            out-file target (if pin-commit (format #f " pin@~a" pin-commit) ""))))
