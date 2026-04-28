;; -*- lexical-binding: t; -*-
;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; test-workspace-trigger.el --- 工作区自动布局触发回归测试

;;; Commentary:
;; 验证工作区状态管理函数和自动布局触发修复。
;; 使用 test-support 加载配置和诊断上下文包装。
;;
;; 运行方式（通过统一运行器）：
;;   emacs --batch -L . -L core -L configs -l tests/run-tests.el

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'test-support)

(tests/ensure-core-loaded)
(tests/load-config "ui" "workspace.el")

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 1：reset-state 清除所有标志
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-workspace-reset-state-clears-all-flags ()
  "调用 `custom--workspace-reset-state' 后，所有状态标志应为 nil。"
  :tags '(workspace trigger)
  (tests/with-diag-test "workspace-reset-state"
    (unwind-protect
        (progn
          ;; 先将所有标志设为非 nil
          (custom--workspace-set-state
           (list :active t
                 :initialized t
                 :transitioning t
                 :windows '((treemacs . "fake-window"))))
          (should (eq t (custom--workspace-layout-active-p)))
          (should (eq t (custom--workspace-layout-initialized-p)))
          (should (eq t (custom--workspace-transitioning-state-p)))
          (should (custom--workspace-windows-state))
          ;; 执行重置
          (custom--workspace-reset-state)
          ;; 验证全部清零
          (should-not (custom--workspace-layout-active-p))
          (should-not (custom--workspace-layout-initialized-p))
          (should-not (custom--workspace-transitioning-state-p))
          (should-not (custom--workspace-windows-state)))
      ;; 确保测试结束后状态干净
      (custom--workspace-reset-state))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 2：失效状态检测
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-workspace-stale-state-detection ()
  "当 :active=t 但窗口记录中没有 live window 时，状态应被判定为失效。"
  :tags '(workspace trigger)
  (tests/with-diag-test "workspace-stale-state"
    (unwind-protect
        (progn
          (custom--workspace-reset-state)
          ;; 场景 A：干净状态（active=nil）不应被判定为失效
          (should-not (custom--workspace-state-stale-p))
          ;; 场景 B：active=t 且无 live window → 失效
          (custom--workspace-set-state
           (list :active t
                 :initialized nil
                 :transitioning nil
                 :windows '((treemacs . "not-a-window")
                            (editor . nil))))
          (should (custom--workspace-state-stale-p))
          ;; 场景 C：active=t 且 windows=nil → 也应失效
          (custom--workspace-set-state
           (list :active t
                 :initialized nil
                 :transitioning nil
                 :windows nil))
          (should (custom--workspace-state-stale-p)))
      (custom--workspace-reset-state))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 3（关键回归测试）：:initialized 不被过早设置
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-workspace-initialized-not-set-prematurely ()
  "调用 `custom--trigger-layout-on-file' 后，:initialized 标志在 idle timer
触发前应保持 nil。这是修复 \"过早设置 :initialized 导致布局不再触发\"
的核心回归测试。"
  :tags '(workspace trigger)
  (tests/with-diag-test "workspace-initialized-not-premature"
    (let ((tmp-file (make-temp-file "ws-trigger-test-"))
          (initialized-after-call nil))
      (unwind-protect
          (progn
            (with-current-buffer (find-file-noselect tmp-file)
              (insert "workspace trigger regression test")
              (save-buffer))
            (custom--workspace-reset-state)
            ;; 在文件缓冲区中调用触发函数
            (with-current-buffer (get-file-buffer tmp-file)
              (should-not (custom--workspace-layout-initialized-p))
              (custom--trigger-layout-on-file)
              (setq initialized-after-call
                    (custom--workspace-layout-initialized-p)))
            ;; idle timer 尚未执行，initialized 不得被提前设置
            (should-not initialized-after-call))
        ;; 清理
        (custom--workspace-reset-state)
        (let ((buf (get-file-buffer tmp-file)))
          (when buf (kill-buffer buf)))
        (when (file-exists-p tmp-file)
          (delete-file tmp-file))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 4：transitioning 标志基本操作
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-workspace-transitioning-flag-basics ()
  "验证 `custom--workspace-set-transitioning' 和读写可靠性。"
  :tags '(workspace trigger)
  (tests/with-diag-test "workspace-transitioning-flag"
    (unwind-protect
        (progn
          (custom--workspace-reset-state)
          ;; 初始应为 nil
          (should-not (custom--workspace-transitioning-state-p))
          ;; 设置为 t
          (custom--workspace-set-transitioning t)
          (should (eq t (custom--workspace-transitioning-state-p)))
          ;; 恢复为 nil
          (custom--workspace-set-transitioning nil)
          (should-not (custom--workspace-transitioning-state-p))
          ;; 可靠性：反复切换
          (custom--workspace-set-transitioning t)
          (should (custom--workspace-transitioning-state-p))
          (custom--workspace-set-transitioning nil)
          (should-not (custom--workspace-transitioning-state-p)))
      (custom--workspace-reset-state))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 5：离开目标文件 buffer 后，不应继续自动创建布局
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-workspace-auto-layout-skips-hidden-target-buffer ()
  "若 idle timer 执行时目标文件 buffer 已不在当前 frame 可见，不应继续自动布局。"
  :tags '(workspace trigger)
  (tests/with-diag-test "workspace-auto-layout-skips-hidden-buffer"
    (let ((tmp-file (make-temp-file "ws-hidden-target-"))
          (target-buffer nil)
          (other-buffer nil)
          (layout-called nil))
      (unwind-protect
          (progn
            (setq target-buffer (find-file-noselect tmp-file))
            (with-current-buffer target-buffer
              (erase-buffer)
              (insert "hidden target buffer regression test")
              (save-buffer))
            (setq other-buffer (get-buffer-create "*workspace-hidden-target*"))
            (with-current-buffer other-buffer
              (special-mode))
            (custom--workspace-reset-state)
            (switch-to-buffer target-buffer)
            (switch-to-buffer other-buffer)
            (cl-letf (((symbol-function 'custom/ensure-workspace-layout)
                       (lambda (&rest _args)
                         (setq layout-called t))))
              (custom--workspace-run-auto-layout
               (selected-frame)
               target-buffer
               (buffer-local-value 'default-directory target-buffer))
              (should-not layout-called)))
        (custom--workspace-reset-state)
        (when (buffer-live-p other-buffer)
          (kill-buffer other-buffer))
        (when (buffer-live-p target-buffer)
          (kill-buffer target-buffer))
        (when (file-exists-p tmp-file)
          (delete-file tmp-file))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试 6：find-file hook 调度阶段不应过早要求 buffer 已可见
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-workspace-trigger-schedules-before-buffer-is-visible ()
  "在 `find-file-hook' 阶段，即使目标文件 buffer 尚未显示，也应先安排自动布局。"
  :tags '(workspace trigger)
  (tests/with-diag-test "workspace-trigger-schedules-before-visible"
    (let ((tmp-file (make-temp-file "ws-trigger-visible-"))
          (target-buffer nil)
          (other-buffer nil)
          (scheduled nil))
      (unwind-protect
          (progn
            (setq target-buffer (find-file-noselect tmp-file))
            (with-current-buffer target-buffer
              (erase-buffer)
              (insert "workspace scheduling regression test")
              (save-buffer))
            (setq other-buffer (get-buffer-create "*workspace-visible-check*"))
            (switch-to-buffer other-buffer)
            (custom--workspace-reset-state)
            (cl-letf (((symbol-function 'run-with-idle-timer)
                       (lambda (_secs _repeat function &rest args)
                         (setq scheduled (cons function args))
                         'fake-timer)))
              (with-current-buffer target-buffer
                (custom--trigger-layout-on-file))
              (should scheduled)
              (should (eq (caddr scheduled) target-buffer))))
        (custom--workspace-reset-state)
        (when (buffer-live-p other-buffer)
          (kill-buffer other-buffer))
        (when (buffer-live-p target-buffer)
          (kill-buffer target-buffer))
        (when (file-exists-p tmp-file)
          (delete-file tmp-file))))))

(provide 'test-workspace-trigger)
;;; test-workspace-trigger.el ends here
