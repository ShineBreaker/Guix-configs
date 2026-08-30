;;; modules/editor-config.lisp — 编辑器外观与行为变量
;;;
;;; 依赖：utils（vs-setvar）、icons（modeline 分支图标）；无下游依赖
;;; （keybindings/startup 不引用本模块符号）。
;;;
;;; editor variable 同样符号身份敏感：必须用定义包的符号（vs-setvar）。

(in-package :lem-user)

;; VSCode Tab 栏由 frame-multiplexer 承担（after-init-hook 默认开启、带编号、
;; C-z 数字快切）；tabbar（buffer 列表条）与之重复，保持默认关闭

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

;; 行号 + 当前行高亮（VSCode 编辑器默认行为）
(vs-setvar :lem/line-numbers "LINE-NUMBERS" t)
(vs-setvar :lem "HIGHLIGHT-LINE" t)

;; dashboard（VSCode 欢迎页）镜像内置默认开启
;; line-wrap 关闭（VSCode 默认不换行；Alt+Z 切换语义迭代阶段接）
(vs-setvar :lem "LINE-WRAP" nil)
