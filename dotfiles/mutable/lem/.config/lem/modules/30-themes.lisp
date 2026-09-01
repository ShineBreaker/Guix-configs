;;; modules/30-themes.lisp — vscode-dark-modern 主题（运行时构造）
;;;
;;; 依赖：utils（vs-spec）；无下游依赖（explorer 侧栏配色不经主题，
;;; 自带 attribute 定义，见 40-explorer）。
;;;
;;; 运行时构造 specs 而非编译期展开：杜绝包前缀符号缺失炸进程的风险。
;;; 色值权威源 microsoft/vscode dark_modern.json：
;;;   chrome 三元组：#181818（工作台镶边）/ #1F1F1F（编辑器/激活 tab）/ #2B2B2B（分隔线）
;;;   强调 #0078D4；文字三级 #FFFFFF / #CCCCCC / #9D9D9D

(in-package :lem-user)

(let ((specs
       (remove
        nil
        (list
         ;; 工作台
         (list :display-background-mode :dark)
         (list :foreground "#CCCCCC")           ; editor.foreground
         (list :background "#1F1F1F")           ; editor.background
         (list :inactive-window-background "#181818")
         ;; base16 抽象色（isearch 等内部 attribute 按 :baseXX 引用）
         (list :base00 "#1F1F1F") (list :base01 "#252526") (list :base02 "#2B2B2B")
         (list :base03 "#6E7681") (list :base04 "#868686") (list :base05 "#CCCCCC")
         (list :base06 "#D7D7D7") (list :base07 "#FFFFFF")
         (list :base08 "#F14C4C") (list :base09 "#CE9178") (list :base0A "#B5CEA8")
         (list :base0B "#23D18B") (list :base0C "#4EC9B0") (list :base0D "#569CD6")
         (list :base0E "#C586C0") (list :base0F "#D7BA7D")
         ;; 光标 / 选区（editorCursor #AEAFAD、selection #264F78）
         (vs-spec :lem "CURSOR" :background "#AEAFAD")
         (vs-spec :lem "REGION" :foreground nil :background "#264F78")
         ;; 行号（#6E7681 / 当前行 #CCCCCC；背景必须显式，否则用 :base01）
         (vs-spec :lem/line-numbers "LINE-NUMBERS-ATTRIBUTE"
                  :foreground "#6E7681" :background "#1F1F1F")
         (vs-spec :lem/line-numbers "ACTIVE-LINE-NUMBER-ATTRIBUTE"
                  :foreground "#CCCCCC" :background "#1F1F1F")
         ;; isearch（findMatch #9E6A03 / findMatchHighlight 近似；
         ;; 上游 nightly 已删除 UNMATCH-ISEARCH-ATTRIBUTE）
         (vs-spec :lem/isearch "ISEARCH-HIGHLIGHT-ACTIVE-ATTRIBUTE"
                  :foreground "#1F1F1F" :background "#9E6A03")
         (vs-spec :lem/isearch "ISEARCH-HIGHLIGHT-ATTRIBUTE"
                  :foreground "#CCCCCC" :background "#613214")
         ;; 语法高亮（Dark+ token 色板）
         (vs-spec :lem "SYNTAX-COMMENT-ATTRIBUTE" :foreground "#6A9955")
         (vs-spec :lem "SYNTAX-KEYWORD-ATTRIBUTE" :foreground "#569CD6")
         (vs-spec :lem "SYNTAX-STRING-ATTRIBUTE" :foreground "#CE9178")
         (vs-spec :lem "SYNTAX-CONSTANT-ATTRIBUTE" :foreground "#4FC1FF")
         (vs-spec :lem "SYNTAX-FUNCTION-NAME-ATTRIBUTE" :foreground "#DCDCAA")
         (vs-spec :lem "SYNTAX-VARIABLE-ATTRIBUTE" :foreground "#9CDCFE")
         (vs-spec :lem "SYNTAX-TYPE-ATTRIBUTE" :foreground "#4EC9B0")
         (vs-spec :lem "SYNTAX-BUILTIN-ATTRIBUTE" :foreground "#569CD6")
         (vs-spec :lem "SYNTAX-WARNING-ATTRIBUTE" :foreground "#CCA700")
         ;; 诊断（error #F14C4C / warning #CCA700 / info #59A4F9）
         (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-ERROR-ATTRIBUTE" :foreground "#F14C4C")
         (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-WARNING-ATTRIBUTE" :foreground "#CCA700")
         (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-INFORMATION-ATTRIBUTE" :foreground "#59A4F9")
         (vs-spec :lem-lsp-mode/lsp-mode "DIAGNOSTIC-HINT-ATTRIBUTE" :foreground "#9D9D9D")
         ;; modeline → VSCode Status Bar（#181818 全宽条 + #CCCCCC 文字）
         (vs-spec :lem "MODELINE" :background "#181818" :foreground "#CCCCCC")
         (vs-spec :lem "MODELINE-INACTIVE" :background "#181818" :foreground "#868686")
         (vs-spec :lem "MODELINE-NAME-ATTRIBUTE" :background "#181818" :foreground "#CCCCCC")
         (vs-spec :lem "MODELINE-MAJOR-MODE-ATTRIBUTE" :background "#181818" :foreground "#CCCCCC")
         (vs-spec :lem "MODELINE-MINOR-MODES-ATTRIBUTE" :background "#181818" :foreground "#868686")
         (vs-spec :lem "MODELINE-POSITION-ATTRIBUTE" :background "#181818" :foreground "#CCCCCC")
         (vs-spec :lem "MODELINE-POSLINE-ATTRIBUTE" :background "#181818" :foreground "#CCCCCC")
         (vs-spec :lem "INACTIVE-MODELINE-NAME-ATTRIBUTE" :background "#181818" :foreground "#868686")
         (vs-spec :lem "INACTIVE-MODELINE-MAJOR-MODE-ATTRIBUTE" :background "#181818" :foreground "#868686")
         (vs-spec :lem "INACTIVE-MODELINE-MINOR-MODES-ATTRIBUTE" :background "#181818" :foreground "#6E7681")
         (vs-spec :lem "INACTIVE-MODELINE-POSITION-ATTRIBUTE" :background "#181818" :foreground "#868686")
         (vs-spec :lem "INACTIVE-MODELINE-POSLINE-ATTRIBUTE" :background "#181818" :foreground "#868686")
         ;; frame-multiplexer → VSCode Tab 栏（默认开启、带编号切换，是 VSCode
         ;; Tab 的正确对应物；激活 #1F1F1F 白字粗体 / 非激活 #181818 灰 / 栏底 #181818）
         (vs-spec :lem/frame-multiplexer "FRAME-MULTIPLEXER-ACTIVE-FRAME-NAME-ATTRIBUTE"
                  :foreground "#FFFFFF" :background "#1F1F1F" :bold t)
         (vs-spec :lem/frame-multiplexer "FRAME-MULTIPLEXER-FRAME-NAME-ATTRIBUTE"
                  :foreground "#9D9D9D" :background "#181818")
         (vs-spec :lem/frame-multiplexer "FRAME-MULTIPLEXER-BACKGROUND-ATTRIBUTE"
                  :foreground "#CCCCCC" :background "#181818")))))
  (setf (gethash "vscode-dark-modern" lem-core::*color-themes*)
        (lem-core::make-color-theme :specs specs :parent "lem-default")))

;; 载入（load-theme 同时把主题名持久化到 ~/.config/lem/config.lisp）
(load-theme "vscode-dark-modern")
