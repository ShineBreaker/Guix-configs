;;; modules/76-whichkey.lisp — which-key 式前缀提示（上游 transient 扩展接线）
;;;
;;; 按下任何前缀键（C-x / C-c / M-g …）底部弹面板列出后续可用键，
;;; 序列完成回根自动消失——which-key 的核心交互。渲染完全复用上游
;;; extensions/transient（nightly 镜像内置编译，bottomside window，
;;; 非 floating，不踩 with-pop-up-typeout-window 移动键炸点），配置侧
;;; 只做两件事：
;;;   1. *transient-popup-delay* 置 0：默认 500ms 延迟显示走
;;;      make-timer/start-timer，webview 前端缺 timer tick 调度点
;;;      不 fire（AGENTS.md 第 4 节），面板将永不出现；0 走
;;;      show-transient-with-delay 的立即显示分支，绕开 timer。
;;;   2. 给按键路径上的前缀子 keymap 全量设 keymap-show-p：resolve-
;;;      transient-keymap 的显示条件是「该 keymap show-p」或
;;;      *transient-always-show*。不用 always-show（面板常驻吵闹，
;;;      且其 post-command 钩子每条命令后都会重绘整棵 root 面板）；
;;;      只标前缀子 keymap → 仅按键序列进行中显示，命令完成
;;;      （keymap-activate 回 *root-keymap*、其无 show-p → hide）即
;;;      消失。注意树结构（ncurses 实测）：*root-keymap* 是 prefixes=0
;;;      的空壳、只作 keymap-activate 的回根目标；真实绑定（C-x/C-c/
;;;      M-g 等 152 个前缀）全在 *global-keymap*——遍历入口收两棵树，
;;;      gk 是生效目标。两个入口本身绝不设 show-p，否则面板常驻。
;;;
;;; 依赖：00-utils（vs$ / vs-setglobal / vs-warn / vs-trace）必须先行；
;;; 70-keybindings 必须先行——遍历在加载期执行，vs-bind 全部落完键
;;; root 前缀树才完整（80-modes-base / 90-startup 无 global 前缀绑定，
;;; 76 之后无缺口）。基于上游 LEM/TRANSIENT：KEYMAP-SHOW-P 未导出且
;;; 其 setter 是 (SETF KEYMAP-SHOW-P) 列表形函数名（find-symbol 拿不
;;; 到 setf 名），经 fdefinition 构造调用；全部符号动态解析，镜像缺
;;; 该扩展时整模块降级只告警一次，不影响其余配置加载。

(in-package :lem-user)

(defun vs-whichkey-walk (entries km-class setter prefixes-fn suffix-fn children-fn)
  "对 ENTRIES（各入口 keymap 树）递归下钻：prefix 的 suffix 为
keymap、或 child keymap，一律设 show-p 并继续下钻（C-x 4 类二层
中间前缀同覆盖）。入口对象本身绝不设 show-p——它们是「根」：设了
面板就常驻（回根 keymap-activate 传 *root-keymap*）。入口判定走
entry-set 而非调用时序：树间可能交叉引用（实测 *global-keymap*
可从 root 树的 children 链到达），入口若经他树路径再被访问，仍须
豁免。visited 集合 eq 防环、跨树去重。返回设置计数。KM-CLASS 经
vs$ 解析传入：keymap 类符号的包可见性不做静态假设。"
  (let ((visited (make-hash-table :test 'eq))
        (entry-set (make-hash-table :test 'eq))
        (count 0))
    (labels ((walk (km)
               (when (and (typep km km-class) (not (gethash km visited)))
                 (setf (gethash km visited) t)
                 (unless (gethash km entry-set)
                   (funcall setter t km)
                   (incf count))
                 (dolist (p (ignore-errors (funcall prefixes-fn km)))
                   (let ((s (ignore-errors (funcall suffix-fn p))))
                     (when (typep s km-class) (walk s))))
                 (dolist (c (ignore-errors (funcall children-fn km)))
                   (walk c)))))
      (dolist (entry entries)
        (when (typep entry km-class)
          (setf (gethash entry entry-set) t)
          (walk entry))))
    count))

(defun vs-whichkey-install ()
  "接线：delay=0 + 按键路径上前缀树全量 show-p。任一依赖符号缺失
（镜像无 transient 扩展、或 keymap 模型不符）只告警一次并整体跳过。
*ROOT-KEYMAP* / *GLOBAL-KEYMAP* 是 special variable，vs$ 取回的是
符号，须 symbol-value 解引用成 keymap 对象（与 vs-setglobal 的解
引用语义同源）。两棵树都要：*root-keymap* 是 keymap-activate 回根
的空壳（实测 prefixes=0），真实绑定全在 *global-keymap*（152 个
前缀，含 C-x/C-c/M-g）——遍历入口收两棵，gk 是生效目标。"
  (let* ((delay-sym   (vs$ :lem/transient "*TRANSIENT-POPUP-DELAY*"))
         (getter      (vs$ :lem/transient "KEYMAP-SHOW-P"))
         (km-class    (or (vs$ :lem "KEYMAP") (vs$ :lem-core "KEYMAP")))
         (prefixes-fn (vs$ :lem-core "KEYMAP-PREFIXES"))
         (suffix-fn   (vs$ :lem-core "PREFIX-SUFFIX"))
         (children-fn (vs$ :lem-core "KEYMAP-CHILDREN"))
         (root-sym    (vs$ :lem-core "*ROOT-KEYMAP*"))
         (gk-sym      (vs$ :lem-core "*GLOBAL-KEYMAP*"))
         (root        (and root-sym (boundp root-sym) (symbol-value root-sym)))
         (gk          (and gk-sym (boundp gk-sym) (symbol-value gk-sym)))
         (entries     (remove-if-not
                       (lambda (k) (typep k km-class))
                       (list root gk))))
    (if (and delay-sym getter km-class prefixes-fn suffix-fn children-fn
             entries
             (boundp delay-sym)
             (fboundp getter)
             (fboundp prefixes-fn) (fboundp suffix-fn) (fboundp children-fn)
             (fboundp (list 'setf getter)))
        (let ((n (vs-whichkey-walk entries
                                   km-class
                                   (fdefinition (list 'setf getter))
                                   prefixes-fn suffix-fn children-fn)))
          (vs-setglobal :lem/transient "*TRANSIENT-POPUP-DELAY*" 0)
          (vs-trace "76-whichkey: show-p 已设 ~A 个前缀 keymap（delay=0）" n)
          n)
        (vs-warn (list :lem/transient
                       "TRANSIENT-依赖缺失，which-key 模块整体降级")))))

;; 加载期执行：此刻 70-keybindings 已落完全部 vs-bind，root 树完整
(vs-whichkey-install)

;; 弹窗期间上游自动启停 transient-mode（global minor），其局部键
;; M-Shift-方向 滚动面板——不经 vs-bind，收编进帮助页
(vs-help-note "ui" "M-Shift-方向" "前缀提示面板滚动（面板弹出期间有效）")
