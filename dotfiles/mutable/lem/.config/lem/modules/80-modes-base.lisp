;;; modules/80-modes-base.lisp — mode 接线辅助（LSP / paredit / tree-sitter）
;;;
;;; 依赖：utils（vs$ / vs-warn）；被 modes/ 各语言文件依赖，须最先加载。
;;; tree-sitter 段运行时动态解析 :lem-tree-sitter / :tree-sitter 包符号，
;;; 不静态引用（包不存在只降级，不炸编译期）。
;;;
;;; LSP 接线 = 上游 define-language-spec 宏的运行时等价展开：该宏需要
;;; 编译期字面 mode 符号（且展开期即调用 mode-hook-variable，mode 未定义
;;; 直接炸），动态解析路线只能手工做宏做的三件事：注册 spec、挂
;;; enable-lsp-mode 到 mode hook。任一依赖缺失整条跳过并告警。
;;;
;;; tree-sitter 接线（2026-09-04 调研，上游 lem-next-2.3.0-0.68e85e0）：
;;; - 上游 json/nix/markdown/toml/yaml 各 mode 的 body 已自带
;;;   enable-tree-sitter-for-mode(syntax-table language query-path) 调用
;;;   （进 mode 时执行），配置侧无需挂 hook；enable-tree-sitter-for-all-modes
;;;   只有 export 没有定义（调用即 UNDEFINED-FUNCTION），不可用。
;;; - 本机真正的断点是语言 grammar .so 不在 lem 进程库搜索路径（RUNPATH
;;;   仅 glibc/gcc/zstd；LD_LIBRARY_PATH 与 ld.so.cache 均无 grammar），
;;;   上游 fallback 的 load-language-from-system 必失败 → enable 静默
;;;   回落 tmlanguage。修法：load 期 glob guix store 的
;;;   /gnu/store/*-tree-sitter-<lang>-*/lib/libtree-sitter-<lang>.so，
;;;   经 ts:load-language 绝对路径加载并注册进语言注册表；此后上游 mode
;;;   body 的 enable 里 ts:get-language 直接命中，链路打通。store hash
;;;   随版本变，故运行时探测不硬编码。query 文件路径上游走
;;;   asdf:system-relative-pathname，git 构建的源码树已由
;;;   source-registry 50-lem-next.conf :tree 注册，可用（AppImage 无源码树
;;;   的坑不适用当前构建；即便失效 enable 内 probe-file 也只会安全回落）。
;;; - 启用清单 = 预注册清单 = "json" "nix"（未预注册即不启用，上游安全
;;;   回落 tmlanguage，与现状一致）：
;;;   * lisp/scheme：store 无 grammar 库；lisp-mode 高亮由 paredit + 自有
;;;     syntax 承担，不适用 tree-sitter。
;;;   * python/rust/go/c/css/html：store 有 grammar 但上游无 highlights.scm
;;;     （tree-sitter 高亮必须配 query 文件），无 query 不启用。
;;;   * markdown/toml/yaml/wat：上游 mode 自带接线但 store 缺 toml grammar；
;;;     markdown query 依赖 markdown_inline injection，query 编译失败时
;;;     上游 %syntax-scan-region 先清 attribute 再无高亮可套（白板劣化），
;;;     且均不在本配置实际语言清单内，不预注册。
;;; - 高亮配色兼容：capture 名经 make-default-capture-attribute-map 映射到
;;;   lem:syntax-string/comment/keyword/constant/function-name/variable/
;;;   type/builtin-attribute——与 30-themes 的 SYNTAX-* 配色同一套 attribute
;;;   体系，现有 Dark+ token 色直接生效，主题零改动。
;;; - 性能/稳定性：增量解析（pending-edits 记录 after-change、
;;;   buffer-modified-tick 缓存语法树，改动后首扫才重 parse；上游自注
;;;   old-len 字节换算是近似值，仅影响增量精度不影响正确性）。

(in-package :lem-user)

(defun vs-mode-hook (mode)
  "mode 的 hook 变量符号（lem-core mode-hook-variable 动态解析）。"
  (let ((fn (or (vs$ :lem-core "MODE-HOOK-VARIABLE")
                (vs$ :lem "MODE-HOOK-VARIABLE"))))
    (and fn mode (funcall fn mode))))

(defun vs-hook-add (hook-symbol fn-symbol)
  "运行时向 hook 变量登记回调。add-hook 是 place 宏（展开期取符号位置），
运行时拿到 hook 符号值必须 eval 构造调用（与 60-editor-config 的
defmethod :around 挂接同一手法）。"
  (eval `(add-hook ,hook-symbol ',fn-symbol)))

(defun vs-lsp-wire (mode language-id root-patterns command)
  "为 major mode 接线 stdio LSP server：注册 spec + hook 挂 enable-lsp-mode。
mode 符号由调用方 vs$ 解析（nil 则整条跳过）。"
  (let ((reg (vs$ :lem-lsp-mode/spec "REGISTER-LANGUAGE-SPEC"))
        (spec-class (vs$ :lem-lsp-mode/spec "SPEC"))
        (enable (vs$ :lem-lsp-mode "ENABLE-LSP-MODE")))
    (let ((hook (and mode reg spec-class enable (vs-mode-hook mode))))
      (if hook
          (progn
            (funcall reg mode
                     (make-instance spec-class
                                    :language-id language-id
                                    :root-uri-patterns root-patterns
                                    :command command
                                    :connection-mode :stdio
                                    :mode mode))
            (vs-hook-add hook enable)
            (format *error-output* "; [lem] LSP: ~A <- ~A~%"
                    language-id (car command)))
          (vs-warn (list :lsp-deps mode))))))

(defun vs-paredit (mode)
  "lisps 系 mode 挂 paredit。hook 回调零参调用 minor-mode 命令 → toggle →
新 buffer 上等效于启用。"
  (let ((paredit (vs$ :lem-paredit-mode "PAREDIT-MODE"))
        (hook (vs-mode-hook mode)))
    (if (and paredit hook)
        (vs-hook-add hook paredit)
        (vs-warn (list :paredit mode)))))

;; --- tree-sitter：guix store grammar 预注册（取舍与断点分析见头注释）---

(defun vs-ts-store-grammar (lang)
  "glob guix store 里的语言 grammar 共享库，取字典序最大（版本号新），
排除 -js 变体目录；找不到返回 nil。guix 打包 grammar 位于
lib/tree-sitter/ 子目录（tree-sitter 官方搜索路径惯例），非 lib/ 直下。"
  (ignore-errors
    (let ((hits (directory
                 (format nil "/gnu/store/*-tree-sitter-~A-*/lib/tree-sitter/libtree-sitter-~A.so"
                         lang lang))))
      (car (sort (remove-if (lambda (p) (search "-js/" (namestring p))) hits)
                 #'string> :key #'namestring)))))

(defun vs-ts-register (lang)
  "把一个语言的 grammar 以绝对路径加载进 tree-sitter 语言注册表（幂等：
GET-LANGUAGE 已命中则跳过）。加载失败/依赖缺失告警返回 nil，不炸。"
  (let ((have (vs$ :tree-sitter "GET-LANGUAGE"))
        (load (vs$ :tree-sitter "LOAD-LANGUAGE")))
    (cond
      ((and have load (funcall have lang)) lang)
      ((and have load)
       (let ((path (vs-ts-store-grammar lang)))
         (when path
           (handler-case (progn (funcall load lang path) lang)
             (error () (vs-warn (list :ts-grammar lang path)))))))
      (t (vs-warn (list :tree-sitter "LOAD-LANGUAGE" "GET-LANGUAGE"))))))

(defvar *vs-ts-preloaded* nil
  "已预注册的 grammar 语言表（defvar：重载不丢，glob 只跑一次）。
load 期不再 glob /gnu/store（冷启动 store 缓存冷时两次 directory 扫
描昂贵）；首次进入对应 mode 时一次性注册——上游 mode body 进 mode
时才查注册表，时序刚好（见头注释）。")

(defun vs-ts-preload-json (&rest args)
  (declare (ignore args))
  (unless (member "json" *vs-ts-preloaded* :test #'string=)
    (push "json" *vs-ts-preloaded*)
    (vs-ts-register "json")))

(defun vs-ts-preload-nix (&rest args)
  (declare (ignore args))
  (unless (member "nix" *vs-ts-preloaded* :test #'string=)
    (push "nix" *vs-ts-preloaded*)
    (vs-ts-register "nix")))

;; 懒挂接：mode 未定义时 vs-mode-hook 回 nil 即跳过（镜像 mode 内建，
;; load 期即有；json/nix 任一缺失只告警，不影响另一路）。
(let ((avail (vs$ :lem-tree-sitter "TREE-SITTER-AVAILABLE-P")))
  (if (and avail (ignore-errors (funcall avail)))
      (let ((jm (vs$ :lem-json-mode "JSON-MODE"))
            (nm (vs$ :lem-nix-mode "NIX-MODE")))
        (let ((jh (and jm (vs-mode-hook jm)))
              (nh (and nm (vs-mode-hook nm))))
          ;; hook 传符号（运行时 funcall）——裸符号会按变量求值，
          ;; unbound 即 EVAL-ERR，钩子静默丢失（90-startup 同款 quote 风格）
          (when jh (vs-hook-add jh 'vs-ts-preload-json))
          (when nh (vs-hook-add nh 'vs-ts-preload-nix))
          (unless (or jh nh)
            (vs-warn (list :ts-modes "JSON-MODE" "NIX-MODE")))))
      (vs-warn (list :lem-tree-sitter "TREE-SITTER-AVAILABLE-P"))))
