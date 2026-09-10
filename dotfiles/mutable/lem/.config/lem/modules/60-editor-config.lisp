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
;; git 分支查询必须缓存：SBCL 大堆镜像上 fork+exec 一次 git 实测 ~84ms，
;; 而 modeline 随每个命令重绘——不缓存等于每键付一次 fork 开销（按键
;; 卡顿主因）。按目录缓存 + TTL 过期重查；切换分支后最多 TTL 秒陈旧。
(defparameter *vs-branch-cache* (make-hash-table :test 'equal)
  "目录 namestring → (分支名 . 查询时刻 universal-time)。")
(defparameter *vs-branch-cache-ttl* 30 "秒内重绘免 fork，过期后首次重绘同步重查。")

(defun vs-git-branch (dir)
  (let* ((key (namestring dir))
         (cell (gethash key *vs-branch-cache*)))
    (unless (and cell (<= (- (get-universal-time) (cdr cell))
                          *vs-branch-cache-ttl*))
      (setf cell (cons (string-trim
                        '(#\Newline #\Space)
                        (uiop:run-program
                         (list "git" "-C" key "rev-parse" "--abbrev-ref" "HEAD")
                         :output '(:string :stripped t)
                         :ignore-error-status t))
                       (get-universal-time))
            (gethash key *vs-branch-cache*) cell))
    (car cell)))

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

;; 悬停文档增强（VSCode 鼠标悬停语义）：around HANDLE-MOUSE-HOVER，
;; 先 call-next-method 走上游默认悬浮，再尝试 LSP 文档覆盖——取当前点
;; 调 LSP-HOVER（无 LSP 时返回 NIL 天然穿透），非空则经 hover overlay
;; 显示。overlay 链：UPDATE-HOVER-OVERLAY 落位 → FIND-OVERLAY-THAT-
;; CAN-HOVER 取 overlay → SET-HOVER-MESSAGE 写文本，全程 ignore-errors，
;; 任一环节缺失即退回上游默认行为。LSP-HOVER 传 point（v48 实测无 LSP
;; 时回 NIL；有 LSP 时行为由真机验证）。
(defun vs-left-click-p (event btn-reader)
  "左键判定：BUTTON 槽按符号名比对（:LEFT / BUTTON-1 / BUTTON1）。vs-right-click-p 同款手法。"
  (let ((b (ignore-errors (funcall btn-reader event))))
    (and (symbolp b)
         (let ((n (string-upcase (string b))))
           (or (string= n "LEFT") (string= n ":LEFT")
               (string= n "BUTTON-1") (string= n "BUTTON1"))))))

;; 拖拽选中（VSCode 左键拖拽语义）：上游 motion 走 RECEIVE-MOUSE-MOTION
;; （普通函数，无 around 挂接点），但 motion 下游必经 HANDLE-MOUSE-HOVER
;; （同 MOUSE-EVENT 事件，带 BUTTON 状态），故在 hover 的 around 里补：
;; 左键按下中且 mark 未激活 → 在当前点设 mark 起点，选区随光标延伸。
;; mark 已激活则不动（拖拽延续）；单击（无 motion）由上游默认处理。
;; 全程 ignore-errors，不影响 hover 文档链。
(let ((gf-name (vs$ :lem-core "HANDLE-MOUSE-HOVER")))
  (when gf-name
    (vs-replace-method
     :vs-hover-enhance
     (eval `(defmethod ,gf-name :around (buffer event &key)
             ;; primary 在合成事件/无 hover 上下文时可能抛错，先包住，
             ;; 保证增强分支总有机会执行（右键 around 同理已包）。
             (let ((res (ignore-errors
                          (multiple-value-list (call-next-method)))))
               (ignore-errors
                 (let ((hover (vs$ :lem-lsp-mode "LSP-HOVER"))
                       (update (vs$ :lem-core "UPDATE-HOVER-OVERLAY"))
                       (find-ov (vs$ :lem-core "FIND-OVERLAY-THAT-CAN-HOVER"))
                       (set-msg (vs$ :lem-core "SET-HOVER-MESSAGE"))
                       (btn (vs$ :lem-core "MOUSE-EVENT-BUTTON"))
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
                   ;; LSP 文档覆盖
                   (when (and hover update find-ov set-msg)
                     (let ((doc (funcall hover (current-point))))
                       (when doc
                         (vs-trace "hover doc fired")
                         (funcall update (current-point))
                         (let ((ov (funcall find-ov (current-point))))
                           (when ov
                             (funcall set-msg ov doc))))))))
               (values-list res)))))))

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

;; 自动保存（VSCodium files.autoSave=onFocusChange 的对应物）：
;; 上游 lem/auto-save 全局 minor mode：idle 定时 + 每 256 键 checkpoint
;; 写回真实文件。webview 前端 timer 不 fire，idle 路径失效，实际靠
;; 按键计数路径（约 256 键一存）；changed-disk-p 守卫 + 只碰已存盘
;; 文件（未存盘新 buffer 不写）。*make-backup-files* 保持 nil，不产
;; 生 ~ 备份文件。2026-09-04 ncurses 探针：符号存在、启用无错。
(let ((mode (vs$ :lem/auto-save "AUTO-SAVE-MODE")))
  (when (and mode (fboundp mode))
    (ignore-errors (funcall mode t))))

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
