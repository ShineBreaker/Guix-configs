;;; modules/00-utils.lisp — 动态符号解析辅助 + 键位注册表
;;;
;;; 依赖：init.lisp（vs-load-source）；被其余所有模块依赖，必须最先加载。
;;;
;;; 设计动机：配置里直接书写 lem 内部/扩展包的包前缀符号，会在编译期
;;; 因符号不存在而炸死进程（handler-case 无效）。所有非核心符号一律
;;; find-symbol 动态解析，缺失只告警跳过——扩展版本变动只降级不崩。
;;; （原 store 扩展补载器 vs-load-lem-source 已随 10-extensions 废弃：
;;; nightly 镜像扩展全内置且无源码树。）

(in-package :lem-user)

(defun vs$ (pkg name)
  "find-symbol 动态解析；包或符号不存在返回 nil。"
  (ignore-errors (find-symbol name pkg)))

(defun vs-warn (sym)
  (format *error-output* "~&; [lem] 符号缺失被跳过: ~S~%" sym)
  nil)

(defun vs-call (pkg name &rest args)
  "动态解析并调用；符号缺失只告警返回 nil。"
  (let ((sym (vs$ pkg name)))
    (if sym
        (apply sym args)
        (vs-warn (list pkg name)))))

(defun vs-spec (pkg name &rest args)
  "构造一条 (attribute-symbol args...) 主题规格；符号缺失返回 nil。"
  (let ((sym (vs$ pkg name)))
    (if sym (cons sym args) (vs-warn (list pkg name)))))

(defun vs-setvar (pkg name val)
  "设置编辑器全局变量（editor variable 符号身份敏感，必须用定义包的符号）。"
  (let ((sym (vs$ pkg name)))
    (if sym
        (setf (variable-value sym :global) val)
        (vs-warn (list pkg name)))))

(defun vs-setglobal (pkg name val)
  "直接 setf special variable 的 symbol-value。
区别于 vs-setvar（variable-value plist 机制）：上游代码不经
variable-value 而直接引用 special variable 时（grep 的 *last-query*、
format 的 *auto-format*、line-numbers 的 *relative-line* 均是），
必须走这里，否则 plist 改了、运行时读到的仍是镜像默认值。" 
  (let ((sym (vs$ pkg name)))
    (if sym
        (setf (symbol-value sym) val)
        (vs-warn (list pkg name)))))

;; --- 键位注册表（45-keyhelp 帮助页的数据源，which-key 替代的描述层）---
(defparameter *vs-binding-groups* nil
  "分组登记表：(分组ID 标题) 列表，vs-declare-group 按声明顺序展示。")
(defparameter *vs-binding-registry* nil
  "已注册键位：(键串 命令名 分组ID 描述 命令符号) 列表，vs-bind 落键时
登记；第五位符号供 vs-transient-show 菜单直接执行。")
(defparameter *vs-help-notes* nil
  "帮助页附注：(分组ID 键串 描述) 列表——登记不经 vs-bind 的绑定
（language-mode 默认键、局部 keymap 内的键），只作展示。")

(defun vs-declare-group (id title)
  "声明键位分组（帮助页按声明顺序渲染分组标题）。"
  (unless (assoc id *vs-binding-groups* :test #'string=)
    (setf *vs-binding-groups*
          (nconc *vs-binding-groups* (list (list id title))))))

(defun vs-help-note (group keyspec desc)
  "向帮助页附注一条不经 vs-bind 的绑定（仅展示，不落键）。
条目与注册表同构：(键串 命令名 分组ID 描述)，命令名留空占位。"
  (push (list keyspec "" group desc) *vs-help-notes*))

(defun vs-bind (keyspec pkg name &optional (group "other") (desc ""))
  "逐条 define-key（函数式）：命令符号 find-symbol 动态解析，缺失只告警。
同时登记进 *vs-binding-registry*（帮助页数据源）。"
  (let ((sym (vs$ pkg name)))
    (if sym
        (progn
          (define-key *global-keymap* keyspec sym)
          (push (list keyspec name group desc sym) *vs-binding-registry*))
        (vs-warn (list pkg name)))))

(defparameter *vs-heal-hooks* nil
  "resize 自愈（侧栏重建）完成后的布局恢复钩子。侧栏重建内部走
make-leftside-window → balance-windows，会把已有的上下 split 均分；
依赖特定 split 比例的模块（如终端面板 1/3）在此注册恢复函数。
定义于 00（最先加载），触发在 40-explorer 的 vs-maybe-heal。")

(defun vs-trace (fmt &rest args)
  "诊断日志直写文件（lem 的 with-editor-stream 会吞 *error-output*）。"
  (ignore-errors
    (with-open-file (out "/tmp/vs-trace.log"
                         :direction :output :if-exists :append
                         :if-does-not-exist :create)
      (format out "~&~A~%" (apply #'format nil fmt args)))))
