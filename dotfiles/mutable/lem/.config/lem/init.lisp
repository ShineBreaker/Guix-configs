;;; init.lisp — Lem 配置引导：VSCode Dark Modern 一比一复刻
;;;
;;; 部署：dotfiles/mutable/lem/ 经 GNU Stow 直链 ~/.config/lem/（改源即生效）
;;; 结构：参照 oh-my-lem（github.com/xenodesire/oh-my-lem）的模块化拆分——
;;;   本文件只做引导；modules/ 目录下全部 .lisp 与 modules/modes/ 下
;;;   各语言文件按文件名字典序自动遍历加载（新增模块建文件即可，
;;;   无需改本文件）。加载顺序由数字前缀控制：
;;;   前缀间隔 10 留插入位；跨模块依赖与顺序约束详见各模块头注释。
;;;     00-utils → 10-performance → 20-icons → 25-fonts → 30-themes
;;;     → 40-explorer → 45-keyhelp → 46-problems → 50-terminal
;;;     → 55-completion
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
      (loop :for n :from 0
            :for pos := (file-position in)
            :for form := (handler-case (read in nil nil)
                           (error (e)
                             (with-open-file
                                 (o "/tmp/lem-loaderr.log" :direction :output
                                    :if-exists :append :if-does-not-exist :create)
                               (format o "READ-ERR ~A form~D byte~D: ~A~%"
                                       path n pos e))
                             nil))
            :while form
            :do (handler-case (eval form)
                  (error (e)
                    ;; eval 错误同样落文件：*error-output* 被 editor stream
                    ;; 吞掉终端不可见，无文件日志时 form 失败只剩「后续
                    ;; 符号静默缺失」这一个远端症状（read 日志同款出口）
                    (with-open-file
                        (o "/tmp/lem-loaderr.log" :direction :output
                           :if-exists :append :if-does-not-exist :create)
                      (format o "EVAL-ERR ~A form~D: ~A~%  form: ~S~%"
                              path n e
                              (if (and (consp form) (> (length form) 3))
                                  (append (subseq form 0 3) '(&etc))
                                  form)))))))
    path))

;; --- 模块 FASL 缓存：read+eval 逐 form 加载会让 SBCL 对每 form 走编译
;;     管线（~250ms/全配置）；编译产物缓存后 load fasl 只需毫秒级。
;;     缓存键 = mtime+size（配置编辑场景足够；sb-md5 不在镜像内，勿用）。
;;     fasl 存放在 XDG cache（不污染 LEM_HOME/仓库源）。编译或 load 失败
;;     一律退化 vs-load-source——缓存只许加速，不许成为故障源。
;;     VS_NO_FASL=1 可整体旁路（调试用）。 ---
(defparameter *vs-fasl-dir*
  (ignore-errors
    (uiop:ensure-directory-pathname
     (merge-pathnames "lem/fasl/" (uiop:xdg-cache-home))))
  "fasl 缓存目录（~/.cache/lem/fasl/）。")

(defun vs-fasl-path (src mtime size)
  (merge-pathnames
   (format nil "~A-~A-~A.fasl" (pathname-name src) mtime size)
   *vs-fasl-dir*))

(defun vs-load-module (path)
  "fasl 命中直接 load；未命中 compile-file 到临时文件后 rename 进缓存
（同文件系统原子替换，并发 lem 实例最坏重复编译不损坏）；任一步失败
退化 vs-load-source。"
  (if (or (uiop:getenv "VS_NO_FASL") (null *vs-fasl-dir*))
      (vs-load-source path)
      (let* ((mtime (ignore-errors (file-write-date path)))
             (size (ignore-errors
                     (with-open-file (in path) (file-length in))))
             (fasl (and mtime size (vs-fasl-path path mtime size))))
        (if (and fasl (probe-file fasl))
            (or (ignore-errors (load fasl) t)
                (progn (ignore-errors (delete-file fasl))
                       (vs-load-source path)))
            (progn
              (ensure-directories-exist fasl)
              (let ((tmp (ignore-errors
                           (compile-file
                            path
                            :output-file
                            (merge-pathnames
                             (format nil "~A-tmp~A.fasl"
                                     (pathname-name path)
                                     (get-internal-real-time))
                             *vs-fasl-dir*)))))
                (if (and tmp (probe-file tmp))
                    (progn
                      (ensure-directories-exist fasl)
                      (ignore-errors (rename-file tmp fasl))
                      ;; 同模块旧键的 fasl 清掉，防缓存无限堆积
                      (dolist (stale (directory
                                      (merge-pathnames
                                       (format nil "~A-*.fasl" (pathname-name path))
                                       *vs-fasl-dir*)))
                        (unless (equal stale fasl)
                          (ignore-errors (delete-file stale))))
                      (or (ignore-errors (load fasl) t)
                          (vs-load-source path)))
                    (vs-load-source path))))))))

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
(defparameter *vs-bench* (uiop:getenv "VS_BENCH")
  "VS_BENCH=1 时把各模块加载耗时追加到 /tmp/lem-bench-modules.log。")

(defun vs-bench-log (fmt &rest args)
  (when *vs-bench*
    (ignore-errors
      (with-open-file (out "/tmp/lem-bench-modules.log"
                           :direction :output :if-exists :append
                           :if-does-not-exist :create)
        (apply #'format out fmt args)))))

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
  (let ((t0 (get-internal-real-time)))
    (handler-case
        (vs-load-module f)
      (error (e)
        (format *error-output* "~&; [lem] 模块加载失败 ~A: ~A~%" f e)))
    (vs-bench-log "~A ~D ms~%" (file-namestring f)
                  (round (* 1000 (- (get-internal-real-time) t0))
                         internal-time-units-per-second))))
