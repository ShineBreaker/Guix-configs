;;; modules/55-completion.lisp — dabbrev 弹窗补全（M-/）
;;;
;;; lem 内置补全套件盘点（对齐用户 Emacs 的补全栈）：
;;;   - 弹窗 UI + 候选导航 = lem/completion-mode（run-completion 公开
;;;     API；LSP 补全即站其上；language-mode 里 Tab=缩进并补全、
;;;     C-M-i complete-symbol 手动触发；弹窗内 Tab 窄化/M-n M-p 上下/
;;;     Return 选中）；
;;;   - 本模块补缺：dabbrev（全 buffer 词候选），M-/ 触发——对齐用户
;;;     Emacs 的 M-/ cape-dabbrev（其补全链尾手动项）。
;;; 依赖：utils；lem/completion-mode 符号全部动态解析（该包未
;;; use-reexport 进 :lem，静态前缀引用会在编译期炸死进程）。

(in-package :lem-user)

(defparameter *vs-dabbrev-max-words* 1500
  "候选词总量上限（防大 buffer / 多 buffer 扫描失控）。")
(defparameter *vs-dabbrev-max-word-len* 64
  "超过此长度的「词」视为噪声（压缩串/二进制残片）丢弃。")

(defun vs-word-before-point (point)
  "取 point 前方的起补词；不足 2 字符不补（候选必然包含起词，无意义）。"
  (with-point ((p point))
    (skip-chars-backward p #'syntax-symbol-char-p)
    (let ((word (points-to-string p point)))
      (and (>= (length word) 2) word))))

(defun vs-buffer-words (buffer seen limit)
  "按出现顺序收集 buffer 内 symbol 词：seen 哈希去重、计数至 limit。"
  (let (words)
    (with-point ((p (buffer-start-point buffer)))
      (loop :while (and (< (hash-table-count seen) limit)
                        (not (end-buffer-p p)))
            :do (skip-chars-forward p (complement #'syntax-symbol-char-p))
                (let ((start (copy-point p :temporary)))
                  (skip-chars-forward p #'syntax-symbol-char-p)
                  (unless (point= start p)
                    (let ((w (points-to-string start p)))
                      (when (and (<= (length w) *vs-dabbrev-max-word-len*)
                                 (not (gethash w seen)))
                        (setf (gethash w seen) t)
                        (push w words))))))
      (nreverse words))))

(defun vs-dabbrev-candidates (point)
  "completion-spec 函数：全 buffer 词候选 → completion-item 列表。
当前 buffer 优先，其余按 buffer-list 顺序只收文件 buffer
（explorer/dashboard 等交互 buffer 的路径词是纯噪声）。"
  (let* ((word (vs-word-before-point point))
         (mk-item (vs$ :lem/completion-mode "MAKE-COMPLETION-ITEM")))
    (when (and word mk-item)
      (let ((seen (make-hash-table :test #'equal))
            (cur (point-buffer point))
            words)
        (setf (gethash word seen) t)
        (dolist (b (cons cur (remove cur (buffer-list) :test #'eq)))
          (when (and (< (hash-table-count seen) *vs-dabbrev-max-words*)
                     (or (eq b cur) (buffer-filename b)))
            (setf words
                  (nconc words (vs-buffer-words b seen *vs-dabbrev-max-words*)))))
        (mapcar (lambda (w) (funcall mk-item :label w)) words)))))

(define-command vs-dabbrev-complete () ()
  "M-/ dabbrev 补全：收集全 buffer 词弹窗补全。
候选空时静默（与 VSCode 补全无候选行为一致）。"
  (let ((run (vs$ :lem/completion-mode "RUN-COMPLETION"))
        (mk-spec (vs$ :lem/completion-mode "MAKE-COMPLETION-SPEC")))
    (if (and run mk-spec)
        (funcall run (funcall mk-spec #'vs-dabbrev-candidates))
        (message "lem/completion-mode 不可用，dabbrev 跳过"))))
