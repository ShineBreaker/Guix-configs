;;; modules/editor-config.lisp — 编辑器外观与行为变量
;;;
;;; 依赖：utils（vs-setvar）、icons（modeline 分支图标）；无下游依赖
;;; （keybindings/startup 不引用本模块符号）。
;;;
;;; editor variable 同样符号身份敏感：必须用定义包的符号（vs-setvar）。

(in-package :lem-user)

;; VSCode Tab 栏 = webview 前端 tabbar（buffer 列表条，上游默认开启且显示
;; 全部 buffer——含 *terminal*/*dashboard* 等临时 buffer）。wrap
;; get-tabbar-buffers 收窄为只显示打开的文件（VSCode 编辑器 tab 语义）；
;; 原函数的增量缓存逻辑不动，只过滤出口。ncurses 前端下 tabbar 渲染走
;; lem-server 的 HTML 管线、view 类型不匹配必崩（nightly 实测），显式关闭。
(let* ((impl-fn (vs$ :lem "IMPLEMENTATION"))
       ;; IMPLEMENTATION-NAME 未 export 进 :lem，home 包 :lem-core 解析
       (name-fn (vs$ :lem-core "IMPLEMENTATION-NAME"))
       (frontend (and (fboundp impl-fn) (fboundp name-fn)
                      (ignore-errors (funcall name-fn (funcall impl-fn)))))
       (get-bufs (vs$ :lem/tabbar "GET-TABBAR-BUFFERS")))
  (cond ((eq frontend :webview)
         (when (and get-bufs (fboundp get-bufs))
           (let ((orig (symbol-function get-bufs)))
             (setf (symbol-function get-bufs)
                   (lambda ()
                     (remove-if-not
                      (lambda (b) (ignore-errors (buffer-filename b)))
                      (funcall orig))))))
         (vs-setglobal :lem/tabbar "*ENABLE-TABBAR-ON-STARTUP*" t))
        (t
         (vs-setglobal :lem/tabbar "*ENABLE-TABBAR-ON-STARTUP*" nil))))

;; VSCode Status Bar 风格：左（ 分支）· 右（Ln,Col / 编码 / EOL / 语言）
(defun vscode-modeline-branch (window)
  (declare (ignore window))
  (ignore-errors
    (let* ((file (buffer-filename (current-buffer)))
           (dir (if file
                    (make-pathname :directory (pathname-directory file))
                    (buffer-directory (current-buffer)))))
      (when dir
        (let ((branch (string-trim
                       '(#\Newline #\Space)
                       (uiop:run-program
                        (list "git" "-C" (namestring dir)
                              "rev-parse" "--abbrev-ref" "HEAD")
                        :output '(:string :stripped t)
                        :ignore-error-status t))))
          (when (and branch (plusp (length branch)))
            (values (format nil "  ~C ~A " (vs-icon :branch) branch)
                    'modeline-name-attribute)))))))

(defun vscode-modeline-encoding (window)
  (declare (ignore window))
  (values " UTF-8 " 'modeline-minor-modes-attribute))

(defun vscode-modeline-eol (window)
  (declare (ignore window))
  (values " LF " 'modeline-minor-modes-attribute))

(defun vscode-modeline-language (window)
  (let ((name (mode-name (buffer-major-mode (window-buffer window)))))
    (values (format nil "  ~A  " name) 'modeline-major-mode-attribute)))

(let ((pos (vs$ :lem "MODELINE-POSITION")))
  (vs-setvar
   :lem "MODELINE-FORMAT"
   `(" "
     vscode-modeline-branch
     ,@(when pos `((,pos nil :right)))
     (vscode-modeline-encoding nil :right)
     (vscode-modeline-eol nil :right)
     (vscode-modeline-language nil :right))))

;; 行号 + 当前行高亮（VSCode 编辑器默认行为）；相对行号见下方 nightly 增益
(vs-setvar :lem/line-numbers "LINE-NUMBERS" t)
(vs-setvar :lem "HIGHLIGHT-LINE" t)

;; dashboard（VSCode 欢迎页）镜像内置默认开启
;; line-wrap 关闭（VSCode 默认不换行；Alt+Z 切换语义迭代阶段接）
(vs-setvar :lem "LINE-WRAP" nil)

;; --- nightly 增益 ---

;; 项目 grep 后端换 rg（Shift-C-f）：nightly 的 grep 把提示符整串交给
;; shell 执行，生效面是 *last-query*（提示符初始串）；*grep-command* /
;; *grep-args* 只是默认拼装源，一并设保持一致。三者均为直接引用的
;; special variable（不走 variable-value plist），必须 vs-setglobal。
;; --vimgrep 输出 path:line:col:text，grep 结果行解析兼容；rg 尊重
;; .gitignore，非 git 目录也能用。
(vs-setglobal :lem/grep "*GREP-COMMAND*" "rg")
(vs-setglobal :lem/grep "*GREP-ARGS*" "--vimgrep")
(vs-setglobal :lem/grep "*LAST-QUERY*" "rg --vimgrep ")

;; 保存时格式化（nightly *auto-format*，format.lisp 直接引用该 special
;; variable）：formatter 缺失或执行出错时静默跳过，未注册 formatter 的
;; 模式不受影响。已注册面：lisp=纯缩进、c=clang-format、go=gofmt、
;; js/ts/vue=prettier、rust=rustfmt、json=prettier。
(vs-setglobal :lem "*AUTO-FORMAT*" t)

;; 相对行号（当前行保持绝对行号；*relative-line* 为直接引用的
;; special variable，见 line-numbers.lisp）
(vs-setglobal :lem/line-numbers "*RELATIVE-LINE*" t)

;; 插件通道（lem-extension-manager + 内置 Quicklisp）：镜像构建期把
;; *PACKAGES-DIRECTORY* 固化成了 /root/.config/lem/packages/（构建容器
;; HOME 残留，warm-boot 后成常量），不可写、装包必炸，必须重设到用户目录。
(vs-setglobal :lem-extension-manager "*PACKAGES-DIRECTORY*"
              (merge-pathnames ".config/lem/packages/" (user-homedir-pathname)))
