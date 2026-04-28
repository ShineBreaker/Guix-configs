;; -*- lexical-binding: t; -*-
;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; test-diagnostic.el --- 诊断系统自测试

;;; Commentary:
;; 为 core/diagnostic.el 的核心 API 编写 ERT 回归测试。
;; 验证上下文链构建、失败记录、格式化输出、函数包装等核心功能。
;;
;; 运行方式（通过统一运行器）：
;;   emacs --batch -L . -L core -L configs -l tests/run-tests.el

;;; Code:

(require 'ert)
(require 'test-support)

(tests/ensure-core-loaded)

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 1：custom/diag 宏输出格式
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-diag-macro-output-format ()
  "验证 `custom/diag' 在 init-file-debug=t 时输出 [diag:CATEGORY] 格式消息。"
  :tags '(diagnostic core)
  (tests/with-diag-test "diag-macro-output-format"
    (let ((captured nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (push (apply #'format fmt args) captured))))
        (custom/diag "test-cat" "测试消息 %s" "arg1")
        (should (seq-some
                 (lambda (msg) (string-match "\\[diag:test-cat\\]" msg))
                 captured))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 2：custom/diag-with-context 构建上下文链
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-diag-with-context-builds-chain ()
  "验证嵌套调用 `custom/diag-with-context' 后 context stack 包含正确 kind/label。"
  :tags '(diagnostic core)
  (tests/with-diag-test "diag-context-chain"
    ;; 在诊断上下文中执行，验证栈在内部可见
    (let ((inner-contexts nil))
      (custom/diag-with-context 'outer "外层"
        (custom/diag-with-context 'inner "内层"
          (setq inner-contexts (copy-sequence custom--diag-context-stack))))
      ;; 应有 4 层：test + outer + inner（最内层执行时）
      ;; inner 执行时栈：test/outer(外层) -> outer/inner -> inner/内层
      (should (>= (length inner-contexts) 2))
      ;; 验证最内层有正确的 kind 和 label
      (let ((top (car inner-contexts)))
        (should (eq (plist-get top :kind) 'inner))
        (should (equal (plist-get top :label) "内层"))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 3：context stack 清理（无泄漏）
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-diag-with-context-stack-cleanup ()
  "验证 `custom/diag-with-context' 正常退出后 context stack 被正确 pop。"
  :tags '(diagnostic core)
  (tests/with-diag-test "diag-stack-cleanup"
    (let ((before (copy-sequence custom--diag-context-stack)))
      (custom/diag-with-context 'temp "临时上下文"
        ;; 内部时栈应该更深
        (should (> (length custom--diag-context-stack) (length before))))
      ;; 退出后栈应恢复
      (should (equal (length custom--diag-context-stack) (length before))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 4：custom/diag-with-context 捕获失败
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-diag-with-context-captures-failure ()
  "验证 `custom/diag-with-context' 内部错误被记录到 `custom--diag-failures'。"
  :tags '(diagnostic core)
  (tests/with-diag-test "diag-captures-failure"
    (let ((failures-before (length custom--diag-failures)))
      ;; 用 condition-case 捕获 error，避免传播到 ERT
      (condition-case _err
          (custom/diag-with-context 'failing "会失败的上下文"
            (error "测试用故意错误"))
        (error nil))
      ;; 验证新增了失败记录
      (should (> (length custom--diag-failures) failures-before))
      ;; 验证最新失败记录的内容
      (let ((latest (car custom--diag-failures)))
        (should (plist-get latest :time))
        (should (plist-get latest :message))
        (should (string-match "测试用故意错误"
                              (plist-get latest :message)))
        (should (plist-get latest :contexts))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 5：custom/diag-wrap-function 保留行为
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-diag-wrap-function-preserves-behavior ()
  "验证 `custom/diag-wrap-function' 包装器与原函数行为一致。"
  :tags '(diagnostic core)
  (tests/with-diag-test "diag-wrap-function"
    (let* ((call-count 0)
           (original (lambda (x)
                       (setq call-count (1+ call-count))
                       (* x 2)))
           (wrapped (custom/diag-wrap-function
                     'test "包装测试" original)))
      ;; 包装器应返回相同结果
      (should (= (funcall wrapped 5) 10))
      (should (= (funcall wrapped 3) 6))
      ;; 应调用了原函数
      (should (= call-count 2)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 6：custom--diag-format-context-summary 格式
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-diag-format-context-summary ()
  "验证 `custom--diag-format-context-summary' 生成 kind=label -> kind=label 格式。"
  :tags '(diagnostic core)
  (tests/with-diag-test "diag-format-summary"
    (let ((contexts (list (list :kind 'phase :label "system")
                          (list :kind 'module :label "startup.el")))
          (empty nil))
      ;; 有内容
      (let ((result (custom--diag-format-context-summary contexts)))
        (should (string-match "phase=system" result))
        (should (string-match "module=startup.el" result))
        (should (string-match " -> " result)))
      ;; 空内容
      (should (equal (custom--diag-format-context-summary empty)
                     "<无上下文>")))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 7：失败记录结构完整性
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-diag-record-failure-structure ()
  "验证失败记录包含 :time、:type、:message、:contexts、:backtrace 键。"
  :tags '(diagnostic core)
  (tests/with-diag-test "diag-failure-structure"
    (let ((failures-before (length custom--diag-failures)))
      (condition-case _err
          (custom/diag-with-context 'struct-test "结构测试"
            (error "结构验证错误"))
        (error nil))
      ;; 取最新失败
      (let ((entry (car custom--diag-failures)))
        (should (plist-get entry :time))
        (should (plist-get entry :type))
        (should (stringp (plist-get entry :message)))
        (should (plist-get entry :contexts))
        (should (stringp (plist-get entry :backtrace)))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 8：custom/diag-dump-env 不抛错
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-diag-dump-env-no-error ()
  "验证 `custom/diag-dump-env' 在任何环境下都不抛错。"
  :tags '(diagnostic core)
  (tests/with-diag-test "diag-dump-env"
    (should (not (null (custom/diag-dump-env))))))

(provide 'test-diagnostic)
;;; test-diagnostic.el ends here
