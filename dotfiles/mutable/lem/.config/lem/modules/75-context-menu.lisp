;;; modules/75-context-menu.lisp — 右键命令菜单（VSCode 右键语义的配置侧实现）
;;;
;;; 上游菜单内容管线无注册点（BUFFER-CONTEXT-MENU 普通函数默认 NIL；
;;; DISPLAY-POPUP-MENU 的 ITEMS 元素无公开构造子，v29-v36 探针结论），
;;; 此处自研：右键点击弹 prompt-for-string 过滤菜单（F1 transient 同款
;;; 浮窗，见 45-keyhelp），列上下文命令、选中执行。全部条目引用已验证
;;; 存在的命令，缺失只告警跳过（vs$ 动态解析）。
;;;
;;; 上下文感知（:when 谓词槽）：条目可带 :when 谓词符号，每次弹出时
;;; 于当前 buffer/region/killring 状态求值，返回 NIL 即隐藏——无效条目
;;; 不进菜单。谓词内部只依赖 vs$ 动态解析的 API，符号缺失一律失败开放
;;; （宁可多显示一个可能无效的条目，也不藏起能用的）；谓词本体报错视
;;; 同隐藏（菜单永远开得出来）。region 判定无 REGION-ACTIVE-P 可用
;;; （0.68e85e0 源码 grep + 探针双确认），走 BUFFER-MARK-P（mark 的
;;; active 位）+ BUFFER-MARK 与 BUFFER-POINT 的 POINT= 比对（空选区
;;; 不算激活）；killring 是 lem-core 内部对象，公开路径 CURRENT-KILLRING
;;; + PEEK-KILLRING-ITEM。
;;;
;;; 依赖：utils（vs$ / vs-warn / vs-bind）、keybindings（分组声明先行，
;;; 本模块借其 "editor" 分组登记）、keyhelp（复用 vs-transient-filter
;;; 做浮窗过滤，45 先于 75 加载）；被 60-editor-config 依赖（右键
;;; around 调本命令）。加载序 70 之后、90 之前，文件名前缀 75 即位置。

(in-package :lem-user)

(defun vs-ctx-file-buffer-p ()
  "当前 buffer 关联文件（保存等文件类条目的前提）。
buffer-filename 返回 namestring 或 NIL（AGENTS 语义坑已录）；
API 缺失失败开放。"
  (let ((cb (vs$ :lem "CURRENT-BUFFER"))
        (bf (vs$ :lem "BUFFER-FILENAME")))
    (if (and cb bf)
        (ignore-errors (and (funcall bf (funcall cb)) t))
        t)))

(defun vs-ctx-language-buffer-p ()
  "文件 buffer 且 major mode 非 Fundamental——跳转定义/查找引用/
重命名符号/代码操作类 LSP 条目的可用前提（dashboard/scratch/帮助页
等非文件 buffer 上这些命令必报错）。mode 名不可解析时退化为
file-buffer 判定（失败开放）。"
  (and (vs-ctx-file-buffer-p)
       (let ((cb (vs$ :lem "CURRENT-BUFFER"))
             (bm (vs$ :lem "BUFFER-MAJOR-MODE"))
             (mn (vs$ :lem "MODE-NAME")))
         (if (and cb bm mn)
             (ignore-errors
               (let ((name (funcall mn (funcall bm (funcall cb)))))
                 (and (stringp name)
                      (not (string-equal name "Fundamental")))))
             t))))

(defun vs-ctx-region-active-p ()
  "选区激活：mark 激活且 mark≠point（空选区不算，免得 C-Space 一下
就冒出无效的剪切/复制）。API 缺失失败开放。"
  (let ((cb (vs$ :lem "CURRENT-BUFFER"))
        (bmp (vs$ :lem "BUFFER-MARK-P"))
        (bmk (vs$ :lem "BUFFER-MARK"))
        (bp (vs$ :lem "BUFFER-POINT"))
        (peq (vs$ :lem "POINT=")))
    (if (and cb bmp bmk bp peq)
        (ignore-errors
          (let ((b (funcall cb)))
            (and (funcall bmp b)
                 (let ((mk (funcall bmk b)))
                   (and mk (not (funcall peq mk (funcall bp b))))))))
        t)))

(defun vs-ctx-killring-nonempty-p ()
  "killring 顶部有非空条目（粘贴才有意义）。剪贴板启用时 yank 另有
来源（yank-from-clipboard-or-killring），此判定偏保守；API 缺失
失败开放。"
  (let ((ck (vs$ :lem-core "CURRENT-KILLRING"))
        (pk (vs$ :lem-core "PEEK-KILLRING-ITEM")))
    (if (and ck pk)
        (ignore-errors
          (multiple-value-bind (str opts) (funcall pk (funcall ck) 0)
            (declare (ignore opts))
            (and (stringp str) (plusp (length str)))))
        t)))

(defparameter *vs-context-commands*
  '(("复制" :lem "COPY-REGION" :when vs-ctx-region-active-p)
    ("剪切" :lem "KILL-REGION" :when vs-ctx-region-active-p)
    ("粘贴" :lem "YANK" :when vs-ctx-killring-nonempty-p)
    ("注释/反注释" :lem/language-mode "COMMENT-OR-UNCOMMENT-REGION"
     :when vs-ctx-region-active-p)
    ("全选" :lem "MARK-SET-WHOLE-BUFFER")
    ("删除整行" :lem "KILL-WHOLE-LINE")
    ("保存" :lem "SAVE-BUFFER" :when vs-ctx-file-buffer-p)
    ("跳转定义" :lem/language-mode "FIND-DEFINITIONS"
     :when vs-ctx-language-buffer-p)
    ("查找引用" :lem/language-mode "FIND-REFERENCES"
     :when vs-ctx-language-buffer-p)
    ("重命名符号" :lem-lsp-mode "LSP-RENAME" :when vs-ctx-language-buffer-p)
    ("代码操作" :lem-lsp-mode "LSP-CODE-ACTION" :when vs-ctx-language-buffer-p)
    ("参数提示" :lem-lsp-mode "LSP-SIGNATURE-HELP" :when vs-ctx-language-buffer-p)
    ("格式化文档" :lem "FORMAT-BUFFER")
    ("切换自动换行" :lem-user "VSCODE-TOGGLE-LINE-WRAP"))
  "右键菜单条目：(中文标签 定义包 命令名 [:when 谓词符号])。
:when 谓词为本模块 defun 符号（:lem-user 内静态引用安全），每次弹出
时求值，返回 NIL 的条目按当前上下文隐藏；缺省恒显示。")

(defun vs-context-candidates ()
  "当前上下文可用的条目 → (显示行 . 命令符号)。
弹出时求值：:when 谓词不过关的条目先行过滤（谓词报错视同隐藏），
命令符号缺失照旧告警跳过。"
  (let (acc)
    (dolist (e *vs-context-commands* (nreverse acc))
      (let ((pred (getf (cdddr e) :when)))
        (when (or (null pred)
                  (and (fboundp pred) (ignore-errors (funcall pred))))
          (let ((sym (vs$ (second e) (third e))))
            (if (and sym (fboundp sym))
                (push (cons (format nil "~A" (first e)) sym) acc)
                (vs-warn (list (second e) (third e))))))))))

(define-command vscode-context-menu () ()
  "右键命令菜单：prompt 过滤浮窗选命令并执行（VSCode 右键语义）。
必须是 define-command 产物：60-editor-config 的右键 around 直接
funcall 本符号，且未来可绑键。"
  (let* ((table (vs-context-candidates))
         (labels (mapcar #'car table))
         (chosen (prompt-for-string
                  "操作: "
                  :completion-function
                  (lambda (str) (vs-transient-filter str labels)))))
    (let ((hit (assoc chosen table :test #'string=)))
      (when hit (funcall (cdr hit))))))

;; Shift-F10 与右键同命令（VSCode 语义；覆盖上游 SHOW-CONTEXT-MENU，
;; webview 原生菜单遮蔽时的键盘退路）。放本模块：命令在此定义，
;; 70 加载时符号尚不存在。
(vs-bind "Shift-F10" :lem-user "VSCODE-CONTEXT-MENU" "editor" "上下文菜单（右键同款）")
(vs-help-note "code" "参数提示（右键菜单）" "函数签名浮窗（LSP；VSCode Ctrl+Shift+Space 同位，和弦不绑键）")
