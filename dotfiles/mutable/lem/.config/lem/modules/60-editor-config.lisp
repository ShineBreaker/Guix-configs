;;; modules/60-editor-config.lisp — 编辑器外观与行为变量
;;;
;;; 依赖：utils（vs-setvar）、icons（modeline 分支图标）；下游 keybindings
;;; 引用本模块命令（VSCODE-TOGGLE-LINE-WRAP，M-z）。
;;;
;;; editor variable 同样符号身份敏感：必须用定义包的符号（vs-setvar）。

(in-package :lem-user)

;; 上游 tabbar（webview 顶栏 buffer 列表条）= VSCode 编辑器 tab 的对位物：
;; HTML 管线、原生点击切换/关闭/dirty 圆点（webview 自带交互）。默认显示
;; 全部 buffer（含 *terminal*/*dashboard* 等临时 tab），wrap get-tabbar-buffers
;; 收窄为只显示文件 buffer（原函数增量缓存逻辑不动，只过滤出口）。
;; 旧方案（禁 tabbar + frame-multiplexer 当标签条）被否：vf 是 frame 条非文件
;; tab（单显示项、无点击关闭），与 VSCode 语义差距更大。
;; 开关分派用「排除法」：webview 下加载本模块时 IMPLEMENTATION 尚未就绪
;; （frontend 解析为 nil），eq :webview 判定会误关；ncurses 的 tabbar 渲染走
;; lem-server HTML 管线必崩（AGENTS 实测），唯独它要关；其余前端一律开。
(let* ((impl-fn (vs$ :lem "IMPLEMENTATION"))
       ;; IMPLEMENTATION-NAME 未 export 进 :lem，home 包 :lem-core 解析
       (name-fn (vs$ :lem-core "IMPLEMENTATION-NAME"))
       (frontend (and (fboundp impl-fn) (fboundp name-fn)
                      (ignore-errors (funcall name-fn (funcall impl-fn))))))
  (vs-setglobal :lem/tabbar "*ENABLE-TABBAR-ON-STARTUP*"
                (not (eq frontend :ncurses))))
(let ((get-bufs (vs$ :lem/tabbar "GET-TABBAR-BUFFERS")))
  (when (and get-bufs (fboundp get-bufs))
    ;; 重载幂等：orig 只记首次的上游原始函数（重载不复写），每次重载
    ;; 都按同一 orig 重包一层再整体 setf——wrap 链深度恒 1，不随重载
    ;; 叠加。登记挂符号 plist（get/setf get 不触发包锁）。
    (let ((orig (or (get get-bufs 'vs-tabbar-orig)
                    (symbol-function get-bufs))))
      (setf (symbol-function get-bufs)
            (lambda ()
              (remove-if-not
               (lambda (b) (ignore-errors (buffer-filename b)))
               (funcall orig))))
      (setf (get get-bufs 'vs-tabbar-orig) orig))))

;; tabbar 推送去重（webview 前端）：上游 tabbar 的 update 挂在
;; after-change-functions 上——**每次编辑**都置 need-update-p=nil，下一帧
;; window-redraw 便重跑 generate-html（含 CSS/JS 的整份 HTML，数 KB）并经
;; CHANGE-VIEW-TO-HTML 推向浏览器。而连续打字时 tab 的三态（标题/dirty/
;; active）逐字不变 → 整份 HTML 逐字相同，推送、JSON 编码、浏览器 DOM
;; 重建全是白做。这里按 window 缓存上次内容、等值即跳过；3 秒时限是兜底：
;; 前端重载（WebSocket 重连重建 view）后即使内容未变也会重推一次，避免
;; tab 条空白。只对 server 前端生效（ncurses 下 vs$ 解析为空）。
;; 重载幂等：orig 只记首次的上游函数，cache 跨重载复用（内容比对本身安全）。
(let ((cvt (vs$ :lem-server "CHANGE-VIEW-TO-HTML")))
  (when (and cvt (fboundp cvt))
    (let ((orig (or (get cvt 'vs-cvt-orig) (symbol-function cvt)))
          (cache (or (get cvt 'vs-cvt-cache)
                     (setf (get cvt 'vs-cvt-cache)
                           (make-hash-table :test 'eq :weakness :key)))))
      (setf (symbol-function cvt)
            (lambda (window content)
              (let* ((now (get-internal-real-time))
                     (cell (gethash window cache))
                     (skip (and cell (equal (car cell) content)
                                (< (- now (cdr cell))
                                   (* 3 internal-time-units-per-second)))))
                (unless skip
                  (setf (gethash window cache) (cons content now))
                  (funcall orig window content)))))
      (setf (get cvt 'vs-cvt-orig) orig))))

;; ATTRIBUTE-FOREGROUND 疯弹窗修复（上游 server 前端缺陷）：webview 渲染链
;; put() → ensure-attribute(attr nil)，attr=NIL（无 :attribute 的 insert-string
;; 普遍如此）时兜底条件 *background-color-of-drawing-window* 恒 NIL（server
;; 前端从不 setf，src/interface.lisp L77 defvar nil；ncurses 侧同变量由其自身
;; 渲染路径赋值）→ attribute 保持 NIL → attribute-to-hash(NIL) →
;; attribute-foreground(NIL) → no-applicable-method，每次重绘弹一个错误窗。
;; 修法：把该变量置为主题工作台底色（40/46 load 期已读 *vs-theme-mode*，
;; 此处同源取值），NIL attr 兜底为带底色的 attribute 对象，弹窗绝迹。
;; 注：只影响「无属性文本」的兜底渲染色，正常属性文本不受影响。
(let ((bg (if (eq *vs-theme-mode* :dark) "#1F1F1F" "#FFFFFF")))
  (vs-setglobal :lem-if "*BACKGROUND-COLOR-OF-DRAWING-WINDOW*" bg))

;; VSCode Status Bar 风格：左（ 分支）· 右（Ln,Col / 编码 / EOL / 语言）
;; git 分支查询必须缓存 + 过期异步重查：SBCL 大堆镜像上 fork+exec 一次
;; git 实测 ~84ms，而 modeline 随每个命令重绘——同步重查等于每 TTL 到期
;; 卡编辑线程一次。过期时本帧先返旧值、后台线程重查后经 send-event 回
;; 写落表（下次重绘即新值，最多一帧陈旧）；40-explorer 的 git 异步同款
;; 范式。按目录单飞：在途集合防重复 spawn；查询幂等，回写无条件落表。
(defparameter *vs-branch-cache* (make-hash-table :test 'equal)
  "目录 namestring → (分支名 . 查询时刻 universal-time)。")
(defparameter *vs-branch-cache-ttl* 30 "秒内重绘免 fork，过期走异步重查。")
(defparameter *vs-branch-refreshing* (make-hash-table :test 'equal)
  "在途集合：目录 namestring → t（采集线程存活期间）。")
(defparameter *vs-branch-deliver* nil
  "投递槽：(目录key 分支名 时刻)，单目录单飞下同一时刻至多一个生产者。")

(defun vs-branch-commit ()
  "编辑线程回写：投递槽落缓存表。后台线程绝不直接碰编辑状态。"
  (let ((cell *vs-branch-deliver*))
    (setf *vs-branch-deliver* nil)
    (when cell
      (destructuring-bind (key branch stamp) cell
        (remhash key *vs-branch-refreshing*)
        (setf (gethash key *vs-branch-cache*) (cons branch stamp))))))

(defun vs-branch-refresh-async (key)
  "后台采集：同步跑 git（阻塞的是采集线程），解析后 send-event 回写。"
  (setf (gethash key *vs-branch-refreshing*) t)
  (sb-thread:make-thread
   (lambda ()
     (handler-case
         (let ((branch (string-trim
                        '(#\Newline #\Space)
                        (uiop:run-program
                         (list "git" "-C" key "rev-parse" "--abbrev-ref" "HEAD")
                         :output '(:string :stripped t)
                         :ignore-error-status t))))
           (setf *vs-branch-deliver* (list key branch (get-universal-time)))
           (if (and (boundp '*vs-send-event*) *vs-send-event*)
               (funcall *vs-send-event* #'vs-branch-commit)
               (remhash key *vs-branch-refreshing*)))
       (serious-condition (e)
         (vs-trace "modeline git 采集线程异常: ~A" e)
         (remhash key *vs-branch-refreshing*))))
   :name "vs-modeline-git-branch"))

(defun vs-git-branch (dir)
  (let* ((key (namestring dir))
         (cell (gethash key *vs-branch-cache*)))
    (if (and cell (<= (- (get-universal-time) (cdr cell))
                      *vs-branch-cache-ttl*))
        (car cell)
        (progn
          (unless (gethash key *vs-branch-refreshing*)
            (vs-branch-refresh-async key))
          (and cell (car cell))))))

(defun vscode-modeline-branch (window)
  (ignore-errors
    (let* ((buffer (window-buffer window))
           (file (buffer-filename buffer))
           (dir (if file
                    (make-pathname :directory (pathname-directory file))
                    (buffer-directory buffer))))
      (when dir
        (let ((branch (vs-git-branch dir)))
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
;; line-wrap 关闭（VSCode 默认不换行；Alt+Z 切换见下 vscode-toggle-line-wrap，
;; 绑在 70-keybindings 的 M-z）
(vs-setvar :lem "LINE-WRAP" nil)

;; 换行开关（VSCode Alt+Z；toggle 全局编辑器变量，当前 buffer 立即生效，
;; 新 buffer 继承全局值）。必须是 define-command 产物才能绑键。
(define-command vscode-toggle-line-wrap () ()
  (let ((sym (vs$ :lem "LINE-WRAP")))
    (when sym
      (setf (variable-value sym :global)
            (not (variable-value sym :global)))
      (message "自动换行: ~A"
               (if (variable-value sym :global) "开" "关")))))

;; 鼠标滚轮速度（上游 *SCROLL-SPEED* 默认 3 行/格；VSCodium 侧滚轮一格
;; 多行，对齐其手感提到 6。special variable，走 vs-setglobal）。
(vs-setglobal :lem-core "*SCROLL-SPEED*" 6)

;; 右键命令菜单（VSCode 右键语义）：上游鼠标键不走 keymap 模型
;; （define-key 不接受 Mouse-Right 键串，parse error；MOUSE-BUTTON-DOWN-
;; FUNCTIONS 在本构建未绑定），改挂 HANDLE-MOUSE-BUTTON-DOWN 的 :around
;; 方法——右键按下时先 call-next-method 走原分发（保留定位/选区等默认
;; 行为），再调自研 VSCODE-CONTEXT-MENU（75-context-menu，prompt 过滤
;; 菜单）。BUTTON 槽取值前端不一致：ncurses 合成事件为 :RIGHT，真机
;; webview 右键为 BUTTON-3 符号（trace 实测），故按名字比对。
;;
;; 手法注意：不能 setf 上游 generic 的 symbol-function（LEM-CORE 包锁，
;; 配置加载期的逐 form 容错会静默吞掉整个 form，v20 实测），defmethod
;; :around 是 CLOS 标准挂接，不触发包锁。defmethod 为宏，运行时动态
;; 定义须 eval 构造（与 80-modes-base 的 vs-hook-add 同一手法）。菜单
;; 命令在回调体内动态解析（75 后于 60 加载，加载期解析必空）。
(defun vs-right-click-p (event btn-reader)
  "右键判定：BUTTON 槽按符号名比对（:RIGHT / BUTTON-3，大小写无关）。"
  (let ((b (ignore-errors (funcall btn-reader event))))
    (and (symbolp b)
         (let ((n (string-upcase (string b))))
           (or (string= n "RIGHT") (string= n ":RIGHT")
               (string= n "BUTTON-3") (string= n "BUTTON3")
               (string= n "RIGHT-BUTTON"))))))

;; 重载幂等挂接：defmethod 产物登记——重载时先摘除上次自己定义的方法
;; 再重新 defmethod。CLOS 对同 qualifiers+specializers 的 defmethod 本是
;; 替换语义（20260531 构建实测重载计数不变），此处的显式摘挂是幂等
;; 保障：specializer 文本一旦漂移（改参数特化）替换即失效成叠加。
;; 只摘本配置登记的 method 对象，绝不触碰上游/其他扩展的方法；
;; method 对象失效（已脱离 gf 等）一律 ignore-errors 兜底——最坏退化为
;; 替换语义本身的行为，不会崩。SBCL 的 defmethod 求值返回 method 对象。
(defun vs-replace-method (key new-method)
  (let ((old (get key 'vs-owned-method)))
    (when (typep old 'method)
      (ignore-errors
        (let ((gf (method-generic-function old)))
          (when gf (remove-method gf old))))))
  (setf (get key 'vs-owned-method)
        (when (typep new-method 'method) new-method))
  new-method)

;; 注意：菜单不能在鼠标分发里同步调——prompt 在 button-down 上下文
;; 内起不来（ignore-errors 吞掉，真机右键 trace 走但菜单不现，
;; 2026-09-04 实测）。改走 send-event 延后到编辑线程（探针链同款
;; 手法），右键即返，菜单随后弹出。
(let ((gf-name (vs$ :lem-core "HANDLE-MOUSE-BUTTON-DOWN"))
      (btn (vs$ :lem-core "MOUSE-EVENT-BUTTON"))
      (send (vs$ :lem "SEND-EVENT")))
  (when (and gf-name btn)
    (vs-replace-method
     :vs-right-click-menu
     (eval `(defmethod ,gf-name :around (buffer event &key)
             (let ((res (multiple-value-list (call-next-method))))
               (when (vs-right-click-p event ',btn)
                 (vs-trace "right-click menu fired")
                 (let ((menu (vs$ :lem-user "VSCODE-CONTEXT-MENU")))
                   (when (and menu (fboundp menu))
                     (if (and ',send (fboundp ',send))
                         (ignore-errors
                          (funcall ',send (lambda () (funcall menu))))
                         (ignore-errors (funcall menu))))))
               (values-list res)))))))

;; hover 文档异步化：mousemove 在 webview 前端约 60 事件/秒，而
;; TEXT-DOCUMENT/HOVER 是**同步** LSP 请求（本地 server 数十 ms、索引中
;; 可达百 ms）——逐事件同步查询会占满编辑线程，表现为鼠标划过代码即整体
;; 卡顿。旧版按点位 300ms 节流只挡「同一点重复查」，跨点移动仍逐字符
;; 发起请求（扫过一行 = 几十次阻塞往返），故重写。
;; 新模型「投递 + 防抖 + 单例采集线程」：mousemove 只登记待查位置（零解析
;; 零阻塞），后台线程在鼠标静止一个防抖窗后发一次查询，经 send-event 回
;; 编辑线程显示——快速扫过时 pending 被连续覆盖、只在最后落点查一次。
;; 与 modeline git 分支采集同款范式：后台线程绝不直接碰编辑状态。
(defvar *vs-hover-pending* nil
  "待查位置 (buffer . buffer 内绝对位置)。编辑线程写、采集线程读后清空。")
(defvar *vs-hover-worker* nil
  "单例采集线程（常驻；空闲时每防抖窗醒一次，开销可忽略）。")
(defparameter *vs-hover-debounce* 0.12
  "鼠标静止多久后发起查询（秒）。VSCode 的 hover 默认延迟 300ms，此值快于它。")

(defun vs-hover-deliver (cell)
  "编辑线程回写：定位到 CELL 并发起一次同步 LSP hover，显示文档 overlay。
位置可能已失效（buffer 已关闭 / 文本已改），逐层校验后静默跳过。"
  (ignore-errors
    (destructuring-bind (buffer . position) cell
      (when (and (bufferp buffer) (member buffer (buffer-list)))
        (with-point ((pt (buffer-point buffer)))
          (when (move-to-position pt position)
            (let ((hover (or (vs$ :lem-lsp-mode "TEXT-DOCUMENT/HOVER")
                             (vs$ :lem-lsp-mode/lsp-mode "TEXT-DOCUMENT/HOVER")))
                  (update (vs$ :lem-core "UPDATE-HOVER-OVERLAY"))
                  (find-ov (vs$ :lem-core "FIND-OVERLAY-THAT-CAN-HOVER"))
                  (set-msg (vs$ :lem-core "SET-HOVER-MESSAGE")))
              (when (and hover update find-ov set-msg)
                (let ((doc (funcall hover pt)))
                  (when doc
                    (vs-trace "hover doc fired")
                    (funcall update pt)
                    (let ((ov (funcall find-ov pt)))
                      (when ov (funcall set-msg ov doc)))))))))))))

(defun vs-hover-worker-loop ()
  (loop
    (sleep *vs-hover-debounce*)
    (let ((cell *vs-hover-pending*))
      (when cell
        (setf *vs-hover-pending* nil)
        (let ((send (vs$ :lem "SEND-EVENT")))
          (when (and send (fboundp send))
            (ignore-errors
              (funcall send (lambda () (vs-hover-deliver cell))))))))))

(defun vs-hover-request (buffer position)
  "编辑线程调用：登记待查位置，并按需拉起常驻采集线程。"
  (setf *vs-hover-pending* (cons buffer position))
  (unless (and *vs-hover-worker* (sb-thread:thread-alive-p *vs-hover-worker*))
    (setf *vs-hover-worker*
          (sb-thread:make-thread #'vs-hover-worker-loop
                                 :name "vs-hover-doc"))))

(defun vs-hover-mouse-position (window x y)
  "鼠标窗口内坐标 → (buffer . buffer 内绝对位置)。
上游 GET-POINT-FROM-WINDOW-WITH-COORDINATES 是无副作用的换算（返回临时
point）；坐标不可得（合成事件 / window 为 nil）时回退当前光标位置。
旧实现直接用 current-point，导致悬停查的始终是光标处文档、鼠标移到别处
文档不变——hover 形同虚设。"
  (let ((pt (and window x y
                 (ignore-errors
                   (funcall (vs$ :lem-core
                                 "GET-POINT-FROM-WINDOW-WITH-COORDINATES")
                            window x y)))))
    (if pt
        (cons (point-buffer pt) (position-at-point pt))
        (cons (current-buffer) (position-at-point (current-point))))))

(defun vs-left-click-p (event btn-reader)
  "左键判定：BUTTON 槽按符号名比对（:LEFT / BUTTON-1 / BUTTON1）。vs-right-click-p 同款手法。"
  (let ((b (ignore-errors (funcall btn-reader event))))
    (and (symbolp b)
         (let ((n (string-upcase (string b))))
           (or (string= n "LEFT") (string= n ":LEFT")
               (string= n "BUTTON-1") (string= n "BUTTON1"))))))

 (let ((gf-name (vs$ :lem-core "HANDLE-MOUSE-HOVER")))
   (when gf-name
     (vs-replace-method
      :vs-hover-enhance
      (eval `(defmethod ,gf-name :around (buffer event &key window x y)
              ;; primary 在合成事件/无 hover 上下文时可能抛错，先包住，
              ;; 保证增强分支总有机会执行（右键 around 同理已包）。
              (let ((res (ignore-errors
                           (multiple-value-list (call-next-method)))))
                (ignore-errors
                 (let ((btn (vs$ :lem-core "MOUSE-EVENT-BUTTON"))
                       (setm (vs$ :lem-core "SET-CURSOR-MARK"))
                       (bmp (vs$ :lem "BUFFER-MARK-P")))
                    ;; 拖拽起点（先执行，保证 mark 在文档链之前就位；
                    ;; 独立 ignore-errors，与文档链互不连累）
                    (ignore-errors
                      (when (and btn setm bmp
                                 (vs-left-click-p event btn)
                                 (not (ignore-errors (funcall bmp buffer))))
                        (vs-trace "drag mark set")
                        (funcall setm (current-point)
                                 (copy-point (current-point)))))
                   ;; LSP 文档：只投递位置——符号解析与同步请求都在
                   ;; VS-HOVER-DELIVER 内做，热路径零解析零阻塞。
                   ;; 位置取**鼠标坐标**换算（见 VS-HOVER-MOUSE-POSITION），
                   ;; 而非 current-point：否则悬停查的是光标处文档、鼠标移到
                   ;; 别处文档不变（旧实现即如此，hover 形同虚设）
                   (destructuring-bind (hb . hp)
                       (vs-hover-mouse-position window x y)
                     (vs-hover-request hb hp))))
                (values-list res)))))))

;; --- nightly 增益 ---

;; 项目 grep 后端换 rg（Shift-C-f）：nightly 的 grep 把提示符整串交给
;; shell 执行，生效面是 *last-query*（提示符初始串）；*grep-command* /
;; *grep-args* 只是默认拼装源，一并设保持一致。三者均为直接引用的
;; special variable（不走 variable-value plist），必须 vs-setglobal。
;; --vimgrep 输出 path:line:col:text，grep 结果行解析兼容；rg 尊重
;; .gitignore，非 git 目录也能用。
;; --hidden 必须加：rg 默认跳过以 . 开头的隐藏目录/文件，而 Guix/Nix 与
;; 大量工具链的配置都在 .config/ 下——不加则在这些目录里搜索恒为空
;; （本仓库 dotfiles/mutable/lem/.config/ 即是一例，2026-09-11 实测）。
;; VSCode 搜索默认包含隐藏文件（仅 files.exclude 掉 **/.git），此改动与之一致。
(vs-setglobal :lem/grep "*GREP-COMMAND*" "rg")
(vs-setglobal :lem/grep "*GREP-ARGS*" "--vimgrep --hidden")
(vs-setglobal :lem/grep "*LAST-QUERY*" "rg --vimgrep --hidden ")

;; 保存时格式化（nightly *auto-format*，format.lisp 直接引用该 special
;; variable）：special variable，走 vs-setglobal。触发点在上游
;; after-save-hook——保存落盘 → hook 回调 (format-buffer :buffer b :auto t)
;; → formatter-impl 按 mode 名符号 eql 分派 → 结尾 save-without-hooks
;; 回写格式化结果；auto 路径 formatter 抛错一律 handler-case 静默吞掉，
;; 二次保存走 write-hook 豁免（不会无限递归）。
;;
;; 注册面 = 上游自带 + 配置补注册两条线：
;; - 上游 define-major-mode 的 :formatter（镜像内置即注册，见 extensions/
;;   各 mode 的 define-major-mode）：lisp-mode=indent-buffer（纯 Lisp 缩进
;;   零依赖）、rust-mode=rustfmt（filter-buffer 管道）——这两条本机可用；
;;   c-mode=clang-format（-i 改文件 + revert）、go-mode=gofmt（-w 改文件
;;   + revert）——「改文件后 revert 回读」型在同秒内改写时必失效（见下）；
;;   json-mode/js-mode=prettier（本机未装＝死注册，无害：工具缺失按
;;   非零状态处理，buffer 原文不动）。
;;   上游 go/c 缺陷（2026-09-04 ncurses 实测）：改文件型 formatter 跑在
;;   after-save-hook 内，此时本次保存刚 update-changed-disk-date，工具又
;;   在同一秒内改写文件——SBCL file-write-date 秒级粒度，revert-buffer 的
;;   changed-disk-p 判否 → 跳过回读 → format-buffer 结尾 save-without-hooks
;;   把脏 buffer 写回，格式化结果被覆盖丢失。故 c/go 由配置以同 specializer
;;   替换语义覆盖为 stdin→stdout 管道（不碰文件、无竞态）。
;; - 配置补注册（vs-register-formatter，stdin→stdout 管道，本机实测）：
;;   nix=nixfmt（modes/nix.lisp）、sh=shfmt（modes/shell.lisp）、
;;   json=clang-format（modes/json.lisp，:FILE 注入 buffer 路径做
;;   .clang-format/.clang-format 发现与语言判定）、c=clang-format
;;   （modes/cc.lisp，覆盖上游竞态版）、go=gofmt（modes/go.lisp，同）。
;;   本机未装、暂不注册的补装位：python→ruff、lua→stylua（装好后在本
;;   目录对应语言文件加一行 vs-register-formatter 即可）；fish_indent 因
;;   lem 无 fish-mode 无处挂接，不注册。
(vs-setglobal :lem "*AUTO-FORMAT*" t)

;; 落盘清理（VSCode files.insertFinalNewline / files.trimTrailingWhitespace
;; 的对应物）：两者都是 editor variable（定义在 :lem-core/commands/file，
;; 前者导出、后者未导出——vs$ 走 find-symbol 均可解析）。save-buffer 内
;; 以 :default + buffer 读取，buffer 无 local 值时回落全局值，故 vs-setvar
;; 设 :global 即生效（2026-09-11 核对上游 src/common/var.lisp 读路径）。
(vs-setvar :lem-core/commands/file "ADD-NEWLINE-AT-EOF-ON-WRITING-FILE" t)
(vs-setvar :lem-core/commands/file "DELETE-TRAILING-WHITESPACE-ON-WRITING-FILE" t)

;; 自动保存（VSCodium files.autoSave=onFocusChange 的对应物）：
;; 上游 lem/auto-save 全局 minor mode：idle 定时 + 每 256 键 checkpoint
;; 写回真实文件。webview 前端 timer 不 fire，idle 路径失效，实际靠
;; 按键计数路径（约 256 键一存）；changed-disk-p 守卫 + 只碰已存盘
;; 文件（未存盘新 buffer 不写）。*make-backup-files* 保持 nil，不产
;; 生 ~ 备份文件。2026-09-04 ncurses 探针：符号存在、启用无错。
(let ((mode (vs$ :lem/auto-save "AUTO-SAVE-MODE")))
  (when (and mode (fboundp mode))
    (funcall mode t)))
;; 切 buffer 自动保存（VSCode files.autoSave=onFocusChange 的对应物）：
;; *switch-to-buffer-hook* 在切走后触发，参数是新 buffer；保存的是
;; 「切走前」的 buffer——用 *vs-prev-buffer* 追踪（post-command 每命令
;; 更新，开销可忽略）。只碰已存盘且被修改的 buffer（save-buffer 内部
;; 已判 modified+filename，未存盘新 buffer 不写）。
(defvar *vs-prev-buffer* nil)

(defun vs-autosave-on-switch (new-buffer)
  (declare (ignore new-buffer))
  (ignore-errors
    (when (and *vs-prev-buffer*
               (bufferp *vs-prev-buffer*)
               (member *vs-prev-buffer* (buffer-list))
               (buffer-modified-p *vs-prev-buffer*)
               (buffer-filename *vs-prev-buffer*))
      (save-buffer *vs-prev-buffer*))))

(defun vs-track-prev-buffer ()
  (setf *vs-prev-buffer* (current-buffer)))

(let ((hook (or (vs$ :lem "*SWITCH-TO-BUFFER-HOOK*")
                (vs$ :lem-core "*SWITCH-TO-BUFFER-HOOK*")
                (vs$ :lem-core/display "*SWITCH-TO-BUFFER-HOOK*"))))
  (when (and hook (boundp hook))
    (eval `(add-hook ,hook 'vs-autosave-on-switch))))
(add-hook *post-command-hook* 'vs-track-prev-buffer)

;; formatter 注册器（modes/ 各语言文件调用；本模块先于 modes/ 加载）。
;; register-formatter 是 :lem-core 导出宏，不能 funcall，运行时注册走
;; eval 展开（与 80-modes-base 的 vs-hook-add 同一手法）；mode 符号经
;; vs$ 动态解析，任一缺失整条跳过。argv 中的关键字 :FILE 在运行时替换
;; 为 buffer 文件名（供 clang-format --assume-filename 做 .clang-format
;; 发现与语言判定；buffer 无文件名时该次格式化整体跳过）。handler 全文
;; 经 argv 管道替换，失败兜底三层：ignore-errors（工具不存在等启动异
;; 常）、非零退出、输出为空或与原文逐字相同——任一命中都不动 buffer，
;; 绝不丢用户代码；成功才替换并保留行列（照抄上游 filter-buffer 的点
;; 恢复）。重载幂等：同 specializer 的 defmethod 是 CLOS 替换语义，不叠加。
(defun vs-register-formatter (mode-pkg mode-name argv)
  (let ((rf (vs$ :lem-core "REGISTER-FORMATTER"))
        (mode (vs$ mode-pkg mode-name)))
    (when (and rf mode)
      (eval
       `(,rf ,mode
             (lambda (buffer)
               (let* ((argv (mapcar (lambda (a)
                                      (if (eq a :file)
                                          (buffer-filename buffer)
                                          a))
                                    ',argv))
                      (text (buffer-text buffer))
                      status
                      out)
                 (unless (member nil argv)
                   (setf out
                         (with-output-to-string (o)
                           (with-input-from-string (i text)
                             (multiple-value-bind (v e s)
                                 (ignore-errors
                                   (uiop:run-program argv
                                                     :input i
                                                     :output o
                                                     :error-output :string
                                                     :ignore-error-status t))
                               (declare (ignore v e))
                               (setf status s)))))
                   (when (and (eql status 0)
                              (plusp (length out))
                              (string/= out text))
                     (let ((pt (buffer-point buffer))
                           (start (buffer-start-point buffer))
                           (end (buffer-end-point buffer)))
                       (let ((line (line-number-at-point pt))
                             (charpos (point-charpos pt)))
                         (delete-between-points start end)
                         (insert-string start out)
                         (move-to-line pt line)
                         (line-offset pt 0 charpos))))))))))))

;; 相对行号（当前行保持绝对行号；*relative-line* 为直接引用的
;; special variable，见 line-numbers.lisp）
(vs-setglobal :lem/line-numbers "*RELATIVE-LINE*" t)

;; 插件通道（lem-extension-manager + 内置 Quicklisp）：镜像构建期把
;; *PACKAGES-DIRECTORY* 固化成了 /root/.config/lem/packages/（构建容器
;; HOME 残留，warm-boot 后成常量），不可写、装包必炸，必须重设到用户目录。
(vs-setglobal :lem-extension-manager "*PACKAGES-DIRECTORY*"
              (merge-pathnames ".config/lem/packages/" (user-homedir-pathname)))
;; 制表宽 2（VSCodium editor.tabSize="2" 的对应物）：tab-width 是 tab 字符
;; 显示宽度 + 列运算基准（ncurses 探针初值 8）；各 mode 缩进走自有逻辑
;;（python-mode 源码内无 tab-width 引用），不受影响。
(vs-setvar :lem "TAB-WIDTH" 2)

;; 括号匹配高亮（VSCode bracket match 的对应物）：上游 show-paren 包在
;; 60 加载期尚未就绪（ncurses 探针：load 期 vs$ 解析为空，全量加载后才
;; 出现），故首命令时补挂钩子、随后自摘（90-startup 同款一次性
;; post-command 模式）。show-paren 的 enable 缺省 t，但刷新走 idle
;; timer——webview 前端 timer 不 fire，鼠标钩子只覆盖点击；补 post-command
;; 钩子每命令刷新（单个 overlay，开销可忽略）。包缺失不挂钩（vs-call 的
;; 缺失告警会每命令刷屏，故存在性 + member 双门控）。
;; git-gutter 曾在此同批启用，真机验证回退：左缘是单槽位 dispatch
;;（compute-left-display-area-content 按合成 mode 类单方法胜出），gutter
;; 启用后行号被顶掉（ncurses 探针：line-numbers-mode 明明 active）。
;; 行号是核心 chrome 保留，gutter 降级：文件级 git 染色（侧栏树/modeline
;; 分支）不受影响。要行级 diff 看 legit（C-G）。
(defun vs-show-paren-tick ()
  (vs-call :lem/show-paren "UPDATE-SHOW-PAREN"))
(defun vs-late-vscode-gains ()
  (ignore-errors
    (when (and (vs$ :lem/show-paren "UPDATE-SHOW-PAREN")
               (not (member 'vs-show-paren-tick *post-command-hook*
                            :test #'eq)))
      (add-hook *post-command-hook* 'vs-show-paren-tick)))
  (eval '(remove-hook *post-command-hook* 'vs-late-vscode-gains)))
(add-hook *post-command-hook* 'vs-late-vscode-gains)
