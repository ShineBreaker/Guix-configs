;;; diagnostic-context.el --- 诊断上下文管理 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 诊断系统的核心：上下文栈管理、失败捕获、debugger 集成。
;; 提供 `custom/diag-with-context' 和 `custom/diag-wrap-function'。

;;; Code:

(require 'diagnostic-state)

;; ═════════════════════════════════════════════════════════════════════════════
;; 上下文栈辅助函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--diag-context-indent ()
  "根据当前上下文栈深度返回缩进字符串。"
  (make-string (* 2 (length custom--diag-context-stack)) ?\s))

(defun custom--diag-describe-callable (callable)
  "返回 CALLABLE 的可读描述。"
  (cond
   ((symbolp callable) (symbol-name callable))
   ((byte-code-function-p callable) "<byte-code>")
   ((subrp callable) (format "%s" callable))
   ((functionp callable) "<lambda>")
   (t (format "%S" callable))))

(defun custom--diag-internal-path-p (path)
  "判断 PATH 是否属于当前配置仓库。"
  (and path
       (boundp 'custom:emacs-dir)
       (stringp custom:emacs-dir)
       (string-prefix-p (expand-file-name custom:emacs-dir)
                        (expand-file-name path))))

(defun custom--diag-timer-noisy-p (label)
  "判断 timer LABEL 是否属于高频噪音。"
  (seq-some (lambda (pattern)
              (string-match-p pattern label))
            custom--diag-noisy-timer-patterns))

(defun custom--diag-record-suppressed-timer (label)
  "聚合记录被抑制的 timer LABEL。"
  (puthash label (1+ (gethash label custom--diag-suppressed-timers 0))
           custom--diag-suppressed-timers))

(defun custom--diag-should-log-timer-p (label)
  "判断当前是否应输出 timer LABEL 的即时日志。"
  (or custom--diag-enable-timer-trace
      custom--diag-verbose
      (string-match-p "custom[-/]" label)))

(defun custom--diag-extract-condition (debugger-args)
  "从 DEBUGGER-ARGS 中提取 `error-message-string' 可接受的错误对象。"
  (cond
   ((and (>= (length debugger-args) 2)
         (consp (cadr debugger-args)))
    (cadr debugger-args))
   ((and debugger-args
         (consp (car debugger-args)))
    (car debugger-args))
   (t (list 'error (format "未知 debugger 参数: %S" debugger-args)))))

(defun custom--diag-capture-backtrace ()
  "捕获当前 debugger 环境中的真实 backtrace。"
  (with-temp-buffer
    (let ((standard-output (current-buffer)))
      (backtrace))
    (buffer-string)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 上下文格式化
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--diag-format-context-summary (contexts)
  "将 CONTEXTS 格式化为单行上下文链。"
  (if contexts
      (mapconcat
       (lambda (context)
         (format "%s=%s"
                 (plist-get context :kind)
                 (plist-get context :label)))
       contexts
       " -> ")
    "<无上下文>"))

(defun custom--diag-format-context-block (contexts)
  "将 CONTEXTS 格式化为多行块。"
  (if contexts
      (mapconcat
       (lambda (context)
         (let ((file (plist-get context :file)))
           (format "- %s: %s%s"
                   (plist-get context :kind)
                   (plist-get context :label)
                   (if file
                       (format " [%s]" file)
                     ""))))
       contexts
       "\n")
    "- <无上下文>"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 失败记录
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--diag-write-failure-report (entry)
  "将失败 ENTRY 追加到 *Init Diagnostics* 缓冲区。"
  (let ((buf (get-buffer-create "*Init Diagnostics*"))
        (inhibit-read-only t))
    (with-current-buffer buf
      (special-mode)
      (goto-char (point-max))
      (unless (= (point) (point-min))
        (insert "\n"))
      (insert (format "===== Failure @ %s =====\n" (plist-get entry :time)))
      (insert (format "Type: %s\n" (plist-get entry :type)))
      (insert (format "Message: %s\n" (plist-get entry :message)))
      (insert (format "Load file: %s\n"
                      (or (plist-get entry :load-file) "<未知>")))
      (insert "Context chain:\n")
      (insert (custom--diag-format-context-block (plist-get entry :contexts)))
      (insert "\n\nBacktrace:\n")
      (insert (or (plist-get entry :backtrace) "<无 backtrace>")))))

(defun custom--diag-record-failure (condition contexts backtrace)
  "记录 CONDITION 对应的失败信息。
CONTEXTS 为当前上下文栈快照，BACKTRACE 为原始 backtrace 字符串。"
  (let ((entry (list :time (current-time-string)
                     :type (car-safe condition)
                     :message (error-message-string condition)
                     :load-file load-file-name
                     :contexts contexts
                     :backtrace backtrace)))
    (push entry custom--diag-failures)
    (custom--diag-write-failure-report entry)
    (message "[init:error] %s" (plist-get entry :message))
    (message "[init:error] 上下文链: %s"
             (custom--diag-format-context-summary contexts))
    (message "[init:error] 详细报告: *Init Diagnostics*")))

(defun custom--diag-record-current-failure (condition)
  "按当前上下文栈记录 CONDITION，对同一错误只入账一次。"
  (unless custom--diag-error-recorded
    (custom--diag-record-failure
     condition
     (reverse custom--diag-context-stack)
     (custom--diag-capture-backtrace))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 诊断 debugger
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--diag-debugger (parent-debugger &rest diag-debugger-args)
  "记录诊断信息后，继续交给 PARENT-DEBUGGER 处理 DIAG-DEBUGGER-ARGS。"
  (if custom--diag-debugger-active
      (let ((debugger parent-debugger))
        (if (functionp parent-debugger)
            (apply parent-debugger diag-debugger-args)
          (apply #'debug diag-debugger-args)))
    (let ((custom--diag-debugger-active t))
      (condition-case diag-err
          (custom--diag-record-current-failure
           (custom--diag-extract-condition diag-debugger-args))
        (error
         (message "[init:error] 诊断器自身出错: %s"
                  (error-message-string diag-err))))
      (let ((debugger parent-debugger))
        (if (functionp parent-debugger)
            (apply parent-debugger diag-debugger-args)
          (apply #'debug diag-debugger-args))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 上下文执行
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--diag-run-with-context (kind label thunk &optional quiet)
  "以 KIND/LABEL 上下文执行 THUNK。
仅在 `init-file-debug' 为非 nil 时建立上下文链并绑定诊断 debugger。"
  (if (not init-file-debug)
      (funcall thunk)
    (let* ((indent (custom--diag-context-indent))
           (outermost-context (null custom--diag-context-stack))
           (entry (list :kind kind
                        :label label
                        :file load-file-name))
           (start-time (current-time))
           (completed nil)
           (parent-debugger debugger))
      (push entry custom--diag-context-stack)
      (unless quiet
        (message "[diag:%s] %s→ %s" kind indent label))
      (unwind-protect
          (let ((debug-on-error t)
                (debugger (if outermost-context
                              (lambda (&rest args)
                                (apply #'custom--diag-debugger parent-debugger args))
                            debugger)))
            (condition-case err
                (prog1 (funcall thunk)
                  (setq completed t)
                  (unless quiet
                    (message "[diag:%s] %s← %s (%.3fs)"
                             kind indent label
                             (float-time (time-subtract (current-time) start-time)))))
              (error
               (custom--diag-record-current-failure err)
               (let ((custom--diag-error-recorded t))
                 (signal (car err) (cdr err))))))
        (unless (or completed quiet)
          (message "[diag:%s] %s✗ %s (%.3fs)"
                   kind indent label
                   (float-time (time-subtract (current-time) start-time))))
        (pop custom--diag-context-stack)))))

(defmacro custom/diag-with-context (kind label &rest body)
  "在 KIND/LABEL 上下文中执行 BODY。
仅在 `init-file-debug' 为非 nil 时启用上下文链、失败报告与原始 backtrace 捕获。"
  (declare (indent 2) (debug (sexp sexp body)))
  `(if init-file-debug
       (custom--diag-run-with-context ,kind ,label (lambda () ,@body))
     (progn ,@body)))

(defmacro custom--diag-with-quiet-context (kind label &rest body)
  "在 KIND/LABEL 上下文中静默执行 BODY。"
  (declare (indent 2) (debug (sexp sexp body)))
  `(if init-file-debug
       (custom--diag-run-with-context ,kind ,label (lambda () ,@body) t)
     (progn ,@body)))

(defun custom--diag-wrap-function-internal (kind label function quiet)
  "根据 QUIET 为 FUNCTION 创建上下文包装器。"
  (if (not init-file-debug)
      function
    (lambda (&rest args)
      (if quiet
          (custom--diag-with-quiet-context kind label
            (apply function args))
        (custom/diag-with-context kind label
          (apply function args))))))

(defun custom/diag-wrap-function (kind label function)
  "为 FUNCTION 返回一个 debug-only 的 KIND/LABEL 上下文包装器。"
  (custom--diag-wrap-function-internal kind label function nil))

(provide 'diagnostic-context)
;;; diagnostic-context.el ends here
