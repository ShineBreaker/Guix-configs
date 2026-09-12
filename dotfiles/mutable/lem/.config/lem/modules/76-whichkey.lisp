;;; modules/76-whichkey.lisp — which-key 式前缀提示（自研，参考 Emacs which-key）
;;;
;;; 按下前缀键（C-x / C-c / M-g …）停留片刻后，底部弹出面板列出该前缀下
;;; 全部可用后续键与中文说明；继续按键完成序列后自动消失。交互语义对齐
;;; GNU Emacs which-key：延迟显示、列优先多列、前缀键串作标题。
;;;
;;; ── 设计 ────────────────────────────────────────────────────────────
;;;
;;; 挂点选 keymap-activate（而非 *input-hook*）：core 在 read-command 的
;;; 前缀等待循环里进入子 keymap 时调用（src/input.lisp:196-197），回根
;;; 时也调用（:drop 空 220、:cancel 237、叶子执行前 241）。因此「进入某
;;; 前缀」= 收到该子 keymap 对象，「序列结束/取消」= 收到 *root-keymap*，
;;; 无需自行维护 partial 序列状态机。keymap-activate 是 :lem-core 的
;;; generic，上游 transient 扩展对 (keymap keymap) 特化过；本模块在加载
;;; 期用运行时 eval 构造同特化 defmethod 将其替换——transient 不再接线
;;; （其描述层只能产出 +prefix/大写符号名，且 bottomside 窗口有 balance
;;; 回流副作用）。SBCL 会打 redefine warning 到 stderr，无害。
;;;
;;; 描述层唯一来源是 00-utils 的 *vs-binding-registry*（vs-bind 登记：
;;; 键串/命令名/分组/中文描述/命令符号）。core 无命令 docstring API
;;; （command 对象只有 name/source-location），故按命令符号反查注册表；
;;; 查不到回退符号名小写，保证面板永不空缺。
;;;
;;; 候选来源含 mode/global 合并：keymap-find 单键命中 mode 子树即返回
;;; （如 lisp-mode 自带 C-x C-e），但多键序列在 mode 子树 miss 时仍会
;;; 回退 global，故实际可达键 = mode 的该前缀子树 ∪ global 的同一前缀
;;; 子树（同名键 mode 覆盖）。vs-wk-global-subtree 用同一按键序列在
;;; *GLOBAL-KEYMAP* 上再查一次，非同一对象则合并（EQ 判定，已属 global
;;; 子树就不重复收集）。
;;;
;;; 防抖线程模型：keymap-activate 在按键循环内被同步调用，绝不允许阻塞
;;; 或抛错。收到前缀后立即返回，另起 sb-thread 短命线程 sleep
;;; *vs-whichkey-delay* 秒；醒后校验 epoch 未变才经 lem:send-event 把
;;; 渲染回调排回编辑线程。epoch 在每次 on-activate/hide 时自增，快速连续
;;; 按键（如在延迟内完成 C-x C-f）会让在途线程失效，不闪面板。渲染只在
;;; 编辑线程发生（后台线程仅 sleep + 读 epoch + 投递），buffer/window 无锁。
;;; 不用 make-timer：AGENTS §4 记录 webview 前端缺调度 tick，timer 不可靠。
;;;
;;; 渲染：自绘 buffer（*vs-which-key*，temporary + 只读）承载文本，浮窗
;;; （make-floating-window，贴屏幕底）承载显示。刻意避开 bottomside window
;;; （frame 单例 + balance-windows 回流）与 with-pop-up-typeout-window
;;; （聚焦后方向键炸点）。布局复刻 Emacs which-key：maxkey/maxdesc 按显示
;;; 宽度（string-width，中文字符宽 2）计算，itemw = maxkey+2+maxdesc+1，
;;; ncols 按 display-width 推算，列优先（column-major）填充；单列都放不下
;;; 时截断描述而非撑破屏幕。行内分段上色（键 vs-wk-key / 描述 vs-wk-desc /
;;; 填充 vs-wk-bg），整行补满 display-width。贴底锚点取 max(display-height,
;;; 平铺窗口区底行+1)：多 client 尺寸不一致时 display-height 会被改小、
;;; 窗口树仍按大尺寸布局，仅用 display-height 会让面板悬空露出下方 modeline
;;; （vs-wk-anchor-height）。
;;;
;;; ── 依赖 ────────────────────────────────────────────────────────────
;;;
;;; 00-utils 必须先行（vs$ / vs-warn / vs-trace）；70-keybindings 必须先行
;;; ——按键描述反查依赖 registry 已灌满（76 在 75 之后、90 之前加载，无缺口）。
;;; 主题：30-themes 先行，vscode-toggle-theme 追加一行 vs-whichkey-set-chrome
;;; 回调（与 explorer/problems/welcome 同模式）；本模块 load 期也自调一次。
;;; 全部上游符号经 vs$ 动态解析；任一关键符号缺失只 vs-warn 一次并整模块
;;; 降级（不 eval defmethod、不登记帮助），绝不影响其余配置加载。
;;;
;;; ── 已知取舍 ────────────────────────────────────────────────────────
;;;
;;; · function-table 绑定（define-key 以 symbol 作 keyspec，core 内 21 处）
;;;   不在 keymap-prefixes 里，故不枚举、不显示——which-key 会「漏键」，
;;;   与上游 describe-bindings/traverse-keymap 同病。
;;; · 不做分页：候选行数超 display-height-2 时窗口封顶，尾部被裁（无滚动键）。
;;; · 不做鼠标点击执行：面板 focusable nil，纯展示；点击由后续版本再议。
;;; · 嵌套 keymap 只展示一层（suffix 是 keymap 显示 "+ 描述"），不递归展开。

(in-package :lem-user)

;; --- attribute（跟随 40-explorer 的 set-chrome 模式：load-theme 不覆盖，
;;     浅色由 vscode-toggle-theme 经本函数重 skin） ---
(defun vs-whichkey-set-chrome (mode)
  "按 MODE（:dark/:light）重设 which-key 面板 attribute。
load 期以 *vs-theme-mode*（缺省 :dark）调用；主题切换时由 30-themes 回调。"
  (let ((dark (eq mode :dark))
        (bg (if (eq mode :dark) "#1F1F1F" "#F8F8F8")))
    (define-attribute vs-wk-bg
        (t :foreground (if dark "#CCCCCC" "#3B3B3B") :background bg))
    (define-attribute vs-wk-key
        (t :foreground (if dark "#4FC1FF" "#0451A5") :background bg :bold t))
    (define-attribute vs-wk-desc
        (t :foreground (if dark "#CCCCCC" "#3B3B3B") :background bg))
    (define-attribute vs-wk-title
        (t :foreground (if dark "#9D9D9D" "#616161") :background bg :bold t))))
(vs-whichkey-set-chrome (if (boundp '*vs-theme-mode*) *vs-theme-mode* :dark))

;; --- 状态 ---
(defparameter *vs-whichkey-delay* 0.4
  "前缀按下到面板显示的防抖秒数（Emacs which-key-echo-delay 对应物）；0 立即。")
(defparameter *vs-wk-send-event* (vs$ :lem "SEND-EVENT")
  "lem:send-event（把回调排回编辑线程执行）；加载期解析一次。")
(defparameter *vs-wk-buffer* nil "面板 buffer（temporary，二次显示复用）。")
(defparameter *vs-wk-window* nil "面板浮窗句柄（nil = 未显示）。")
(defparameter *vs-wk-pending-km* nil
  "待显示前缀 keymap；on-activate 写入，vs-wk-show（编辑线程）读取。")
(defvar *vs-wk-epoch* 0
  "防抖代际：on-activate/hide 自增，在途线程醒后比对不一致即放弃。")
(defvar *vs-wk-desc-cache* (make-hash-table :test 'eq)
  "命令符号 → 中文描述；registry 长度变化时整体重建。")
(defvar *vs-wk-cache-len* -1 "desc-cache 构建时的 registry 条数。")

;; --- 动态解析辅助 ---
(defun vs-wk-callable (pkg name)
  "解析 PKG 内 NAME 的函数符号；缺失返回 nil（vs$ 命中缓存，热路径廉价）。"
  (let ((sym (vs$ pkg name)))
    (and sym (fboundp sym) sym)))

(defun vs-wk-class (pkg name)
  "解析 PKG 内 NAME 的类符号；不是类则返回 nil（class 符号无 fboundp）。"
  (let ((sym (vs$ pkg name)))
    (and sym (ignore-errors (find-class sym nil)) sym)))

(defun vs-wk-typep (obj class)
  "容忍 CLASS 为 nil（符号缺失时不误炸 typep）。"
  (and class (typep obj class)))

(defun vs-wk-display-width ()
  (or (ignore-errors (funcall (vs-wk-callable :lem "DISPLAY-WIDTH"))) 80))

(defun vs-wk-display-height ()
  (or (ignore-errors (funcall (vs-wk-callable :lem "DISPLAY-HEIGHT"))) 24))

(defun vs-wk-anchor-height ()
  "面板贴底基准高度（字符行）：1 + max(display-height-1, 平铺窗口区底行)。
窗口区底行由 (window-list (current-frame)) 的最后一行取最大值。多 client
以不同尺寸登录时 display-height 会被后来的尺寸改小，而窗口树仍按大尺寸
布局（实测 display-height=43 而 tile 底行=45），仅按 display-height 定位
会让面板悬空、下方露出窗口 modeline。两者一致时结果与 display-height 相同；
window-list 解析失败时回退 display-height。"
  (let ((wl (vs-wk-callable :lem-core "WINDOW-LIST"))
        (cf (vs-wk-callable :lem-core "CURRENT-FRAME"))
        (wy (vs-wk-callable :lem-core "WINDOW-Y"))
        (wh (vs-wk-callable :lem-core "WINDOW-HEIGHT"))
        (bottom (max 0 (1- (vs-wk-display-height)))))
    (when (and wl cf wy wh)
      (dolist (w (ignore-errors (funcall wl (ignore-errors (funcall cf)))))
        (let ((y (ignore-errors (funcall wy w)))
              (h (ignore-errors (funcall wh w))))
          (when (and (integerp y) (integerp h) (> (+ y h -1) bottom))
            (setf bottom (+ y h -1))))))
    (1+ bottom)))

(defun vs-wk-sw (s)
  "字符串显示宽度（中文字符 = 2 列）。"
  (or (ignore-errors (funcall (vs-wk-callable :lem "STRING-WIDTH") s))
      (length s)))

(defun vs-wk-root ()
  "*ROOT-KEYMAP* 对象（special variable，需 symbol-value 解引用）。"
  (let ((sym (vs$ :lem-core "*ROOT-KEYMAP*")))
    (and sym (boundp sym) (symbol-value sym))))

(defun vs-wk-global-keymap ()
  "*GLOBAL-KEYMAP* 对象（special variable，需 symbol-value 解引用）；
缺失返回 nil。global-mode 的 keymap，位于 keymap-find 优先级末位。"
  (let ((sym (vs$ :lem-core "*GLOBAL-KEYMAP*")))
    (and sym (boundp sym) (symbol-value sym))))

(defun vs-wk-keymap-find ()
  "KEYMAP-FIND 泛型函数符号；先 :lem 后 :lem-core，缺失返回 nil。
缺失只跳过候选合并，不作模块级硬依赖（vs-whichkey-install 不校验它）。"
  (or (vs-wk-callable :lem "KEYMAP-FIND")
      (vs-wk-callable :lem-core "KEYMAP-FIND")))

;; --- registry 描述反查 ---
(defun vs-wk-ensure-desc-cache ()
  "registry 条数变化时重建符号→描述表。"
  (let ((len (length *vs-binding-registry*)))
    (unless (eql len *vs-wk-cache-len*)
      (clrhash *vs-wk-desc-cache*)
      (dolist (e *vs-binding-registry*)
        (let ((sym (fifth e)) (desc (fourth e)))
          (when (and sym (symbolp sym) (stringp desc) (plusp (length desc)))
            (setf (gethash sym *vs-wk-desc-cache*) desc))))
      (setf *vs-wk-cache-len* len))))

(defun vs-wk-desc-for-symbol (sym)
  "命令符号 → 中文描述。registry 符号与 keymap 中 prefix-suffix 理应为同一
eq 符号（vs-bind 用 vs$ 解析后 define-key），eq 命中；若实测包/字符串化
差异导致未命中，降级按 symbol-name string= 匹配，再回退符号名小写。"
  (or (gethash sym *vs-wk-desc-cache*)
      (let ((name (and (symbolp sym) (symbol-name sym))))
        (when name
          (maphash (lambda (k v)
                     (when (string= (symbol-name k) name)
                       (return-from vs-wk-desc-for-symbol v)))
                   *vs-wk-desc-cache*)))
      (and (symbolp sym) (string-downcase sym))))

;; --- 候选收集 ---
(defun vs-wk-key-string (k)
  "prefix-key → 显示键串；宽空格键 \"Space\" 译 \"SPC\"。函数式键不可
表示（core define-key 恒为 key 结构，此分支只作防御）返回 nil。"
  (when (and k (not (functionp k)))
    (let ((s (princ-to-string k)))
      (if (string= s "Space") "SPC" s))))

(defun vs-wk-desc-of (p &optional (depth 0))
  "prefix P 的描述：symbol→registry 反查/小写名；keymap→\"+ 描述\"；
  prefix→取其 suffix 递归一次（depth 防环）。"
  (let ((s (ignore-errors (funcall (vs-wk-callable :lem-core "PREFIX-SUFFIX") p))))
    (cond
      ((null s) "?")
      ((vs-wk-typep s (vs-wk-class :lem "KEYMAP"))
       (let* ((kdf (vs-wk-callable :lem-core "KEYMAP-DESCRIPTION"))
              (d (and kdf (ignore-errors (funcall kdf s)))))
         (format nil "+ ~A" (or (and d (stringp d) (plusp (length d)) d) "prefix"))))
      ((and (< depth 1) (vs-wk-typep s (vs-wk-class :lem-core "PREFIX")))
       (vs-wk-desc-of s (1+ depth)))
      ((symbolp s) (or (vs-wk-desc-for-symbol s) (string-downcase s)))
      (t (format nil "~A" s)))))

(defun vs-wk-global-subtree (km)
  "KM 不在 *GLOBAL-KEYMAP* 树上时，返回当前按键序列在 global 树上对应的
子 keymap（供候选合并）；KM 本就是 global 子树、键序列不可得或解析失败
返回 nil。判定用 EQ：keymap-find 返回的 suffix 与 KM 同一对象即无需合并。

背景：keymap-find 对 children 逐个尝试，单键命中 mode 子树即返回；多键
序列在 mode 子树 miss 时才回退后续 child（含 global）。因此按 C-x 后
实际可达键 = mode 的 C-x 子树 ∪ global 的 C-x 子树（同名键 mode 覆盖）。"
  (let ((gk (vs-wk-global-keymap))
        (kf (vs-wk-keymap-find))
        (kseq (vs-wk-kseq))
        (keymap-class (vs-wk-class :lem "KEYMAP"))
        (skf (vs-wk-callable :lem-core "PREFIX-SUFFIX")))
    (when (and gk kf kseq skf keymap-class)
      (let* ((prefix (ignore-errors (funcall kf gk kseq)))
             (sub (and prefix (ignore-errors (funcall skf prefix)))))
        (when (and (vs-wk-typep sub keymap-class)
                   (not (eq sub km)))
          sub)))))

(defun vs-wk-candidates (km &optional (base (vs-wk-current-keys-string)))
  "收集 KM 及其 keymap-base 继承链上的可用绑定，返回 ((键串 . 描述) …)
按键串 string< 排序。派生层先收集，同键串只保留最先出现者（覆盖语义）。
prefix-active-p 为 nil 的跳过。BASE 是当前序列串（如 \"C-x\"），用于
子前缀条目查 *vs-wk-prefix-names* 的完整键映射。

mode 遮蔽合并：KM 若非 global 子树，再收集 *GLOBAL-KEYMAP* 上同一键
序列的子 keymap（vs-wk-global-subtree），两步共用 seen 表——mode 层
先收集故同键串以 mode 优先。global 树与 keymap-find 解析失败则跳过
合并，退化为仅 KM 链（不告警、不影响其余功能）。"
  (vs-wk-ensure-desc-cache)
  (let ((seen (make-hash-table :test 'equal))
        (out '())
        (keymap-class (vs-wk-class :lem "KEYMAP"))
        (kpf (vs-wk-callable :lem-core "KEYMAP-PREFIXES"))
        (kbf (vs-wk-callable :lem-core "KEYMAP-BASE"))
        (pkf (vs-wk-callable :lem-core "PREFIX-KEY"))
        (paf (vs-wk-callable :lem-core "PREFIX-ACTIVE-P")))
    (labels ((collect (start)
               (loop for cur = start then (ignore-errors (funcall kbf cur))
                     while (and cur (vs-wk-typep cur keymap-class))
                     do (dolist (p (ignore-errors (funcall kpf cur)))
                          (let ((ks (vs-wk-key-string
                                     (ignore-errors (funcall pkf p)))))
                            (when (and ks (not (gethash ks seen))
                                       (ignore-errors (funcall paf p)))
                              (setf (gethash ks seen) t)
                              (push (cons ks
                                          (or (and base ks
                                                   (cdr (assoc (format nil "~A ~A"
                                                                        base ks)
                                                               *vs-wk-prefix-names*
                                                               :test #'string=)))
                                              (ignore-errors (vs-wk-desc-of p))
                                              "?"))
                                    out)))))))
      (when (and km keymap-class kpf kbf pkf paf)
        (collect km)
        (let ((gkm (vs-wk-global-subtree km)))
          (when gkm (collect gkm)))))
    (sort out #'string< :key #'car)))

;; --- 渲染 ---
(defun vs-wk-truncate (s width)
  "把 S 截断到显示宽度 WIDTH（宽字符按 2 列计）。"
  (if (or (null s) (<= (vs-wk-sw s) width))
      s
      (let ((idx (ignore-errors
                   (funcall (vs-wk-callable :lem "WIDE-INDEX") s width))))
        (subseq s 0 (or idx (length s))))))

(defun vs-wk-pad (point target col)
  "从显示列 COL 补空格到 TARGET（整行底色），返回新列。"
  (let ((pad (- target col)))
    (when (plusp pad)
      (insert-string point (make-string pad :initial-element #\space)
                     :attribute 'vs-wk-bg)
      (incf col pad)))
  col)

(defun vs-wk-current-keys-string ()
  "当前按键序列字符串（this-command-keys → keyseq-to-string）；
解析失败返回 nil。标题与子前缀映射（*vs-wk-prefix-names*）共用。"
  (let* ((keys (ignore-errors
                 (funcall (vs-wk-callable :lem "THIS-COMMAND-KEYS"))))
         (s (and keys (ignore-errors
                        (funcall (vs-wk-callable :lem "KEYSEQ-TO-STRING")
                                 keys)))))
    (and s (stringp s) (plusp (length s)) s)))

(defun vs-wk-kseq ()
  "当前按键序列（this-command-keys → key 对象列表，含当前前缀键）。
keymap-find 接受单个 key 或 key 列表；空序列/解析失败返回 nil。"
  (let ((keys (ignore-errors
                (funcall (vs-wk-callable :lem "THIS-COMMAND-KEYS")))))
    (and (consp keys) keys)))

(defun vs-wk-title-string ()
  "标题 = 当前按键序列 + 提示；序列不可得时省略标题行。"
  (let ((s (vs-wk-current-keys-string)))
    (and s (format nil "~A — 按后续键或 Esc 取消" s))))

(defparameter *vs-wk-prefix-names*
  '(("C-x 4" . "其他窗口")
    ("C-x p" . "项目")
    ("C-x 4 p" . "项目（其他窗口）")
    ("C-c C-d" . "查符号（Lisp）"))
  "上游子前缀 keymap 的中文名。上游 keymap-description 未设时面板
显示「+ prefix」；按完整键序列（当前序列 + 相对键）在此兜底。")

(defparameter *vs-whichkey-keymap* (make-keymap)
  "面板局部 keymap（面板不可聚焦、不绑定键，仅占位）。")

(define-major-mode vs-whichkey-mode ()
    (:name "Which-Key"
     :keymap *vs-whichkey-keymap*)
  (setf (variable-value 'line-wrap :buffer (current-buffer)) nil)
  (setf (buffer-read-only-p (current-buffer)) t))

(defun vs-wk-ensure-buffer ()
  (unless (and *vs-wk-buffer*
               (ignore-errors (buffer-name *vs-wk-buffer*)))
    (setf *vs-wk-buffer*
          (funcall (vs-wk-callable :lem "MAKE-BUFFER")
                   "*vs-which-key*" :temporary t :enable-undo-p nil))
    (funcall (vs-wk-callable :lem "CHANGE-BUFFER-MODE")
             *vs-wk-buffer* 'vs-whichkey-mode))
  *vs-wk-buffer*)

(defun vs-wk-render (cands)
  "把 CANDS 渲染进面板 buffer；返回 (values 高度 宽度)。
Emacs which-key 布局：itemw = maxkey+2+maxdesc+1，ncols 由 display-width
推算，列优先填充；单列都放不下时截断描述到 (- width maxkey 3)。"
  (let* ((width (max 3 (vs-wk-display-width)))
         (maxkey (max 1 (reduce #'max cands :key (lambda (c) (vs-wk-sw (car c))))))
         (maxdesc (max 1 (reduce #'max cands :key (lambda (c) (vs-wk-sw (cdr c))))))
         (raw-cols (floor (max 1 (1- width))
                          (+ maxkey 2 maxdesc 1)))
         (ncols (max 1 raw-cols))
         (nrows (ceiling (length cands) ncols)))
    (when (zerop raw-cols)
      (setf maxdesc (max 1 (- width maxkey 3))))
    (let ((buffer (vs-wk-ensure-buffer))
          (title (vs-wk-title-string))
          (itemw (+ maxkey 2 maxdesc 1))
          (height 0))
      (with-buffer-read-only buffer nil
        (erase-buffer buffer)
        (let ((point (buffer-point buffer)))
          (when title
            (let* ((tstr (vs-wk-truncate title width)))
              (insert-string point tstr :attribute 'vs-wk-title)
              (vs-wk-pad point width (vs-wk-sw tstr))
              (insert-character point #\newline)))
          (dotimes (r nrows)
            (let ((col 0))
              (dotimes (c ncols)
                (let ((item (nth (+ (* c nrows) r) cands)))
                  (when item
                    (let ((base (* c itemw))
                          (k (vs-wk-truncate (car item) maxkey))
                          (d (vs-wk-truncate (cdr item) maxdesc)))
                      (insert-string point k :attribute 'vs-wk-key)
                      (setf col (+ base (vs-wk-sw k)))
                      (setf col (vs-wk-pad point (+ base maxkey) col))
                      (insert-string point "  " :attribute 'vs-wk-bg)
                      (setf col (+ col 2))
                      (insert-string point d :attribute 'vs-wk-desc)
                      (setf col (+ col (vs-wk-sw d)))
                      (setf col (vs-wk-pad point (+ base maxkey 2 maxdesc) col))
                      (insert-string point " " :attribute 'vs-wk-bg)
                      (setf col (1+ col))))))
              (vs-wk-pad point width col)
              (insert-character point #\newline)))
          (setf height (max 2 (min (+ nrows (if title 1 0))
                                   (max 2 (- (vs-wk-anchor-height) 2)))))))
      (values height width))))

;; --- 窗口 ---
(defun vs-wk-ensure-window (height width)
  "建/复用贴底浮窗；句柄失效（被外部删除）则重建。"
  (let ((w *vs-wk-window*)
        (delp (vs-wk-callable :lem-core "DELETED-WINDOW-P")))
    (when (and w delp (ignore-errors (funcall delp w)))
      (setf w nil *vs-wk-window* nil))
    (if w
        (progn
          (ignore-errors
            (funcall (vs-wk-callable :lem-core "WINDOW-SET-POS")
                     w 0 (- (vs-wk-anchor-height) height)))
          (ignore-errors
            (funcall (vs-wk-callable :lem-core "WINDOW-SET-SIZE")
                     w width height))
          w)
        (setf *vs-wk-window*
              (funcall (vs-wk-callable :lem "MAKE-FLOATING-WINDOW")
                       :buffer *vs-wk-buffer* :x 0
                       :y (- (vs-wk-anchor-height) height)
                       :width width :height height
                       :use-modeline-p nil)))))

;; --- 显示 / 隐藏 ---
(defun vs-wk-hide ()
  "收起面板并取消在途防抖（epoch+1）。无窗口时不 redraw（叶子命令每次都
会收到 root activate，避免每命令无谓重绘）。"
  (incf *vs-wk-epoch*)
  (when *vs-wk-window*
    (ignore-errors
      (funcall (vs-wk-callable :lem "DELETE-WINDOW") *vs-wk-window*))
    (setf *vs-wk-window* nil)
    (ignore-errors
      (funcall (vs-wk-callable :lem "REDRAW-DISPLAY")))))

(defun vs-wk-show ()
  "编辑线程渲染回调：候选为空则收起，否则渲染 + 建/复用窗口 + 重绘。"
  (handler-case
      (let ((cands (and *vs-wk-pending-km*
                        (vs-wk-candidates *vs-wk-pending-km*))))
        (if (null cands)
            (vs-wk-hide)
            (multiple-value-bind (height width) (vs-wk-render cands)
              (when (and height width (>= width 3) (>= height 2))
                (vs-wk-ensure-window height width)
                (ignore-errors
                  (funcall (vs-wk-callable :lem "REDRAW-DISPLAY")))))))
    (error (e) (vs-trace "76-whichkey: show 失败: ~A" e))))

;; --- 挂点 ---
(defun vs-whichkey-on-activate-inner (km)
  (if (or (eq km (vs-wk-root))
          (null (vs-wk-candidates km)))
      (vs-wk-hide)
      (progn
        (setf *vs-wk-pending-km* km)
        (incf *vs-wk-epoch*)
        (let ((epoch *vs-wk-epoch*)
              (send *vs-wk-send-event*))
          (sb-thread:make-thread
           (lambda ()
             (sleep *vs-whichkey-delay*)
             (when (and send (= epoch *vs-wk-epoch*))
               (funcall send #'vs-wk-show)))
           :name "vs-whichkey-debounce")))))

(defun vs-whichkey-on-activate (km)
  "keymap-activate 替换方法：在 read-command 按键循环内同步调用，任何错误
只记 vs-trace 后静默，绝不打断按键处理。"
  (handler-case
      (vs-whichkey-on-activate-inner km)
    (error (e) (vs-trace "76-whichkey: on-activate 错误: ~A" e))))

(defun vs-wk-present-p (pkg name)
  "加载期能力探测：KEYMAP/PREFIX 是类（无 fboundp），*ROOT-KEYMAP* 是
special variable，其余为函数。"
  (cond ((or (string= name "KEYMAP") (string= name "PREFIX"))
         (vs-wk-class pkg name))
        ((string= name "*ROOT-KEYMAP*")
         (let ((s (vs$ pkg name)))
           (and s (boundp s) s)))
        (t (vs-wk-callable pkg name))))

(defun vs-whichkey-install ()
  "能力探测 + 替换 keymap-activate 的同特化方法。缺符号只告警降级。"
  (let ((missing
         (loop for (pkg . name)
               in '((:lem-core . "KEYMAP-ACTIVATE")
                    (:lem . "KEYMAP")
                    (:lem-core . "PREFIX")
                    (:lem-core . "PREFIX-KEY")
                    (:lem-core . "PREFIX-SUFFIX")
                    (:lem-core . "PREFIX-ACTIVE-P")
                    (:lem-core . "KEYMAP-PREFIXES")
                    (:lem-core . "KEYMAP-BASE")
                    (:lem-core . "KEYMAP-DESCRIPTION")
                    (:lem-core . "*ROOT-KEYMAP*")
                    (:lem . "MAKE-FLOATING-WINDOW")
                    (:lem-core . "WINDOW-SET-POS")
                    (:lem-core . "WINDOW-SET-SIZE")
                    (:lem-core . "DELETED-WINDOW-P")
                    (:lem . "MAKE-BUFFER")
                    (:lem . "CHANGE-BUFFER-MODE")
                    (:lem . "DELETE-WINDOW")
                    (:lem . "REDRAW-DISPLAY")
                    (:lem . "DISPLAY-WIDTH")
                    (:lem . "DISPLAY-HEIGHT")
                    (:lem . "STRING-WIDTH")
                    (:lem . "WIDE-INDEX")
                    (:lem . "KEYSEQ-TO-STRING")
                    (:lem . "THIS-COMMAND-KEYS")
                    (:lem . "SEND-EVENT"))
               unless (vs-wk-present-p pkg name)
                 collect name)))
    (if missing
        (progn
          (vs-warn (list :lem-user "which-key 依赖缺失，模块降级" missing))
          nil)
        (let ((gf (vs$ :lem-core "KEYMAP-ACTIVATE"))
              (km-class (vs$ :lem "KEYMAP")))
          (eval `(defmethod ,gf ((km ,km-class))
                   (vs-whichkey-on-activate km)))
          (vs-trace "76-whichkey: keymap-activate 方法已替换，面板就绪")
          t))))

;; 加载期接线：此刻 70-keybindings 已落完全部 vs-bind，registry 完整。
(if (vs-whichkey-install)
    (vs-help-note "ui" "前缀键停留"
                  "底部弹出可用后续键位面板（which-key）")
    (vs-warn '(:lem-user "VS-WHICHKEY 未接线")))
