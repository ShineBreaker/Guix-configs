;;; modules/46-problems.lisp — Problems 诊断面板（VSCode Problems 复刻）
;;;
;;; 依赖：utils（vs$ 动态解析）、icons（vs-icon severity 图标）、
;;;       explorer（Up/Down 纯点移动命令 vscode-explorer-next/previous-line
;;;       直接复用，40 必须先加载）、00 的 vs-help-note（帮助页收编）。
;;;       运行期软依赖 lsp-mode：全部 vs$ 动态解析，无 LSP 运行态时
;;;       显示空态不炸。被无模块依赖（叶子）。加载序：45 与 50 之间。
;;;
;;; C-M（物理 Ctrl+Shift+M，webview 到达形式=大写 sym 无 shift，见
;;; 70-keybindings 文件头键语法注）打开/刷新 *Problems* 只读 buffer
;;; （禁止 floating window：
;;; AGENTS.md 第 4 节 MOVE-TO-VIRTUAL-LINE-COLUMN 炸点；渲染型只读
;;; buffer 的 Up/Down 必须拦成纯点移动——照抄 40-explorer 尾部模式）。
;;; g/r 重扫诊断，Return/Space 跳到诊断文件:行:列。
;;;
;;; 上游对接（lem-next-2.3.0-0.68e85e0 源码核对，2026-08-31 git 构建）：
;;;   - :lem-lsp-mode BUFFER-DIAGNOSTIC-OVERLAYS：每 buffer 的诊断
;;;     overlay 列表。diagnostic struct 只有 buffer/position/message 三槽
;;;     ——severity 不入库，只体现在 overlay 的 attribute 上
;;;     （DIAGNOSTIC-{ERROR,WARNING,INFORMATION,HINT}-ATTRIBUTE 四档，
;;;     make-overlay 期 ensure-attribute 实例化为 attribute 对象，每次
;;;     实例化皆新对象、无 name 槽）。故 severity 用 lem-core 的
;;;     ATTRIBUTE-EQUAL 逐字段比较回推：ensure-color 查当前主题表是
;;;     确定性纯函数，同主题下逐字段相等可稳定区分四档；换主题后的
;;;     旧 overlay 失配降级为 information 档，不炸。
;;;   - 跳转：position 是 :lem/language-mode 的 xref-position（line-number
;;;     + charpos 两 internal 槽），move-to-line + line-offset 直达，
;;;     不依赖 language-mode 的跳转命令。
;;;   - 状态栏：lem-core MODELINE-ADD-STATUS-LIST 注册函数符号，modeline
;;;     渲染期经 convert-modeline-element 的 symbol 分支 symbol-function
;;;     调用，签名 (window) 返回 (values 字符串 attribute)。无诊断必须
;;;     返回空串——返回 nil 会被 princ-to-string 成 "NIL" 打上状态栏。
;;;     计数只在面板打开/刷新时重算（webview 前端 timer 不 fire，禁
;;;     轮询；modeline 函数只读缓存，每键重绘零开销）。

(in-package :lem-user)

;; --- attribute（只染色前景：本面板是 switch-to-buffer 的普通窗口
;;     buffer，背景跟随主题；不像 40 侧栏那样整行铺底色。
;;     浅色由 vscode-toggle-theme 经本函数重 skin） ---
(defun vs-problems-set-chrome (mode)
  "按 MODE（:dark/:light）重设问题面板 attribute 前景。
load 期以 :dark 调用（与旧顶层定义等价）；主题切换时由 30-themes 回调。"
  (let ((dark (eq mode :dark)))
    (define-attribute vs-problems-title
        (t :foreground (if dark "#CCCCCC" "#3B3B3B") :bold t))
    (define-attribute vs-problems-section
        (t :foreground (if dark "#9D9D9D" "#616161") :bold t))
    ;; VSCode problemsError/WarningForeground（light 取浅色对应值；
    ;; warning/info light 为 workbench light default）
    (define-attribute vs-problems-error
        (t :foreground (if dark "#F14C4C" "#F85149")))
    (define-attribute vs-problems-warning
        (t :foreground (if dark "#CCA700" "#BF8803")))
    (define-attribute vs-problems-info
        (t :foreground (if dark "#3794FF" "#1A85FF")))
    (define-attribute vs-problems-location
        (t :foreground (if dark "#9D9D9D" "#616161")))))
(vs-problems-set-chrome (if (boundp '*vs-theme-mode*) *vs-theme-mode* :dark))

;; --- 状态 ---
(defparameter *vs-problems-buffer-name* "*Problems*")
(defparameter *vs-problems-entries* nil
  "最近一次收集的诊断条目（plist 列表：:severity/:file/:line/:col/:message）。")
(defparameter *vs-problems-errors* 0 "状态栏计数缓存：面板刷新时重算。")
(defparameter *vs-problems-warnings* 0 "状态栏计数缓存：面板刷新时重算。")

;; severity 档位 → overlay attribute 符号（加载期解析一次；lsp-mode
;; 未加载时为 nil，该档永不命中）
(defparameter *vs-problems-severity-attrs*
  (list :error   (vs$ :lem-lsp-mode "DIAGNOSTIC-ERROR-ATTRIBUTE")
        :warning (vs$ :lem-lsp-mode "DIAGNOSTIC-WARNING-ATTRIBUTE")
        :information (vs$ :lem-lsp-mode "DIAGNOSTIC-INFORMATION-ATTRIBUTE")
        :hint    (vs$ :lem-lsp-mode "DIAGNOSTIC-HINT-ATTRIBUTE")))

(defun vs-problems-severity-rank (sev)
  "排序权重：Error 前 Warning 后，信息/提示殿后。"
  (ecase sev (:error 0) (:warning 1) (:information 2) (:hint 3)))

(defun vs-problems-overlay-severity (overlay-attr)
  "overlay 的 attribute 对象 → 四档 severity 关键字。
attribute-equal 内部对两边 ensure-attribute 后逐字段 equal，符号与
实例化对象皆可作第二参。识别失败（换主题后的陈旧 overlay 等）降级
information，绝不让上游异常炸进命令循环。"
  (let ((attr-equal (vs$ :lem-core "ATTRIBUTE-EQUAL")))
    (when attr-equal
      (dolist (pair *vs-problems-severity-attrs* :information)
        (when (cdr pair)
          (ignore-errors
           (when (funcall attr-equal overlay-attr (cdr pair))
             (return (car pair)))))))))

(defun vs-problems-collect ()
  "遍历全部 buffer 收集 LSP 诊断 overlay，输出按 severity 分档、段内
文件+行排序的条目列表，并更新状态栏 E/W 计数缓存。任一上游符号缺失
（无 LSP 运行态 / 扩展未加载）→ 返回 nil 空态。"
  (let ((overlays-fn (vs$ :lem-lsp-mode "BUFFER-DIAGNOSTIC-OVERLAYS"))
        (ov-attr (vs$ :lem-core "OVERLAY-ATTRIBUTE"))
        (ov-get  (vs$ :lem-core "OVERLAY-GET"))
        (diag-key (vs$ :lem-lsp-mode "DIAGNOSTIC"))
        (d-buffer (vs$ :lem-lsp-mode "DIAGNOSTIC-BUFFER"))
        (d-pos    (vs$ :lem-lsp-mode "DIAGNOSTIC-POSITION"))
        (d-msg    (vs$ :lem-lsp-mode "DIAGNOSTIC-MESSAGE"))
        (pos-line (vs$ :lem/language-mode "XREF-POSITION-LINE-NUMBER"))
        (pos-col  (vs$ :lem/language-mode "XREF-POSITION-CHARPOS"))
        entries)
    (when (and overlays-fn ov-attr ov-get diag-key
               d-buffer d-pos d-msg pos-line pos-col)
      (dolist (buffer (buffer-list))
        (dolist (ov (funcall overlays-fn buffer))
          (let* ((diag (funcall ov-get ov diag-key))
                 (src-buffer (and diag (funcall d-buffer diag)))
                 (pos (and diag (funcall d-pos diag))))
            (when (and diag src-buffer pos)
              (push (list :severity (or (vs-problems-overlay-severity
                                         (funcall ov-attr ov))
                                        :information)
                          :file (or (ignore-errors (buffer-filename src-buffer))
                                    (buffer-name src-buffer))
                          :line (funcall pos-line pos)
                          :col  (funcall pos-col pos)
                          :message (funcall d-msg diag))
                    entries))))))
    ;; severity 段内按 文件 → 行 排序（Error 前 Warning 后由 rank 保证）
    (setf entries
          (sort entries
                (lambda (a b)
                  (let ((sa (vs-problems-severity-rank (getf a :severity)))
                        (sb (vs-problems-severity-rank (getf b :severity))))
                    (if (= sa sb)
                        (if (string= (getf a :file) (getf b :file))
                            (< (getf a :line) (getf b :line))
                            (string-lessp (getf a :file) (getf b :file)))
                        (< sa sb)))))
          *vs-problems-entries* entries
          *vs-problems-errors*
          (count :error entries :key (lambda (e) (getf e :severity)))
          *vs-problems-warnings*
          (count :warning entries :key (lambda (e) (getf e :severity))))
    entries))

;; --- 渲染 ---
(defun vs-problems-entry-attribute (sev)
  (ecase sev
    (:error 'vs-problems-error)
    (:warning 'vs-problems-warning)
    ((:information :hint) 'vs-problems-info)))

(defun vs-problems-entry-icon (sev)
  ;; 20-icons 的 codicon 表无 info 档图标，信息/提示留白格
  (ecase sev
    (:error (string (vs-icon :error)))
    (:warning (string (vs-icon :warning)))
    ((:information :hint) " ")))

(defun vs-problems-insert-entry (point entry)
  "条目行：severity 图标 + 文件:行:列 + message；整行挂 :vs-item
跳转数据（40-explorer 同款属性模式）。message 内换行压成空格，
防多行消息破坏行级属性结构。"
  (let ((sev (getf entry :severity))
        (msg (substitute #\space #\newline
                         (or (getf entry :message) ""))))
    (insert-string point "  ")
    (insert-string point (vs-problems-entry-icon sev)
                   :attribute (vs-problems-entry-attribute sev))
    (insert-string point " ")
    (insert-string point (format nil "~A:~D:~D"
                                 (getf entry :file)
                                 (getf entry :line)
                                 (getf entry :col))
                   :attribute 'vs-problems-location)
    (insert-string point "  ")
    (insert-string point msg :attribute (vs-problems-entry-attribute sev))
    (with-point ((start point))
      (line-start start)
      (put-text-property start point :vs-item
                         (list :file (getf entry :file)
                               :line (getf entry :line)
                               :col (getf entry :col))))))

(defun vs-problems-render-buffer (buffer)
  "把 *vs-problems-entries*（collect 产物）渲染进只读 buffer。
渲染与收集分离（45-keyhelp 同款分层）。"
  (with-buffer-read-only buffer nil
    (erase-buffer buffer)
    (let ((point (buffer-point buffer)))
      (insert-string point "  问题 PROBLEMS" :attribute 'vs-problems-title)
      (insert-character point #\newline)
      (insert-string
       point
       (format nil "  ✖ ~D   ⚠ ~D" *vs-problems-errors* *vs-problems-warnings*)
       :attribute 'vs-problems-section)
      (insert-string point "    Return 跳转 · g 刷新" :attribute 'vs-problems-location)
      (insert-character point #\newline)
      (insert-character point #\newline)
      (if (null *vs-problems-entries*)
          (progn
            (insert-string point "  无诊断。" :attribute 'vs-problems-section)
            (insert-character point #\newline))
          (dolist (seg '((:error "错误") (:warning "警告")
                         (:information "信息") (:hint "提示")))
            (let ((items (remove (car seg) *vs-problems-entries*
                                 :key (lambda (e) (getf e :severity))
                                 :test-not #'eq)))
              (when items
                (insert-string
                 point (format nil "  ▼ ~A（~D）" (cadr seg) (length items))
                 :attribute 'vs-problems-section)
                (insert-character point #\newline)
                (dolist (e items)
                  (vs-problems-insert-entry point e)
                  (insert-character point #\newline)))))))
    (setf (buffer-read-only-p buffer) t)
    (buffer-start (buffer-point buffer))
    (buffer-unmark buffer)))

;; --- major mode + 键位（40/45 同款纪律：只读渲染行上放行 global 的
;;     next-line/previous-line 会在 virtual column=NIL 炸，Up/Down 拦成
;;     纯点移动——命令直接复用 40-explorer） ---
(defparameter *vs-problems-keymap* (make-keymap))

(define-major-mode vscode-problems-mode ()
    (:name "Problems"
     :keymap *vs-problems-keymap*)
  ;; mode 激活命令第一步 clear-editor-local-variables 会清掉 render 期
  ;; 置位的 read-only（ncurses 探针实测 read-only 被清回 NIL）——read-only
  ;; 必须在 mode body 里重设（40-explorer mode body 同款防线）。
  (setf (buffer-read-only-p (current-buffer)) t))

(defun vs-problems-item-at-point ()
  (text-property-at (back-to-indentation (current-point)) :vs-item))

(define-command vscode-problems-jump () ()
  "Return/Space：打开诊断所在文件并跳到 行:列（xref-position 直达）。"
  (let ((item (vs-problems-item-at-point)))
    (when item
      (handler-case
          (progn
            (find-file (getf item :file))
            (move-to-line (current-point) (max 1 (or (getf item :line) 1)))
            (line-offset (current-point) 0 (max 0 (or (getf item :col) 0))))
        (error (e)
          (message "Problems 跳转失败: ~A" e))))))

(define-command vscode-problems-refresh () ()
  "g/r：重扫全部 buffer 的 LSP 诊断并重绘面板（状态栏计数同步重算）。"
  (vs-problems-collect)
  (let ((buffer (get-buffer *vs-problems-buffer-name*)))
    (if buffer
        (vs-problems-render-buffer buffer)
        (message "Problems 面板未打开（C-M 开启，物理 Ctrl+Shift+M）"))))

(define-key *vs-problems-keymap* "Return" 'vscode-problems-jump)
(define-key *vs-problems-keymap* "Space" 'vscode-problems-jump)
(define-key *vs-problems-keymap* "g" 'vscode-problems-refresh)
(define-key *vs-problems-keymap* "r" 'vscode-problems-refresh)
(define-key *vs-problems-keymap* "Down" 'vscode-explorer-next-line)
(define-key *vs-problems-keymap* "Up" 'vscode-explorer-previous-line)

(define-command vs-problems-show () ()
  "C-M（物理 Ctrl+Shift+M）：打开/刷新 Problems 诊断面板（VSCode 同语义）。
无 LSP 运行态时显示空态；面板为可切换的只读 buffer（非浮窗）。"
  (vs-problems-collect)
  (let ((buffer (or (get-buffer *vs-problems-buffer-name*)
                    (make-buffer *vs-problems-buffer-name*))))
    (vs-problems-render-buffer buffer)
    (let ((change (vs$ :lem "CHANGE-BUFFER-MODE")))
      (when change
        (ignore-errors (funcall change buffer 'vscode-problems-mode))))
    (switch-to-buffer buffer)))

;; --- 状态栏 E/W 计数（modeline-add-status-list 注册函数符号） ---
(defun vs-modeline-diagnostics (window)
  "状态栏诊断计数段：只读 *vs-problems-*-count 缓存（面板打开/刷新时
重算）。无 E/W 返回空串——modeline-apply-1 对返回值 princ-to-string，
nil 会打出字面 \"NIL\"。"
  (declare (ignore window))
  (if (or (plusp *vs-problems-errors*) (plusp *vs-problems-warnings*))
      (values (format nil " ~C~D ~C~D "
                      (vs-icon :error) *vs-problems-errors*
                      (vs-icon :warning) *vs-problems-warnings*)
              'modeline-minor-modes-attribute)
      (values "" nil)))

(let ((add (vs$ :lem-core "MODELINE-ADD-STATUS-LIST")))
  (when add
    (funcall add 'vs-modeline-diagnostics)))

;; --- 全局键位 + 帮助页收编 ---
(vs-bind "C-M" :lem-user "VS-PROBLEMS-SHOW" "code" "问题面板（诊断列表，物理 Ctrl+Shift+M）")
(vs-help-note "code" "Return / Space" "跳转到诊断位置（Problems 面板内）")
(vs-help-note "code" "g / r" "重扫诊断列表（Problems 面板内）")
