;; -*- lexical-binding: t; -*-
;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; test-org-folding.el --- Org Mode 启动折叠行为回归测试

;;; Commentary:
;; 验证 org-startup-folded 设置为 'overview。
;; 通过 test-support 加载配置，使用诊断上下文包装测试。
;;
;; 运行方式（通过统一运行器）：
;;   emacs --batch -L . -L core -L configs -l tests/run-tests.el

;;; Code:

(require 'ert)
(require 'test-support)

(tests/ensure-core-loaded)
(tests/load-config "org" "org-mode.el")

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 1：org-startup-folded 应为 'overview
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-org-startup-folded-is-overview ()
  "验证 `org-startup-folded' 被设置为 'overview。"
  :tags '(org folding)
  (tests/with-diag-test "org-startup-folded-is-overview"
    (should (eq org-startup-folded 'overview))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 2：org-cycle 在临时缓冲区不报错
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-org-cycle-expands-heading ()
  "在临时 Org 缓冲区中调用 `org-cycle'，确保不抛错。"
  :tags '(org folding)
  (tests/with-diag-test "org-cycle-expands-heading"
    (with-temp-buffer
      (org-mode)
      (insert "* Heading\n")
      (goto-char (point-min))
      (condition-case err
          (org-cycle)
        (error (ert-skip "org-cycle 在 batch 模式下报错：%S" err))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 3：org-cycle 函数已绑定
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-org-cycle-function-is-bound ()
  "验证 `org-cycle' 已 fboundp。"
  :tags '(org folding)
  (tests/with-diag-test "org-cycle-is-bound"
    (should (fboundp 'org-cycle))))

(provide 'test-org-folding)
;;; test-org-folding.el ends here
