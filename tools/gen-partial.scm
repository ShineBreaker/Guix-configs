;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; gen-partial.scm — 生成单频道刷新的临时 channels 文件
;; 必须经 `guix repl` 子进程跑：调用方（blueprint.scm 的 %partial-channels-file）
;; 的 Guile 环境缺 (guix openpgp)/(gcrypt hash)，openpgp-fingerprint 宏展开会
;; 报 unbound variable；guix 的 Guile 环境自带这些模块。
;; 文档：docs/scripts/gen-partial.md

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
       [by-name (lambda (n) (find (lambda (c) (eq? (channel-name c) n)) scm-ch))])
  (unless (memq t names)
    (format (current-error-port) "update: 未知频道 ~a（可用：~a）\n" target (string-join (map symbol->string names) " "))
    (exit 1))
  ;; 按 channel.scm 的频道顺序合并：目标频道用 channel.scm 定义（给了 COMMIT
  ;; 就 pin 到该 commit）；其余频道用 channel.lock 的锁定版本，lock 里缺席的
  ;; 回退到 channel.scm 定义。
  (let ([merged
         (map (lambda (n)
                (let ([c (if (eq? n t) (by-name n) (or (assq-ref lock-by n) (by-name n)))])
                  (if (and pin-commit (eq? n t))
                      (channel (inherit c) (commit pin-commit))
                      c)))
              names)])
    (mkdir-p (dirname out-file))
    (call-with-output-file out-file
      (lambda (p) (pretty-print `(list ,@(map channel->code merged)) p)))
    (format #t "已生成单频道刷新文件 ~a（目标: ~a~a，其余 pin）\n"
            out-file target (if pin-commit (format #f " pin@~a" pin-commit) ""))))
