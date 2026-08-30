;;; modules/00-utils.lisp — 动态符号解析辅助 + store 源码树加载器
;;;
;;; 依赖：init.lisp（vs-load-source）；被其余所有模块依赖，必须最先加载。
;;;
;;; 设计动机：配置里直接书写 lem 内部/扩展包的包前缀符号，会在编译期
;;; 因符号不存在而炸死进程（handler-case 无效）。所有非核心符号一律
;;; find-symbol 动态解析，缺失只告警跳过——扩展版本变动只降级不崩。

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

(defun vs-bind (keyspec pkg name)
  "逐条 define-key（函数式）：命令符号 find-symbol 动态解析，缺失只告警。"
  (let ((sym (vs$ pkg name)))
    (if sym
        (define-key *global-keymap* keyspec sym)
        (vs-warn (list pkg name)))))

(defparameter *lem-source-tree*
  (asdf:system-source-directory :lem)
  "lem 自身源码树（Guix store 只读副本）。升级换 hash 后自动跟随。")

(defun vs-load-lem-source (relpath)
  "从 store 源码树加载扩展源文件（相对 *lem-source-tree* 的路径）。"
  (vs-load-source (merge-pathnames relpath *lem-source-tree*)))

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
