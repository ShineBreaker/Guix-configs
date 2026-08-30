;;; modules/45-keyhelp.lisp — 键位帮助页（which-key 替代）
;;;
;;; lem 2.3.0 全树 grep 零 which-key 类扩展，自研两层替代：
;;;   描述层 = 00-utils 注册表（vs-bind 落键时登记 分组+中文描述，
;;;            vs-help-note 收编不经 vs-bind 的默认键）；
;;;   展示层 = 本模块 F1 帮助页——渲染进可切换的只读 buffer
;;;            （不用 with-pop-up-typeout-window：其 floating-window
;;;            存活期间按移动键会在 MOVE-TO-VIRTUAL-LINE-COLUMN 上
;;;            以 column=NIL 炸 backtrace，E2E 实测）。
;;; 用户 Emacs 侧对应物是 custom/show-help（自制分组帮助页）+
;;; which-key 中文化，F1 键位与其 <f1> ? / C-c h ? 一致。
;;;
;;; 依赖：utils（注册表）；被 70-keybindings 依赖（本命令名供其绑 F1）。

(in-package :lem-user)

(defun vs-help-entries (group)
  "注册表中 group 分组的已注册键位（恢复注册顺序）。"
  (reverse
   (remove-if-not (lambda (e) (string= (third e) group))
                  *vs-binding-registry*)))

(defun vs-help-note-entries (group)
  "group 分组的附注键位（language-mode 默认键等）。"
  (reverse
   (remove-if-not (lambda (e) (string= (first e) group))
                  *vs-help-notes*)))

(defun vs-help-format-section (stream title entries)
  "渲染一个分组：标题线 + 键串(左对齐 20 列) → 描述。
描述为空时回落显示命令名，保证每行都有信息量。"
  (when entries
    (format stream "~% ── ~A ──────────────────────~%" title)
    (dolist (e entries)
      (let ((desc (if (plusp (length (fourth e)))
                      (fourth e)
                      (string-downcase (second e)))))
        (format stream "   ~20A ~A~%" (first e) desc)))))

(defun vs-help-render-buffer (buffer)
  "把分组键位渲染进 buffer（只读置位、光标回顶部）。
渲染与窗口切换分离：timer 自检可只调本函数。"
  (with-buffer-read-only buffer nil
    (erase-buffer buffer)
    (let ((stream (make-buffer-output-stream (buffer-point buffer))))
      (unwind-protect
           (progn
             (format stream "  键位帮助（lem / VSCode 复刻配置）~%")
             (dolist (g *vs-binding-groups*)
               (vs-help-format-section
                stream (second g)
                (nconc (vs-help-entries (first g))
                       (vs-help-note-entries (first g)))))
             (vs-help-format-section stream "其他" (vs-help-entries "other"))
             (format stream "~%   再按 F1 重开本页；C-x o 切回工作窗口。~%")
             (finish-output stream))
        (close stream))
      (setf (buffer-read-only-p buffer) t))
    (buffer-start (buffer-point buffer))
    (buffer-unmark buffer)))

(define-command vs-show-keybindings () ()
  "F1 键位帮助页：按分组列出全部自定义绑定与默认键附注（中文描述）。
对齐用户 Emacs 的 custom/show-help 自制帮助页；which-key 的逐前缀
idle 弹窗受 lem 命令循环限制不做，本页是完整静态替代。"
  (let ((buffer (or (get-buffer "*键位帮助*")
                    (make-buffer "*键位帮助*"))))
    (vs-help-render-buffer buffer)
    (switch-to-buffer buffer)))
