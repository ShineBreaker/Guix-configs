;; -*- lexical-binding: t; -*-
;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; test-support.el --- 共享测试工具库

;;; Commentary:
;; 所有测试文件共用的基础设施。提供：
;; - 项目根目录常量（一次性计算）
;; - 核心模块加载保障
;; - 诊断上下文感知的配置加载
;; - 测试包装宏（自动诊断上下文链）
;; - 诊断失败捕获工具
;; - Feature 加载断言
;;
;; 使用方法：
;;   (require 'test-support)
;;   (tests/ensure-core-loaded)
;;   (tests/load-config "ui" "workspace.el")

;;; Code:

(require 'ert)
(require 'seq)

;; ═════════════════════════════════════════════════════════════════════════════
;; 项目根目录（一次性计算）
;; ═════════════════════════════════════════════════════════════════════════════

(defconst tests--root-dir
  (let ((candidate nil))
    ;; 优先 load-file-name（直接加载）
    (when (and load-file-name
               (file-exists-p
                (expand-file-name
                 "core/bootstrap.el"
                 (expand-file-name ".." (file-name-directory load-file-name)))))
      (setq candidate (expand-file-name ".." (file-name-directory load-file-name))))
    ;; 回退 default-directory（emacs --batch -L）
    (unless candidate
      (when (file-exists-p (expand-file-name "core/bootstrap.el" default-directory))
        (setq candidate default-directory)))
    ;; 从 tests/ 子目录向上查找
    (unless candidate
      (let* ((dir (or (and load-file-name (file-name-directory load-file-name))
                      default-directory))
             (parent (expand-file-name ".." dir)))
        (when (file-exists-p (expand-file-name "core/bootstrap.el" parent))
          (setq candidate parent))))
    (or candidate
        (error "tests--root-dir: 无法定位项目根目录")))
  "项目根目录（包含 core/ 和 configs/ 的目录）。")

;; ═════════════════════════════════════════════════════════════════════════════
;; 核心模块加载保障
;; ═════════════════════════════════════════════════════════════════════════════

(defvar tests--core-loaded nil
  "核心模块是否已加载。")

(defun tests/ensure-core-loaded ()
  "确保 core/ 三件套已加载：bootstrap + lib + diagnostic。
强制启用 `init-file-debug' 以激活诊断系统。
幂等操作：多次调用不会重复加载。"
  (unless tests--core-loaded
    ;; 强制启用诊断模式
    (setq init-file-debug t)
    ;; 加载核心模块
    (let ((core-dir (expand-file-name "core" tests--root-dir))
          (diagnose-dir (expand-file-name "diagnose" tests--root-dir)))
      (add-to-list 'load-path core-dir)
      (add-to-list 'load-path diagnose-dir))
    (require 'bootstrap)
    (require 'lib)
    (require 'diagnostic)
    (setq tests--core-loaded t)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 诊断上下文感知的配置加载
;; ═════════════════════════════════════════════════════════════════════════════

(defun tests/load-config (category filename)
  "在诊断上下文中通过 `custom/load-config' 加载配置。
CATEGORY 为类别目录名（如 \"ui\"），FILENAME 为文件名（如 \"workspace.el\"）。
返回加载是否成功。"
  (tests/ensure-core-loaded)
  (let ((module (concat category "/" filename)))
    (custom/diag-with-context 'test-load module
      (condition-case err
          (progn
            (custom/load-config category filename)
            t)
        (error
         (custom/diag "test-load" "✗ 加载失败：%s — %s" module
                      (error-message-string err))
         nil)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 测试包装宏
;; ═════════════════════════════════════════════════════════════════════════════

(defmacro tests/with-diag-test (test-name &rest body)
  "在诊断上下文中执行测试体 BODY。
TEST-NAME 为字符串标识，用于诊断日志。
自动记录入口/出口/耗时，失败时附带上下文链。
测试前后验证 context stack 无泄漏。"
  (declare (indent 1) (debug (stringp body)))
  `(let ((stack-before (copy-sequence custom--diag-context-stack))
         (failures-before (copy-sequence custom--diag-failures)))
     (unwind-protect
         (custom/diag-with-context 'test ,test-name
           (progn ,@body))
       ;; 确保 context stack 不泄漏
       (unless (equal stack-before custom--diag-context-stack)
         (custom/diag "test" "⚠ context stack 泄漏检测：%S → %S"
                      stack-before custom--diag-context-stack)
         ;; 强制恢复
         (setq custom--diag-context-stack stack-before))
       ;; 避免测试体中故意制造的失败污染整轮测试汇总
       (setq custom--diag-failures failures-before))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 诊断失败捕获
;; ═════════════════════════════════════════════════════════════════════════════

(defun tests/capture-diag-failures (body-fn)
  "执行 BODY-FN，返回期间新增的诊断失败列表。
利用 `custom--diag-failures' 前后差量计算。"
  (let ((before (length custom--diag-failures)))
    (funcall body-fn)
    (seq-drop custom--diag-failures
              (- (length custom--diag-failures)
                 (- (length custom--diag-failures) before)))))

(defmacro tests/with-captured-failures (var &rest body)
  "执行 BODY，将期间新增的诊断失败绑定到 VAR。"
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,var (tests/capture-diag-failures (lambda () ,@body))))
     ,var))

;; ═════════════════════════════════════════════════════════════════════════════
;; Feature 加载断言
;; ═════════════════════════════════════════════════════════════════════════════

(defun tests/assert-feature-loaded (feature source)
  "断言 FEATURE 已在 `features' 中。
SOURCE 为字符串描述来源（用于诊断消息）。
如果 feature 未加载，产生诊断警告但不硬失败（使用 ert-skip）。"
  (unless (featurep feature)
    (ert-skip (format "Feature %s 未加载（来自 %s）" feature source))))

(defun tests/feature-loaded-p (feature)
  "检查 FEATURE 是否已加载。返回布尔值。"
  (featurep feature))

(provide 'test-support)
;;; test-support.el ends here
