;;; modules/75-context-menu.lisp — 右键命令菜单（VSCode 右键语义的配置侧实现）
;;;
;;; 上游菜单内容管线无注册点（BUFFER-CONTEXT-MENU 普通函数默认 NIL；
;;; DISPLAY-POPUP-MENU 的 ITEMS 元素无公开构造子，v29-v36 探针结论），
;;; 此处自研：右键点击弹 prompt-for-string 过滤菜单（F1 transient 同款
;;; 浮窗，见 45-keyhelp），列上下文命令、选中执行。全部条目引用已验证
;;; 存在的命令，缺失只告警跳过（vs$ 动态解析）。
;;;
;;; 依赖：utils（vs$ / vs-warn / vs-bind）、keybindings（分组声明先行，
;;; 本模块借其 "editor" 分组登记）；被 60-editor-config 依赖（右键 around
;;; 调本命令）。加载序 70 之后、90 之前，文件名前缀 75 即位置。

(in-package :lem-user)

(defparameter *vs-context-commands*
  '(("复制" :lem "COPY-REGION")
    ("剪切" :lem "KILL-REGION")
    ("粘贴" :lem "YANK")
    ("注释/反注释" :lem/language-mode "COMMENT-OR-UNCOMMENT-REGION")
    ("全选" :lem "MARK-SET-WHOLE-BUFFER")
    ("删除整行" :lem "KILL-WHOLE-LINE")
    ("保存" :lem "SAVE-BUFFER")
    ("跳转定义" :lem/language-mode "FIND-DEFINITIONS")
    ("查找引用" :lem/language-mode "FIND-REFERENCES")
    ("重命名符号" :lem-lsp-mode "LSP-RENAME")
    ("代码操作" :lem-lsp-mode "LSP-CODE-ACTION")
    ("格式化文档" :lem "FORMAT-BUFFER")
    ("切换自动换行" :lem-user "VSCODE-TOGGLE-LINE-WRAP"))
  "右键菜单条目：(中文标签 定义包 命令名)。")

(defun vs-context-candidates ()
  "已解析出命令符号的条目 → (显示行 . 命令符号)。"
  (let (acc)
    (dolist (e *vs-context-commands* (nreverse acc))
      (let ((sym (vs$ (second e) (third e))))
        (if (and sym (fboundp sym))
            (push (cons (format nil "~A" (first e)) sym) acc)
            (vs-warn (list (second e) (third e))))))))

(define-command vscode-context-menu () ()
  "右键命令菜单：prompt 过滤浮窗选命令并执行（VSCode 右键语义）。
必须是 define-command 产物：60-editor-config 的右键 around 直接
funcall 本符号，且未来可绑键。"
  (let* ((table (vs-context-candidates))
         (labels (mapcar #'car table))
         (chosen (prompt-for-string
                  "操作: "
                  :completion-function
                  (lambda (str)
                    (if (or (null str) (string= str ""))
                        labels
                        (remove-if-not
                         (lambda (s) (search str s :test #'char-equal))
                         labels))))))
    (let ((hit (assoc chosen table :test #'string=)))
      (when hit (funcall (cdr hit))))))

;; Shift-F10 与右键同命令（VSCode 语义；覆盖上游 SHOW-CONTEXT-MENU，
;; webview 原生菜单遮蔽时的键盘退路）。放本模块：命令在此定义，
;; 70 加载时符号尚不存在。
(vs-bind "Shift-F10" :lem-user "VSCODE-CONTEXT-MENU" "editor" "上下文菜单（右键同款）")
