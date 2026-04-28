;; -*- lexical-binding: t; -*-
;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; run-tests.el --- 统一诊断 + ERT 测试运行器

;;; Commentary:
;; 一站式诊断与测试入口。集成了 ERT 测试执行和配置诊断系统。
;;
;; 功能：
;; - 加载核心模块（bootstrap + lib + diagnostic）
;; - 强制启用诊断模式（测试始终在 --debug-init 等效环境下运行）
;; - 自动发现并加载 diagnose/test-*.el（排除 test-support.el）
;; - 执行 ERT 测试
;; - 输出完整诊断报告：
;;   1. 环境快照（Emacs 版本、系统、Guix 环境、GC 状态）
;;   2. 加载失败汇总（来自 diagnostic 系统）
;;   3. 已加载 features 清单
;;   4. Hook 统计
;;   5. Timer 清单
;;   6. 测试结果摘要
;;
;; 运行方式：
;;   emacs --batch -L . -L core -L diagnose -L configs -l diagnose/run-tests.el
;;
;; 退出码：0 = 全部通过，1 = 有失败

;;; Code:

(require 'ert)
(require 'seq)

;; ═════════════════════════════════════════════════════════════════════════════
;; 项目根目录
;; ═════════════════════════════════════════════════════════════════════════════

(defvar tests-runner--root-dir
  (or (when load-file-name
        (let* ((this-dir (file-name-directory (expand-file-name load-file-name)))
               (parent (expand-file-name ".." this-dir)))
          (when (file-exists-p (expand-file-name "core/bootstrap.el" parent))
            parent)))
      (when (file-exists-p (expand-file-name "core/bootstrap.el" default-directory))
        default-directory)
      (error "run-tests: 无法定位项目根目录"))
  "项目根目录。")

;; ═════════════════════════════════════════════════════════════════════════════
;; Phase 1: 加载核心模块
;; ═════════════════════════════════════════════════════════════════════════════

(defun tests--load-core ()
  "加载 core/ 三件套并强制启用诊断模式。"
  (message "═══════════════════════════════════════════════════════")
  (message "  统一诊断 + ERT 测试运行器")
  (message "═══════════════════════════════════════════════════════")
  ;; 强制启用诊断模式
  (setq init-file-debug t)
  (let ((core-dir (expand-file-name "core" tests-runner--root-dir))
        (diagnose-dir (expand-file-name "diagnose" tests-runner--root-dir)))
    (add-to-list 'load-path core-dir)
    (add-to-list 'load-path diagnose-dir))
  (message "[runner] 加载核心模块...")
  (require 'bootstrap)
  (require 'lib)
  (require 'diagnostic)
  (require 'test-support)
  (message "[runner] 核心模块加载完成"))

;; ═════════════════════════════════════════════════════════════════════════════
;; Phase 2: 发现并加载测试文件
;; ═════════════════════════════════════════════════════════════════════════════

(defun tests--discover-and-load ()
  "发现并加载 diagnose/test-*.el 文件（排除 test-support.el）。
返回加载的文件数量。"
  (let ((test-dir (expand-file-name "diagnose" tests-runner--root-dir))
        (count 0))
    (message "[runner] 发现测试文件...")
    (dolist (f (directory-files test-dir))
      (when (and (string-match "^test-.*\\.el$" f)
                 (not (string= f "test-support.el")))
        (let ((path (expand-file-name f test-dir)))
          (custom/diag-with-context 'test-file f
            (condition-case err
                (progn
                  (load path nil t)
                  (message "[runner] ✓ 已加载：%s" f)
                  (setq count (1+ count)))
              (error
               (message "[runner] ✗ 加载失败：%s — %s" f
                        (error-message-string err))))))))
    (message "[runner] 共加载 %d 个测试文件" count)
    count))

;; ═════════════════════════════════════════════════════════════════════════════
;; Phase 3: 诊断报告生成
;; ═════════════════════════════════════════════════════════════════════════════

(defun tests--report-hook-stats ()
  "输出关键 hook 的函数数量统计。"
  (message "\n── Hook 统计 ──")
  (dolist (hook-sym '(after-make-frame-functions
                      emacs-startup-hook
                      find-file-hook
                      server-switch-hook
                      kill-buffer-hook
                      delete-frame-functions))
    (when (boundp hook-sym)
      (let ((fns (if (listp (symbol-value hook-sym))
                     (symbol-value hook-sym)
                   (list (symbol-value hook-sym)))))
        (message "  %-30s %d 个函数" hook-sym (length fns))))))

(defun tests--report-timers ()
  "输出当前活跃 timer 清单。"
  (message "\n── Timer 清单 ──")
  (let ((timers timer-list)
        (idle-timers timer-idle-list)
        (count 0))
    (dolist (tmr timers)
      (when (timerp tmr)
        (setq count (1+ count))
        (message "  [periodic] %s repeat=%s"
                 (or (timer--function tmr) "<anonymous>")
                 (timer--repeat-delay tmr))))
    (dolist (tmr idle-timers)
      (when (timerp tmr)
        (setq count (1+ count))
        (message "  [idle] %s repeat=%s"
                 (or (timer--function tmr) "<anonymous>")
                 (timer--repeat-delay tmr))))
    (message "  共 %d 个活跃 timer" count)))

(defun tests--report-features ()
  "输出已加载的配置相关 features。"
  (message "\n── Features 清单 ──")
  (let ((config-features
         (seq-filter
          (lambda (f)
            (let ((name (symbol-name f)))
              (or (string-prefix-p "bootstrap" name)
                  (string-prefix-p "lib" name)
                  (string-prefix-p "diagnostic" name)
                  (string-prefix-p "test-" name))))
          features)))
    (message "  配置相关 features: %s" config-features))
  (message "  总计 %d 个 features" (length features)))

(defun tests--report-load-failures ()
  "输出诊断系统捕获的加载失败。"
  (if custom--diag-failures
      (progn
        (message "\n── 加载失败（来自诊断系统）──")
        (dolist (entry (reverse custom--diag-failures))
          (message "  ✗ %s | %s"
                   (plist-get entry :message)
                   (custom--diag-format-context-summary
                    (plist-get entry :contexts)))))
    (message "\n── 加载失败：无 ──")))

(defun tests--report-test-results (stats)
  "根据 ERT STATS 输出测试结果摘要。"
  (message "\n── 测试结果 ──")
  (let ((passed (ert-stats-completed-unexpected stats))
        (failed (ert-stats-completed-expected stats))
        (total (ert-stats-total stats)))
    ;; ERT 的统计方式：passed = 没有unexpected的，我们简单处理
    (message "  总计: %d 个测试" total)))

(defun tests--generate-diagnostic-report ()
  "生成完整诊断报告。"
  (message "\n")
  (message "═══════════════════════════════════════════════════════")
  (message "  诊断报告")
  (message "═══════════════════════════════════════════════════════")

  ;; 环境快照
  (message "\n── 环境快照 ──")
  (custom/diag-dump-env)

  ;; 加载失败
  (tests--report-load-failures)

  ;; Features
  (tests--report-features)

  ;; Hook 统计
  (tests--report-hook-stats)

  ;; Timer 清单
  (tests--report-timers)

  (message "\n═══════════════════════════════════════════════════════")
  (message "  诊断报告结束")
  (message "═══════════════════════════════════════════════════════"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 主入口
;; ═════════════════════════════════════════════════════════════════════════════

(defun tests/run-all ()
  "执行完整测试流程：加载 → 测试 → 诊断报告。"
  ;; Phase 1: 加载核心
  (tests--load-core)

  ;; Phase 2: 发现并加载测试文件
  (tests--discover-and-load)

  ;; Phase 3: 执行 ERT 测试
  (message "\n[runner] 执行 ERT 测试...")
  (message "───────────────────────────────────────────────────────")
  (let ((stats (ert-run-tests-batch)))
    (message "───────────────────────────────────────────────────────")

    ;; Phase 4: 诊断报告
    (tests--generate-diagnostic-report)

    ;; 退出码
    (if (zerop (ert-stats-completed-unexpected stats))
        (progn
          (message "\n✓ 全部测试通过")
          (kill-emacs 0))
      (message "\n✗ 存在失败的测试")
      (kill-emacs 1))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 自动执行
;; ═════════════════════════════════════════════════════════════════════════════

(when noninteractive
  (tests/run-all))

(provide 'tests-runner)
;;; run-tests.el ends here
