;;; modules/30-themes.lisp — vscode-dark/light-modern 主题（运行时构造）
;;;
;;; 依赖：utils（vs-spec）；无下游依赖（explorer/problems 侧栏配色不经
;;; 主题，各自带 set-chrome 函数，切换时由 vscode-toggle-theme 回调）。
;;;
;;; 运行时构造 specs 而非编译期展开：杜绝包前缀符号缺失炸进程的风险。
;;; 色值权威源：
;;;   dark：microsoft/vscode dark_modern.json——
;;;     chrome 三元组：#181818（工作台镶边）/ #1F1F1F（编辑器/激活 tab）/ #2B2B2B（分隔线）
;;;     强调 #0078D4；文字三级 #FFFFFF / #CCCCCC / #9D9D9D
;;;   light：microsoft/vscode light_modern.json + light_plus.json + light_vs.json——
;;;     工作台 #F8F8F8 / 编辑器 #FFFFFF / 分隔线 #E5E5E5；强调 #005FB8；
;;;     文字 #3B3B3B / 次级 #616161 / tab 非激活 #868686；
;;;     行号 #6E7681 / 当前行 #171184；token 沿用 Light+（注释 #008000 /
;;;     关键字 #0000FF / 字符串 #A31515 / 数字 #098658 / 类型 #267F99 /
;;;     函数 #795E26 / 变量 #001080 / 常量 #0070C1 / 流程 #AF00DB）；
;;;     git 染色沿用 git 扩展声明值（modified #895503 / untracked #007100 /
;;;     deleted #AD0707 / conflict #AD0707 / ignored #8E8E90）。
;;;   标注 workbench light default 的三处（findMatch 系、diagnostic
;;;   warning/info）主题文件未定义，取工作台浅色默认值。
;;;
;;; M-x vscode-toggle-theme 在深浅之间切换（VSCode 命令面板
;;; Preferences: Color Theme 的对应物；不绑键，经 M-x 调用零冲突）。

(in-package :lem-user)

(defvar *vs-theme-mode* :dark
  "当前主题（:dark/:light）。defvar 而非 defparameter：reload 不重置，
toggle 的翻转基准才可信。启动恒为 :dark（历史行为不变）。")

(defun vs-theme-specs (mode)
  "按 MODE（:dark/:light）构造主题 specs（vs-spec 缺失符号自动跳过）。"
  (let ((dark (eq mode :dark)))
    (remove
     nil
     (list
      ;; 工作台
      (list :display-background-mode (if dark :dark :light))
      (list :foreground (if dark "#CCCCCC" "#3B3B3B")) ; editor.foreground
      (list :background (if dark "#1F1F1F" "#FFFFFF")) ; editor.background
      (list :inactive-window-background (if dark "#181818" "#F8F8F8"))
      ;; base16 抽象色（isearch 等内部 attribute 按 :baseXX 引用）
      (list :base00 (if dark "#1F1F1F" "#FFFFFF"))
      (list :base01 (if dark "#252526" "#F3F3F3"))
      (list :base02 (if dark "#2B2B2B" "#E5E5E5"))
      (list :base03 (if dark "#6E7681" "#767676"))
      (list :base04 (if dark "#868686" "#616161"))
      (list :base05 (if dark "#CCCCCC" "#3B3B3B"))
      (list :base06 (if dark "#D7D7D7" "#1F1F1F"))
      (list :base07 (if dark "#FFFFFF" "#000000"))
      (list :base08 (if dark "#F14C4C" "#F85149"))
      (list :base09 (if dark "#CE9178" "#A31515"))
      (list :base0A (if dark "#B5CEA8" "#098658"))
      (list :base0B (if dark "#23D18B" "#267F99"))
      (list :base0C (if dark "#4EC9B0" "#795E26"))
      (list :base0D (if dark "#569CD6" "#0000FF"))
      (list :base0E (if dark "#C586C0" "#AF00DB"))
      (list :base0F (if dark "#D7BA7D" "#0070C1"))
      ;; 光标 / 选区（editorCursor；selection #264F78 / light #ADD6FF）
      (vs-spec :lem "CURSOR" :background (if dark "#AEAFAD" "#000000"))
      (vs-spec :lem "REGION" :foreground nil
               :background (if dark "#264F78" "#ADD6FF"))
      ;; 行号（背景必须显式，否则用 :base01）
      (vs-spec :lem/line-numbers "LINE-NUMBERS-ATTRIBUTE"
               :foreground "#6E7681"
               :background (if dark "#1F1F1F" "#FFFFFF"))
      (vs-spec :lem/line-numbers "ACTIVE-LINE-NUMBER-ATTRIBUTE"
               :foreground (if dark "#CCCCCC" "#171184")
               :background (if dark "#1F1F1F" "#FFFFFF"))
      ;; isearch（上游 nightly 已删除 UNMATCH-ISEARCH-ATTRIBUTE；
      ;; light 值为 workbench light default）
      (vs-spec :lem/isearch "ISEARCH-HIGHLIGHT-ACTIVE-ATTRIBUTE"
               :foreground (if dark "#1F1F1F" "#000000")
               :background (if dark "#9E6A03" "#A8AC94"))
      (vs-spec :lem/isearch "ISEARCH-HIGHLIGHT-ATTRIBUTE"
               :foreground (if dark "#CCCCCC" "#000000")
               :background (if dark "#613214" "#EA5C0055"))
      ;; 语法高亮（dark：Dark+；light：Light+）
      (vs-spec :lem "SYNTAX-COMMENT-ATTRIBUTE"
               :foreground (if dark "#6A9955" "#008000"))
      (vs-spec :lem "SYNTAX-KEYWORD-ATTRIBUTE"
               :foreground (if dark "#569CD6" "#0000FF"))
      (vs-spec :lem "SYNTAX-STRING-ATTRIBUTE"
               :foreground (if dark "#CE9178" "#A31515"))
      (vs-spec :lem "SYNTAX-CONSTANT-ATTRIBUTE"
               :foreground (if dark "#4FC1FF" "#0070C1"))
      (vs-spec :lem "SYNTAX-FUNCTION-NAME-ATTRIBUTE"
               :foreground (if dark "#DCDCAA" "#795E26"))
      (vs-spec :lem "SYNTAX-VARIABLE-ATTRIBUTE"
               :foreground (if dark "#9CDCFE" "#001080"))
      (vs-spec :lem "SYNTAX-TYPE-ATTRIBUTE"
               :foreground (if dark "#4EC9B0" "#267F99"))
      (vs-spec :lem "SYNTAX-BUILTIN-ATTRIBUTE"
               :foreground (if dark "#569CD6" "#0000FF"))
      (vs-spec :lem "SYNTAX-WARNING-ATTRIBUTE"
               :foreground (if dark "#CCA700" "#BF8803"))
      ;; document 系（欢迎页/帮助页标题与链接）：上游 lem-default 主题把
      ;; header1-3/link 写死深色值，会遮掉 define-attribute 自带的 :light
      ;; 分支（白字白底隐身，欢迎页标题消失的根因）；此处按模式重设，
      ;; dark 沿用旧值零变化，light 取浅色对应值（header1 用
      ;; settings.headerForeground，链接系用 textLink #005FB8）。
      (vs-spec :lem "DOCUMENT-HEADER1-ATTRIBUTE"
               :foreground (if dark "#FFFFFF" "#1F1F1F") :bold t)
      (vs-spec :lem "DOCUMENT-HEADER2-ATTRIBUTE"
               :foreground (if dark "#90BEE1" "#005FB8") :bold t)
      (vs-spec :lem "DOCUMENT-HEADER3-ATTRIBUTE"
               :foreground (if dark "#BED6FF" "#005FB8") :bold t)
      (vs-spec :lem "DOCUMENT-LINK-ATTRIBUTE"
               :foreground (if dark "#90BEE1" "#005FB8") :underline t)
      ;; 诊断（light warning/info 取 workbench light default）
      (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-ERROR-ATTRIBUTE"
               :foreground (if dark "#F14C4C" "#F85149"))
      (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-WARNING-ATTRIBUTE"
               :foreground (if dark "#CCA700" "#BF8803"))
      (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-INFORMATION-ATTRIBUTE"
               :foreground (if dark "#59A4F9" "#1A85FF"))
      (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-HINT-ATTRIBUTE"
               :foreground (if dark "#9D9D9D" "#616161"))
      ;; modeline → VSCode Status Bar（dark #181818 条 / light #F8F8F8 条）
      (vs-spec :lem "MODELINE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground (if dark "#CCCCCC" "#3B3B3B"))
      (vs-spec :lem "MODELINE-INACTIVE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground "#868686")
      (vs-spec :lem "MODELINE-NAME-ATTRIBUTE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground (if dark "#CCCCCC" "#3B3B3B"))
      (vs-spec :lem "MODELINE-MAJOR-MODE-ATTRIBUTE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground (if dark "#CCCCCC" "#3B3B3B"))
      (vs-spec :lem "MODELINE-MINOR-MODES-ATTRIBUTE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground "#868686")
      (vs-spec :lem "MODELINE-POSITION-ATTRIBUTE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground (if dark "#CCCCCC" "#3B3B3B"))
      (vs-spec :lem "MODELINE-POSLINE-ATTRIBUTE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground (if dark "#CCCCCC" "#3B3B3B"))
      (vs-spec :lem "INACTIVE-MODELINE-NAME-ATTRIBUTE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground "#868686")
      (vs-spec :lem "INACTIVE-MODELINE-MAJOR-MODE-ATTRIBUTE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground "#868686")
      (vs-spec :lem "INACTIVE-MODELINE-MINOR-MODES-ATTRIBUTE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground (if dark "#6E7681" "#616161"))
      (vs-spec :lem "INACTIVE-MODELINE-POSITION-ATTRIBUTE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground "#868686")
      (vs-spec :lem "INACTIVE-MODELINE-POSLINE-ATTRIBUTE"
               :background (if dark "#181818" "#F8F8F8")
               :foreground "#868686")
      ;; frame-multiplexer → VSCode Tab 栏（默认开启、带编号切换，是 VSCode
      ;; Tab 的正确对应物；light 激活 #FFFFFF / 非激活 #F8F8F8 灰字）
      (vs-spec :lem/frame-multiplexer "FRAME-MULTIPLEXER-ACTIVE-FRAME-NAME-ATTRIBUTE"
               :foreground (if dark "#FFFFFF" "#3B3B3B")
               :background (if dark "#1F1F1F" "#FFFFFF") :bold t)
      (vs-spec :lem/frame-multiplexer "FRAME-MULTIPLEXER-FRAME-NAME-ATTRIBUTE"
               :foreground (if dark "#9D9D9D" "#868686")
               :background (if dark "#181818" "#F8F8F8"))
      (vs-spec :lem/frame-multiplexer "FRAME-MULTIPLEXER-BACKGROUND-ATTRIBUTE"
               :foreground (if dark "#CCCCCC" "#3B3B3B")
               :background (if dark "#181818" "#F8F8F8"))))))

(setf (gethash "vscode-dark-modern" lem-core::*color-themes*)
      (lem-core::make-color-theme :specs (vs-theme-specs :dark)
                                 :parent "lem-default"))
(setf (gethash "vscode-light-modern" lem-core::*color-themes*)
      (lem-core::make-color-theme :specs (vs-theme-specs :light)
                                 :parent "lem-default"))

;; 深浅切换：load-theme 持久化主题名；侧栏/问题面板经 set-chrome 回调重 skin
;; （vs-call 动态解析：对应模块未加载时只告警跳过）。
(define-command vscode-toggle-theme () ()
  (setf *vs-theme-mode* (if (eq *vs-theme-mode* :dark) :light :dark))
  (load-theme (if (eq *vs-theme-mode* :dark)
                  "vscode-dark-modern"
                  "vscode-light-modern"))
  (vs-call :lem-user "VS-EXPLORER-SET-CHROME" *vs-theme-mode*)
  (vs-call :lem-user "VS-PROBLEMS-SET-CHROME" *vs-theme-mode*)
  (vs-call :lem-user "VS-WELCOME-SET-CHROME" *vs-theme-mode*)
  (message "Color theme: ~A"
           (if (eq *vs-theme-mode* :dark)
               "VSCode Dark Modern"
               "VSCode Light Modern")))

;; 载入（load-theme 同时把主题名持久化到 ~/.config/lem/config.lisp；
;; VS_THEME=light 启动即浅色：沙箱截屏与偏好预置入口，优先级最高；
;; 未显式指定时跟随 darkman 系统配色（VSCodium window.autoDetectColorScheme
;; 的对应物），读不到/失败回落深色（历史默认）。40/46 load 期读
;; *vs-theme-mode* 而非写死 :dark，故与本块联动）。
;; darkman 探测 fork+exec ~30-50ms，放后台线程与 spec 构造并行；
;; 决策点 join 收结果。VS_THEME 显式指定时连线程都不起。
(defvar *vs-darkman-thread* nil)
(let ((startup (uiop:getenv "VS_THEME")))
  (cond ((and startup (string-equal startup "light"))
         (setf *vs-theme-mode* :light))
        ((null startup)
         (setf *vs-darkman-thread*
               (sb-thread:make-thread
                (lambda ()
                  (ignore-errors
                    (string= (uiop:run-program '("darkman" "get")
                                               :output '(:string :stripped t)
                                               :ignore-error-status t)
                             "light")))
                :name "vs-darkman-probe")))))

(when (and *vs-darkman-thread*
           (ignore-errors (sb-thread:join-thread *vs-darkman-thread*
                                                 :timeout 2)))
  (setf *vs-theme-mode* :light))

(load-theme (if (eq *vs-theme-mode* :dark)
                "vscode-dark-modern"
                "vscode-light-modern"))
(vs-call :lem-user "VS-EXPLORER-SET-CHROME" *vs-theme-mode*)
(vs-call :lem-user "VS-PROBLEMS-SET-CHROME" *vs-theme-mode*)

;; tabbar（webview 顶栏文件 tab 条）HTML token 换肤：上游 generate-html 的
;; CSS token 硬编码暗色（--tab-bg #181818 等），仅激活 tab 底色取 editor-bg，
;; 浅色主题下整条深底白字与编辑区脱节。wrap 输出：dark 直通原函数；light 把
;; :root 暗色 token 与 close hover 高光替换为浅色对（色值对齐 VSCode Light
;; Modern：tab 栏 #F8F8F8 / 激活 #FFFFFF / 文字 #6F6F6F→#3B3B3B / 边 #E2E2E2 /
;; 强调 #0098FF）。上游 *after-load-theme-hook* 已挂 update-on-theme-change
;; （重生成 HTML + 重绘），toggle-theme 时本 wrap 自动换色，无需额外钩子。
;; wrap 幂等同款：orig 挂符号 plist，重载不叠包。
(defun vs-html-replace-all (old new s)
  ;; 纯 string 无依赖：逐处字面替换（token 均唯一，长度可变但无递归回带）。
  (let ((out s) (pos 0))
    (loop
      (let ((i (search old out :start2 pos)))
        (unless i (return out))
        (setf out (concatenate 'string (subseq out 0 i) new (subseq out (+ i (length old))))
              pos (+ i (length new)))))))

(let ((gen (vs$ :lem/tabbar "GENERATE-HTML")))
  (when (and gen (fboundp gen))
    (let ((orig (or (get gen 'vs-tabbar-html-orig) (symbol-function gen))))
      (setf (symbol-function gen)
            (lambda ()
              (if (eq *vs-theme-mode* :dark)
                  (funcall orig)
                  (let ((html (funcall orig)))
                    (dolist (pair
                              '(("--tab-bg: #181818" . "--tab-bg: #F8F8F8")
                                ("--tab-bg-hover: #252525" . "--tab-bg-hover: #ECECEC")
                                ("--tab-fg: #8b8b8b" . "--tab-fg: #6F6F6F")
                                ("--tab-fg-active: #e0e0e0" . "--tab-fg-active: #3B3B3B")
                                ("--tab-border: #2a2a2a" . "--tab-border: #E2E2E2")
                                ("--tab-accent: #4cc2ff" . "--tab-accent: #0098FF")
                                ("background: rgba(255,255,255,.1)"
                                 . "background: rgba(0,0,0,.08)")))
                      (setf html (vs-html-replace-all (car pair) (cdr pair) html)))
                    html))))
      (setf (get gen 'vs-tabbar-html-orig) orig))))
