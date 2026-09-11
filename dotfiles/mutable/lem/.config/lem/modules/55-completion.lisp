;;; modules/55-completion.lisp — dabbrev 弹窗补全（M-/）
;;;
;;; lem 内置补全套件盘点（对齐用户 Emacs 的补全栈）：
;;;   - 弹窗 UI + 候选导航 = lem/completion-mode（run-completion 公开
;;;     API；LSP 补全即站其上；language-mode 里 Tab=缩进并补全、
;;;     C-M-i complete-symbol 手动触发；弹窗内 Tab 窄化/M-n M-p 上下/
;;;     Return 选中）；
;;;   - 本模块补缺：dabbrev（全 buffer 词候选），M-/ 触发——对齐用户
;;;     Emacs 的 M-/ cape-dabbrev（其补全链尾手动项）。
;;; 候选管线：收集 → 过滤+排序（vs-dabbrev-filter-sort：前缀命中先于
;;; 子串命中，同档稳定保持收集序）→ completion-item。上游 run-completion
;;; 不做任何前缀过滤（completion-mode 源码确认，spec 返回什么就显示
;;; 什么），过滤/排序只能在配置侧做。大小写策略：匹配大小写不敏感
;;; （对齐 dabbrev case-fold 语义，ALPHAbet 可被 alp 命中）；插入不做
;;; case 改写——上游 completion-insert 为原样替换目标词（delete-between
;;; + insert-string label，源码确认），候选词词形天然保持。
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

(defun vs-dabbrev-filter-sort (prefix words)
  "过滤+排序：仅保留含 prefix 的词（大小写不敏感），前缀命中（词首
即 prefix）档在前、子串命中档在后，同档稳定保持收集序（buffer 内
出现序；跨 buffer 时当前 buffer 段先于其余文件 buffer 段）。
push 收集须 nreverse 还原收集序，stable-sort 才有「同档保序」可言。"
  (let ((tiered '()))
    (dolist (w words)
      (let ((pos (search prefix w :test #'char-equal)))
        (when pos
          (push (cons (if (zerop pos) 0 1) w) tiered))))
    (mapcar #'cdr (stable-sort (nreverse tiered) #'< :key #'car))))

(defun vs-dabbrev-candidates (point)
  "completion-spec 函数：全 buffer 词候选 → completion-item 列表。
过滤为含起补词的词并排序（前缀命中先于子串命中，同档保持收集序，
见 vs-dabbrev-filter-sort）；当前 buffer 优先，其余按 buffer-list
顺序只收文件 buffer（explorer/dashboard 等交互 buffer 的路径词是
纯噪声）。候选必须是 make-completion-item 对象（字符串列表会在
插入时炸，AGENTS 第 3 节）。"
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
        (mapcar (lambda (w) (funcall mk-item :label w))
                (vs-dabbrev-filter-sort word words))))))

(define-command vs-dabbrev-complete () ()
  "M-/ dabbrev 补全：收集全 buffer 词弹窗补全。
候选空时静默（与 VSCode 补全无候选行为一致）。"
  (let ((run (vs$ :lem/completion-mode "RUN-COMPLETION"))
        (mk-spec (vs$ :lem/completion-mode "MAKE-COMPLETION-SPEC")))
    (if (and run mk-spec)
        (funcall run (funcall mk-spec #'vs-dabbrev-candidates))
        (message "lem/completion-mode 不可用，dabbrev 跳过"))))

;; --- 键入即弹补全（VSCode quickSuggestions 的对应物） ---
;; 上游 LSP 已接 trigger 字符（. : 等）自动补全；本段补「普通词字符」
;; 通道：self-insert-after-hook（edit.lisp 的 editor variable，全局默认
;; 值挂一次即对所有 buffer 生效——buffer-local 值是 cons 到全局值上，
;; 见 lsp-mode add-buffer-hooks 同款机制）。
;; 触发条件：插入的是 symbol 字符 + buffer 可写 + 无补全弹窗在飞。
;; 补全源：LSP buffer 用其 completion-spec（async，不阻塞编辑线程）；
;; 非 LSP buffer 用 dabbrev 的 async 包装（async spec 恒走弹窗分支，
;; 规避 sync spec 的「单候选直接插入」——自动补全绝不能擅自改文本）。
;; 起补词 <3 字符不弹（vs-dabbrev-candidates 的 <2 门槛之外再收一档，
;; 对齐 VSCode 的噪声控制）。
(defparameter *vs-auto-suggest-min* 3
  "自动补全的起补词最小长度。")

(defun vs-auto-suggest-dabbrev (point then)
  "dabbrev 的 async spec 适配器：同步收集后经 then 回调投递。"
  (funcall then (vs-dabbrev-candidates point)))

(defun vs-auto-suggest (char)
  "self-insert-after-hook 回调：词字符键入后弹补全。
热路径守卫全部廉价（symbol 判定 + 两个变量读），不满足即返回。"
  (ignore-errors
    (when (and (characterp char)
               (syntax-symbol-char-p char)
               (not (buffer-read-only-p (current-buffer))))
      (let ((ctx (vs$ :lem/completion-mode "*COMPLETION-CONTEXT*")))
        (unless (and ctx (boundp ctx) (symbol-value ctx))
          (let* ((word (vs-word-before-point (current-point)))
                 (spec-var (vs$ :lem/language-mode "COMPLETION-SPEC"))
                 (spec (and spec-var
                            (ignore-errors (variable-value spec-var))))
                 (run (vs$ :lem/completion-mode "RUN-COMPLETION"))
                 (mk-spec (vs$ :lem/completion-mode "MAKE-COMPLETION-SPEC")))
            (when (and word (>= (length word) *vs-auto-suggest-min*)
                       run mk-spec)
              (if spec
                  (funcall run spec)
                  (funcall run (funcall mk-spec #'vs-auto-suggest-dabbrev
                                        :async t))))))))))

(let ((hook-var (or (vs$ :lem "SELF-INSERT-AFTER-HOOK")
                    (vs$ :lem-core/commands/edit "SELF-INSERT-AFTER-HOOK"))))
  (when hook-var
    (eval `(add-hook (variable-value ',hook-var :global t)
                     'vs-auto-suggest))))
