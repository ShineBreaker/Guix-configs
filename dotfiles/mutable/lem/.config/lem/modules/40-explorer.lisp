;;; modules/40-explorer.lisp — Explorer 常驻侧栏（VSCode 侧边栏复刻）
;;;
;;; 依赖：utils、icons（vs-icon）；被 terminal（bypass 表引用本模块命令）、
;;; keybindings（C-b / Ctrl+Shift+E）、startup（启动展开 + heal 钩子）依赖。
;;;
;;; 架构：lem 框架级 leftside window（make-leftside-window）承载自绘
;;; buffer —— EXPLORER 标题 + 内嵌 Activity 图标行 + 工作区 section +
;;; 文件树（目录记忆 + git 状态染色）。

(in-package :lem-user)

;; --- 侧栏 attribute（直接定义、不经主题：load-theme 不会覆盖） ---
(define-attribute vs-sidebar-bg (t :foreground "#CCCCCC" :background "#181818"))
(define-attribute vs-explorer-title (t :foreground "#CCCCCC" :background "#181818" :bold t))
(define-attribute vs-explorer-titlebar (t :foreground "#9D9D9D" :background "#181818"))
(define-attribute vs-activity-active (t :foreground "#FFFFFF" :background "#181818" :bold t))
(define-attribute vs-activity-inactive (t :foreground "#6E7681" :background "#181818"))
(define-attribute vs-section-header (t :foreground "#CCCCCC" :background "#181818" :bold t))
(define-attribute vs-tree-chevron (t :foreground "#9D9D9D" :background "#181818"))
;; VSCode Seti 风格文件夹黄
(define-attribute vs-tree-folder (t :foreground "#C09553" :background "#181818"))
(define-attribute vs-tree-file (t :foreground "#CCCCCC" :background "#181818"))
;; git 染色（list.warningForeground 系：modified/delete/undo 系）
(define-attribute vs-git-modified (t :foreground "#E2C08D" :background "#181818"))
(define-attribute vs-git-untracked (t :foreground "#73C991" :background "#181818"))
(define-attribute vs-git-deleted (t :foreground "#C74E39" :background "#181818"))
(define-attribute vs-git-conflict (t :foreground "#E4676B" :background "#181818"))

;; --- 状态 ---
(defparameter *vs-explorer-buffer-name* "*Explorer*")
(defparameter *vs-explorer-width* 28 "VSCode Side Bar；SDL2 大字号下 34 列过宽，收窄到 28")
(defparameter *vs-explorer-root* nil)
(defparameter *vs-open-dirs* (make-hash-table :test 'equal)
  "展开状态记忆：目录 namestring → t（侧栏关闭重开后仍保持）")
(defparameter *vs-git-status* (make-hash-table :test 'equal)
  "相对路径 → :modified/:untracked/:deleted/:conflict")
(defparameter *vs-code-exts*
  '("lisp" "lsp" "scm" "el" "py" "c" "h" "cc" "cpp" "rs" "go" "js" "ts"
    "json" "yaml" "yml" "toml" "nix" "sh" "org" "md"))

;; --- 工作区根探测：向上走 .git（与 VSCode 默认 workspace 语义一致） ---
(defun vs-project-root ()
  (labels ((walk (dir count)
             (cond ((or (null dir) (> count 32)
                        (equal (namestring dir) "/"))
                    nil)
                   ((probe-file (merge-pathnames ".git" dir))
                    dir)
                   (t (walk (uiop:pathname-parent-directory-pathname dir)
                            (1+ count))))))
    (let ((start (or (ignore-errors (buffer-directory (current-buffer)))
                     (uiop:getcwd))))
      (or (walk start 0) start))))

;; --- git 状态表（文件 + 祖先目录染色；优先级 conflict>deleted>modified>untracked） ---
(defun vs-status-priority (s)
  (ecase s (:conflict 4) (:deleted 3) (:modified 2) (:untracked 1)))

(defun vs-refresh-git-status ()
  (let ((table (make-hash-table :test 'equal)))
    (when *vs-explorer-root*
      (ignore-errors
        (dolist (line (uiop:run-program
                       (list "git" "-C" (namestring *vs-explorer-root*)
                             "status" "--porcelain" "-uall")
                       :output :lines :ignore-error-status t))
          (when (>= (length line) 4)
            (let* ((xy (subseq line 0 2))
                   (raw (subseq line 3))
                   ;; rename「old -> new」取 new；C 引号路径剥外层引号
                   (path (let ((p (if (and (>= (length raw) 2)
                                           (char= (char raw 0) #\"))
                                      (string-trim '(#\") raw)
                                      raw)))
                           (let ((arrow (search " -> " p)))
                             (if arrow (subseq p (+ arrow 4)) p))))
                   (status (cond ((find #\U xy) :conflict)
                                 ((find #\D xy) :deleted)
                                 ((char= (char line 0) #\?) :untracked)
                                 ((find #\A xy) :untracked)
                                 (t :modified))))
              (setf (gethash path table) status)
              ;; 祖先目录按最高优先级染色
              (loop :for i :from 0 :below (length path)
                    :when (char= (char path i) #\/)
                    :do (let ((dir (subseq path 0 i)))
                          (let ((old (gethash dir table)))
                            (when (or (null old)
                                      (< (vs-status-priority old)
                                         (vs-status-priority status)))
                              (setf (gethash dir table) status))))))))))
    (setf *vs-git-status* table)))

(defun vs-status-attribute (s)
  (ecase s
    (:modified 'vs-git-modified)
    (:untracked 'vs-git-untracked)
    (:deleted 'vs-git-deleted)
    (:conflict 'vs-git-conflict)))

;; --- 文件系统辅助 ---
(defun vs-item-name (path)
  (if (uiop:directory-pathname-p path)
      (car (last (pathname-directory path)))
      (file-namestring path)))

(defun vs-relative (path)
  "相对工作区根的 namestring；目录去掉尾斜杠（与 git status 键对齐）。"
  (let ((s (enough-namestring path *vs-explorer-root*)))
    (if (and (plusp (length s))
             (char= (char s (1- (length s))) #\/))
        (subseq s 0 (1- (length s)))
        s)))

(defun vs-dir-children (dir)
  "子项列表：目录在前、各自大小写不敏感字典序；排除 .git。"
  (sort
   (remove-if (lambda (p)
                (member (vs-item-name p) '(".git") :test #'equal))
              (list-directory dir))
   (lambda (a b)
     (let ((da (uiop:directory-pathname-p a))
           (db (uiop:directory-pathname-p b)))
       (cond ((and da db) (string-lessp (vs-item-name a) (vs-item-name b)))
             (da t)
             (db nil)
             (t (string-lessp (vs-item-name a) (vs-item-name b))))))))

;; --- 渲染 ---
(defun vs-pad-to-width (point)
  (let ((pad (- *vs-explorer-width* (point-charpos point))))
    (when (plusp pad)
      (insert-string point (make-string pad :initial-element #\space)
                     :attribute 'vs-sidebar-bg))))

(defun vs-explorer-render-header (point)
  ;; 标题行（EXPLORER + 右缘 ⋯）
  (insert-string point " EXPLORER" :attribute 'vs-explorer-title)
  (vs-pad-to-width point)
  (insert-string point (string (vs-icon :ellipsis))
                 :attribute 'vs-explorer-titlebar)
  (insert-character point #\newline)
  ;; Activity Bar 内嵌图标行（explorer 激活白，其余灰）
  (let ((icons '(:files :search :scm :debug :extensions)))
    (insert-string point " " :attribute 'vs-sidebar-bg)
    (dolist (i icons)
      (insert-string point (string (vs-icon i))
                     :attribute (if (eq i :files)
                                    'vs-activity-active
                                    'vs-activity-inactive))
      (insert-string point "  " :attribute 'vs-sidebar-bg))
    (vs-pad-to-width point)
    (insert-character point #\newline))
  (insert-character point #\newline)
  ;; 工作区 section 头（▾ 大写项目名，VSCode 形态）
  (insert-string point (format nil " ~C " (vs-icon :chevron-down))
                 :attribute 'vs-tree-chevron)
  (insert-string point (string-upcase
                        (or (car (last (pathname-directory *vs-explorer-root*)))
                            "WORKSPACE"))
                 :attribute 'vs-section-header)
  (vs-pad-to-width point)
  (insert-character point #\newline))

(defun vs-insert-tree-line (point path depth)
  (let* ((dir-p (uiop:directory-pathname-p path))
         (open (and dir-p (gethash (namestring path) *vs-open-dirs*)))
         (name (vs-item-name path))
         (status (gethash (vs-relative path) *vs-git-status*))
         (name-attr (cond (status (vs-status-attribute status))
                          (dir-p 'vs-tree-folder)
                          (t 'vs-tree-file)))
         (glyph (cond ((and dir-p open) (vs-icon :folder-opened))
                      (dir-p (vs-icon :folder))
                      ((member (pathname-type path) *vs-code-exts*
                               :test #'equalp)
                       (vs-icon :file-code))
                      (t (vs-icon :file)))))
    (insert-string point (make-string (* 2 depth) :initial-element #\space)
                   :attribute 'vs-sidebar-bg)
    (if dir-p
        (insert-string point
                       (string (vs-icon (if open :chevron-down :chevron-right)))
                       :attribute 'vs-tree-chevron)
        (insert-string point " " :attribute 'vs-sidebar-bg))
    (insert-string point " " :attribute 'vs-sidebar-bg)
    (insert-string point (string glyph) :attribute name-attr)
    (insert-string point " " :attribute 'vs-sidebar-bg)
    (insert-string point name :attribute name-attr)
    (vs-pad-to-width point)
    ;; 整行挂 item 属性（路径 + 目录标志），供 select/折叠命令读取
    (with-point ((start point))
      (line-start start)
      (put-text-property start point :vs-item
                         (list :path path :dir-p dir-p)))))

(defun vs-render-dir (point dir depth)
  (dolist (child (vs-dir-children dir))
    (let ((open (and (uiop:directory-pathname-p child)
                     (gethash (namestring child) *vs-open-dirs*))))
      (vs-insert-tree-line point child depth)
      (insert-character point #\newline)
      (when open
        (vs-render-dir point child (1+ depth))))))

(defun vs-explorer-render ()
  (when *vs-explorer-root*
    (let ((buffer (vs-explorer-buffer)))
      (when buffer
        (handler-case
            (progn
              (vs-refresh-git-status)
              (with-buffer-read-only buffer nil
                (let ((line (line-number-at-point (buffer-point buffer))))
                  (erase-buffer buffer)
                  (vs-explorer-render-header (buffer-point buffer))
                  (vs-render-dir (buffer-point buffer) *vs-explorer-root* 0)
                  (move-to-line (buffer-point buffer) line))))
          (error (e)
            (message "Explorer 渲染失败: ~A" e)))))))

;; --- major mode + 键位 ---
(defparameter *vs-explorer-keymap* (make-keymap))

(define-major-mode vscode-explorer-mode ()
    (:name "Explorer"
     :keymap *vs-explorer-keymap*)
  (setf (variable-value 'line-wrap :buffer (current-buffer)) nil)
  (setf (buffer-read-only-p (current-buffer)) t))

(defun vs-item-at-point ()
  (text-property-at (back-to-indentation (current-point)) :vs-item))

(defun vs-focus-main-window ()
  (unless (member (current-window) (window-list))
    (setf (current-window) (car (window-list)))))

(define-command vscode-explorer-select () ()
  "Return：目录展开/折叠，文件在主窗打开并把焦点交还编辑区。"
  (let ((item (vs-item-at-point)))
    (when item
      (if (getf item :dir-p)
          (progn
            (let ((key (namestring (getf item :path))))
              (if (gethash key *vs-open-dirs*)
                  (remhash key *vs-open-dirs*)
                  (setf (gethash key *vs-open-dirs*) t)))
            (vs-explorer-render))
          (progn
            (vs-focus-main-window)
            (find-file (getf item :path)))))))

(define-command vscode-explorer-toggle-dir () ()
  "Tab：只切换展开态，不打开文件。"
  (let ((item (vs-item-at-point)))
    (when (and item (getf item :dir-p))
      (let ((key (namestring (getf item :path))))
        (if (gethash key *vs-open-dirs*)
            (remhash key *vs-open-dirs*)
            (setf (gethash key *vs-open-dirs*) t)))
      (vs-explorer-render))))

(define-command vscode-explorer-collapse () ()
  "Left：折叠当前目录。"
  (let ((item (vs-item-at-point)))
    (when (and item (getf item :dir-p))
      (remhash (namestring (getf item :path)) *vs-open-dirs*)
      (vs-explorer-render))))

(define-command vscode-explorer-expand () ()
  "Right：展开当前目录。"
  (let ((item (vs-item-at-point)))
    (when (and item (getf item :dir-p))
      (setf (gethash (namestring (getf item :path)) *vs-open-dirs*) t)
      (vs-explorer-render))))

(define-command vscode-explorer-refresh () ()
  "r/g：重扫文件系统 + git 状态。"
  (vs-explorer-render))

(define-key *vs-explorer-keymap* "Return" 'vscode-explorer-select)
(define-key *vs-explorer-keymap* "Space" 'vscode-explorer-select)
(define-key *vs-explorer-keymap* "Tab" 'vscode-explorer-toggle-dir)
(define-key *vs-explorer-keymap* "Left" 'vscode-explorer-collapse)
(define-key *vs-explorer-keymap* "Right" 'vscode-explorer-expand)
(define-key *vs-explorer-keymap* "r" 'vscode-explorer-refresh)
(define-key *vs-explorer-keymap* "g" 'vscode-explorer-refresh)

;; Activity 图标行对应视图（1-5 跳转；4/5 暂无对应物）
(defun vs-run-command (pkg name)
  (vs-focus-main-window)
  (vs-call pkg name))

(define-command vscode-activity-explorer () ()
  (message "Explorer"))

(define-command vscode-activity-search () ()
  (vs-run-command :lem/grep "PROJECT-GREP"))

(define-command vscode-activity-scm () ()
  (vs-run-command :lem/legit "LEGIT-STATUS"))

(define-command vscode-activity-debug () ()
  (message "Run and Debug：暂无对应物"))

(define-command vscode-activity-extensions () ()
  (message "Extensions：暂无对应物"))

(define-key *vs-explorer-keymap* "1" 'vscode-activity-explorer)
(define-key *vs-explorer-keymap* "2" 'vscode-activity-search)
(define-key *vs-explorer-keymap* "3" 'vscode-activity-scm)
(define-key *vs-explorer-keymap* "4" 'vscode-activity-debug)
(define-key *vs-explorer-keymap* "5" 'vscode-activity-extensions)

;; --- 侧栏开关（Ctrl+B / Ctrl+Shift+E） ---
(defun vs-explorer-window ()
  "本侧栏专属的 leftside 窗口（按 buffer major-mode 判定归属，避免误认 filer 等其它侧窗）。"
  (let ((accessor (vs$ :lem-core "FRAME-LEFTSIDE-WINDOW")))
    (let ((w (and accessor (funcall accessor (current-frame)))))
      (and w
           (eq 'vscode-explorer-mode
               (buffer-major-mode (window-buffer w)))
           w))))

(defun vs-explorer-buffer ()
  "当前侧栏正在显示的 buffer（刷新路径用；开启路径每次造全新 buffer）。"
  (let ((w (vs-explorer-window)))
    (and w (window-buffer w))))

(define-command vscode-toggle-sidebar () ()
  "VSCode Ctrl+B：显示/隐藏 Explorer 侧栏（展开状态存全局表，跨开关保持）。
开启路径每次造全新 buffer：lem 2.3.0 里经 vs-explorer-buffer 复用的 buffer
会被 display 层拒绘（实测恒空白，全新 buffer 同管线正常），unique 名避开
get-buffer 撞名；树状态在 *vs-open-dirs*，buffer 无状态损失。"
  (let ((win (vs-explorer-window)))
    (if win
        (progn
          (when (eq (current-window) win)
            (vs-focus-main-window))
          (delete-leftside-window))
        (let ((buffer (make-buffer (unique-buffer-name *vs-explorer-buffer-name*)
                                   :temporary t)))
          (change-buffer-mode buffer 'vscode-explorer-mode)
          (setf (not-switchable-buffer-p buffer) t)
          (setf *vs-explorer-root* (vs-project-root))
          (vs-refresh-git-status)
          (with-buffer-read-only buffer nil
            (erase-buffer buffer)
            (vs-explorer-render-header (buffer-point buffer))
            (vs-render-dir (buffer-point buffer) *vs-explorer-root* 0)
            (move-to-line (buffer-point buffer) 1))
          (make-leftside-window buffer :width *vs-explorer-width*)))))

;; --- resize 自愈：上游只给 rightside 挂 resize 补偿（window.lisp 只调
;; resize-rightside-window），leftside 的 ncurses view 在终端尺寸变化后
;; 失效且重开也无法恢复（实测恒空白）。治疗动作（关开一遍侧栏，toggle
;; 开启路径每次造 fresh window+view）不能在 size-change 钩子内同步执行
;; ——开关窗口本身又触发 size-change，重入死锁。改为标志位，post-command
;; 安全期执行；run-hooks 会传 window 参数，签名必须收下。
(defparameter *vs-need-heal* nil)
(defparameter *vs-healing* nil)

(defun vs-resize-heal (window)
  (declare (ignore window))
  ;; healing 期内的尺寸变化（toggle 重建、面板恢复）都是自愈动作自身
  ;; 引起的，不置位——否则「heal 改尺寸 → size-change 置位 → 再 heal」
  ;; 永动循环。
  (unless *vs-healing*
    (setf *vs-need-heal* t)))

(defun vs-maybe-heal ()
  "post-command 安全期消费 resize 标志：关开一遍侧栏重建 leftside view。
末次 make-leftside-window 的 balance 会再触发一次 size-change 置位，
治疗完成后清除标志——只把清除之后的新 resize 视为下一次治疗需求。
重建会 balance-windows 均分既有 split，跑 *vs-heal-hooks* 让各模块
恢复自己的布局（50-terminal 的面板 1/3 高度）。"
  (when (and *vs-need-heal* (not *vs-healing*))
    (setf *vs-need-heal* nil
          *vs-healing* t)
    (ignore-errors
      (when (vs-explorer-window)
        (vscode-toggle-sidebar)
        (vscode-toggle-sidebar))
      (dolist (fn *vs-heal-hooks*)
        (ignore-errors (funcall fn))))
    (setf *vs-need-heal* nil
          *vs-healing* nil)))
