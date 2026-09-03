;;; modules/80-modes-base.lisp — mode 接线辅助（LSP / paredit）
;;;
;;; 依赖：utils（vs$ / vs-warn）；被 modes/ 各语言文件依赖，须最先加载。
;;;
;;; LSP 接线 = 上游 define-language-spec 宏的运行时等价展开：该宏需要
;;; 编译期字面 mode 符号（且展开期即调用 mode-hook-variable，mode 未定义
;;; 直接炸），动态解析路线只能手工做宏做的三件事：注册 spec、挂
;;; enable-lsp-mode 到 mode hook。任一依赖缺失整条跳过并告警。

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
