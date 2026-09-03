;;; init.lisp — Lem 配置引导：VSCode Dark Modern 一比一复刻
;;;
;;; 部署：dotfiles/mutable/lem/ 经 GNU Stow 直链 ~/.config/lem/（改源即生效）
;;; 结构：参照 oh-my-lem（github.com/xenodesire/oh-my-lem）的模块化拆分——
;;;   本文件只做引导；modules/ 目录下全部 .lisp 与 modules/modes/ 下
;;;   各语言文件按文件名字典序自动遍历加载（新增模块建文件即可，
;;;   无需改本文件）。加载顺序由数字前缀控制：
;;;   前缀间隔 10 留插入位；跨模块依赖与顺序约束详见各模块头注释。
;;;     00-utils → 10-performance → 20-icons → 25-fonts → 30-themes
;;;     → 40-explorer → 45-keyhelp → 50-terminal → 55-completion
;;;     → 60-editor-config → 70-keybindings → 75-context-menu
;;;     → 76-whichkey → 80-modes-base → modes/<lang>（同层互不依赖）
;;;     → 90-startup（钩子登记，必须最后）
;;;
;;; 机制约束（勿违反，详见仓库 AGENTS 记忆）：
;;; 1. 必须以 (in-package :lem-user) 开头，否则文件编译期触发包锁崩溃
;;; 2. 配置里「包前缀引用不存在的符号」会在编译期炸死进程（handler-case
;;;    无效）。因此所有非核心符号一律 find-symbol 动态解析，找不到则跳过
;;;    （解析辅助在 00-utils.lisp）
;;; 3. Guix 打包的 lem 镜像内嵌 asdf output-translations 指向只读 store，
;;;    asdf:load-system / ql:quickload 均不可用；模块加载沿用 read+eval
;;;    逐 form 管线（单 form 失败只告警不炸进程）
;;;
;;; 色值权威源：microsoft/vscode dark_modern.json（30-themes.lisp 接线）

(in-package :lem-user)

;; 配置目录：镜像上游 lem-home 的优先级（LEM_HOME → ~/.lem → XDG），
;; 保证与 lem 自身定位 init.lisp / 持久化 config.lisp 的口径一致
(defparameter *vs-config-directory*
  (or (let ((env (uiop:getenv "LEM_HOME")))
        (and env (plusp (length env)) (uiop:ensure-directory-pathname env)))
      (let ((dot (merge-pathnames ".lem/" (user-homedir-pathname))))
        (if (probe-file dot)
            dot
            (uiop:ensure-directory-pathname (uiop:xdg-config-home "lem"))))))

(defun vs-load-source (path)
  "read+eval 逐 form 加载任意 Lisp 源文件（模块与 store 扩展共用）。
动态绑定 *package*：文件内部的 in-package 切换在函数返回后恢复，
否则会把后续 form 的裸符号读进被加载文件的包（普通 (load) 的语义）。
逐 form 加 handler-case：单 form 失败只告警不炸进程；真正的错误会
随后续符号缺失暴露。"
  (let ((*package* *package*)
        (*readtable* *readtable*))
    (with-open-file (in path)
      (loop :for form := (read in nil nil)
            :while form
            :do (handler-case (eval form)
                 (error (e)
                   (format *error-output* "~&; [lem] ~A: skip form ~S: ~A~%"
                           path (if (consp form) (car form) form) e)))))
    path))

;; 模块自动发现：modules/ 下全部 .lisp 按文件名字典序加载
;; （顺序由 NN- 前缀控制，见文件头注释）；各语言文件位于
;; modules/modes/ 下（字典序，同层互不依赖），插在 80-modes-base
;; 之后、90-startup 之前（合并排序会把 modes/ 排到 90- 之后，
;; 故分三段拼接；modes/ 缺失时退化为顶层顺序）。
(defun vs-final-module-p (path)
  "90- 前缀模块（startup 收尾）判别。"
  (let ((name (file-namestring path)))
    (and (>= (length name) 3)
         (string= (subseq name 0 3) "90-"))))
(dolist (f (let ((mods (merge-pathnames "modules/" *vs-config-directory*)))
             (flet ((lisp-files (dir)
                      (sort (remove-if-not
                             (lambda (p)
                               (string-equal "lisp" (pathname-type p)))
                             (list-directory dir))
                            #'string< :key #'namestring)))
               (let ((top (lisp-files mods))
                     (langdir (merge-pathnames "modes/" mods)))
                 (append (remove-if #'vs-final-module-p top)
                         (and (probe-file langdir)
                              (lisp-files langdir))
                         (remove-if-not #'vs-final-module-p top))))))
  (handler-case
      (vs-load-source f)
    (error (e)
      (format *error-output* "~&; [lem] 模块加载失败 ~A: ~A~%" f e))))
