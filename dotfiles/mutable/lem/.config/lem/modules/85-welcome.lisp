;;; modules/85-welcome.lisp — VSCode 欢迎页（上游 dashboard 换肤）
;;;
;;; 依赖：utils（vs$/vs-call）；运行期软依赖上游 lem-dashboard 扩展
;;; （nightly 全内置）：类与 set-dashboard 经 vs$ 动态解析，扩展未加载
;;; 时整页跳过并保留上游默认布局（只降级不炸）。被 90-startup 依赖
;;; （首命令钩子里重申一次，防扩展后加载覆盖）。
;;;
;;; 机制：上游 default-dashboard 在扩展加载期 set-default-dashboard
;;; （鹦鹉 ASCII + lisp 笑话）；set-dashboard 只是替换 *dashboard-layout*
;;; 并重绘——本模块在 load 期直接覆盖布局，splash 首绘即欢迎页；
;;; 90-startup 的一次性钩子再调用一次 vs-setup-welcome 兜底。
;;;
;;; VSCode 欢迎页映射：标题 + Start 命令行（New File / Open File）+
;;; Recent 项目与文件 + Learn 链接。dashboard-command 的 Return 开条
;;; 目走 :dashboard-item 属性（键盘可用，不依赖 webview 点击分发）；
;;; display-text 尾部 " (x)" 按上游惯例作按键提示后缀（只显示不点击）。
;;; "Open Folder" 暂缺：上游无对应的交互式命令，不捏造（待补）。
;;;
;;; 上游缺陷补丁（ATTRIBUTE-FOREGROUND 疯弹窗的根因）：lem-core 的
;;; internal-packages export 列表导出了 document-header1~6/link/blockquote
;;; 等一整族 document 属性，**唯独没有 document-text-attribute**；而
;;; lem-dashboard 全部 item 类的 :default-initargs 恰好引用
;;; 'document-text-attribute（在 :lem-dashboard 包 intern 的死符号——从未
;;; define-attribute）。绘制 dashboard 时 ensure-attribute(死符号) → NIL →
;;; attribute-foreground(NIL) 抛 no-applicable-method，每次重绘弹一次错
;;; （即使我们的布局不引用它，上游 set-default-dashboard 的项也带着这个
;;; default-initargs）。补挂 define-attribute 的运行时协议：symbol plists
;;; 'attribute（工厂 lambda，闭包带 :light/:dark 双分支）+ pushnew 进
;;; *attributes*；色值按上游正文语义取 base05 前景（dark #CCCCCC /
;;; light #3B3B3B，即工作台正文字色）。走 vs$ 动态解析：包结构缺失时
;;; 整块跳过。

(in-package :lem-user)

(defparameter *vs-untitled-counter* 0
  "New File 计数器：VSCode Untitled-1/2/… 语义，防重复打开同一 path。")

;; --- 上游缺陷补丁：document-text-attribute 死符号挂接（见文件头注释） ---
(let ((sym (vs$ :lem-dashboard "DOCUMENT-TEXT-ATTRIBUTE")))
  (when (and sym (null (get sym 'attribute)))
    (setf (get sym '%attribute-value) nil)
    (setf (get sym 'attribute)
          (lambda ()
            (or (get sym '%attribute-value)
                (setf (get sym '%attribute-value)
                      (make-attribute
                       :foreground
                       (if (eq :dark (display-background-mode))
                           "#CCCCCC" "#3B3B3B"))))))
    (let ((attrs (vs$ :lem-core "*ATTRIBUTES*")))
      (when (and attrs (boundp attrs))
        (pushnew sym (symbol-value attrs))))))

;; --- Start 区动作（define-command 产物：可绑键，dashboard 点击经
;;     funcall 符号调用；实现只用已验证的上游命令） ---
(define-command vs-welcome-new-file () ()
  "欢迎页 New File：打开 /tmp/Untitled-N 新 buffer（VSCode Untitled 语义）。
find-file 的绝对路径分支直达（已验证 uiop:absolute-pathname-p 吃字符串）。"
  (incf *vs-untitled-counter*)
  (vs-call :lem "FIND-FILE"
           (format nil "/tmp/Untitled-~D" *vs-untitled-counter*)))

(define-command vs-welcome-open-file () ()
  "欢迎页 Open File：find-file universal-1 分支弹文件选择（已验证）。"
  (vs-call :lem "FIND-FILE" 1))

;; --- dashboard item 构造（类符号动态解析：缺失返回 nil，上层 remove） ---
(defun vs-dash (class &rest args)
  "按上游 lem-dashboard 的 CLASS 名构造 item；扩展未加载返回 nil。"
  (let ((c (vs$ :lem-dashboard class)))
    (when c (apply #'make-instance c args))))

(defun vs-setup-welcome ()
  "覆盖上游默认布局为 VSCode 欢迎页；幂等，可重复调用。"
  (let ((items (remove
                nil
                (list
                 (vs-dash "DASHBOARD-SPLASH"
                          :item-attribute 'document-header1-attribute
                          :splash-texts '("Welcome"))
                 (vs-dash "DASHBOARD-COMMAND"
                          :display-text "New File (n)"
                          :action-command 'vs-welcome-new-file
                          :item-attribute 'document-link-attribute
                          :bottom-margin 1)
                 (vs-dash "DASHBOARD-COMMAND"
                          :display-text "Open File (o)"
                          :action-command 'vs-welcome-open-file
                          :item-attribute 'document-link-attribute
                          :bottom-margin 1)
                 (vs-dash "DASHBOARD-RECENT-PROJECTS"
                          :project-count 5
                          :item-attribute 'document-link-attribute
                          :bottom-margin 1)
                 (vs-dash "DASHBOARD-RECENT-FILES"
                          :file-count 8
                          :item-attribute 'document-link-attribute
                          :bottom-margin 1)
                 (vs-dash "DASHBOARD-URL"
                          :display-text "Documentation"
                          :url "https://lem-project.github.io/usage/usage/"
                          :item-attribute 'document-header3-attribute)
                 (vs-dash "DASHBOARD-URL"
                          :display-text "GitHub"
                          :url "https://github.com/lem-project/lem"
                          :item-attribute 'document-header3-attribute
                          :bottom-margin 2)))))
    (when items
      (vs-call :lem-dashboard "SET-DASHBOARD" items)))
  ;; dashboard-mode 局部键：n/o 开条目（r/f 沿用上游最近区跳转）
  (let ((map (let ((s (vs$ :lem-dashboard "*DASHBOARD-MODE-KEYMAP*")))
               (and s (boundp s) (symbol-value s)))))
    (when map
      (vs-call :lem "DEFINE-KEY" map "n" 'vs-welcome-new-file)
      (vs-call :lem "DEFINE-KEY" map "o" 'vs-welcome-open-file))))

;; load 期覆盖：splash 首绘即欢迎页（90-startup 钩子再重申一次防覆盖）
(vs-setup-welcome)
