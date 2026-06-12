;;; early-init-snippets/optimal.el --- 早期优化完整代码 -*- lexical-binding: t -*-
;;; Commentary:
;; 这是从 doomemacs/lisp/early-init.el 和 doom-start.el 提炼的"教科书级"
;; 早期优化代码。逐段注释解释每条优化的目的、副作用、配套措施。
;;
;; **警告**: 不要盲目复制。GC 推迟、file-name-handler-alist 清空等都有副作用,
;; 必须配套 gcmh-mode 或等价的"idle 时复位 GC 阈值"机制,否则会卡顿。
;;
;; 配套: 参考 references/startup-and-packages.md §2-§3

;;; Code:

;;
;; 1. GC 推迟(最大的单项优化)
;;

;; PERF: GC 在启动期贡献了显著的开销(扫描 1MB 堆需要 50ms+)。
;;   把阈值推到最大,跳过启动期所有 GC。
(setq gc-cons-percentage 1.0
      gc-cons-threshold most-positive-fixnum)

;; MUST: 配套 gcmh-mode,在 idle 时把 GC 阈值复位到合理值(默认 16MB),
;;   并在 Emacs 不可见时(daemon 空闲)主动 GC 释放内存。
;; 安装: doom 自带 gcmh;手写用 https://github.com/emacsmirror/gcmh
(use-package gcmh
  :config
  (gcmh-mode 1)
  ;; gcmh-high-cons-threshold 调高(配合 LSP 时)
  (setq gcmh-high-cons-threshold (* 2 16777216)))


;;
;; 2. 关闭 load-prefer-newer(字节编译优先)
;;

;; PERF: Emacs 默认会在 .el 跟 .elc 同时存在时检查 .el 的 mtime,看是否需要重新
;;   编译。这对启动期的几百个文件来说累计开销很大。关掉它,信任 .elc。
;;   当 .el 改变时,用 `M-x byte-compile-file` 重新编译。
(setq load-prefer-newer nil)


;;
;; 3. 关闭 package.el 早初始化(配合 use-package 手动控制)
;;

;; Emacs 27+ 在 init.el 之前会自动 package-initialize,这往往不是我们要的。
;; (我们用 use-package 配合 straight/elpaca 自行管理包。)
(setq package-enable-at-startup nil)


;;
;; 4. 临时清空 file-name-handler-alist
;;

;; PERF: Emacs 大量调用 expand-file-name,而它会查询 file-name-handler-alist
;;   (tramp、远程文件、压缩文件等的 handler)。启动期这些 handler 都没用,
;;   清空可显著加速。
;;   注意: 必须用 `let` 局部清空,启动后 Emacs 会重新填充。
(let ((file-name-handler-alist nil))
  ;; 在这里做需要快速 expand-file-name 的初始化工作(可选)
  )


;;
;; 5. 关闭不必要的默认行为
;;

;; PERF: 关闭大小写折叠扫描 auto-mode-alist(可省 50-100ms)
(setq auto-mode-case-fold nil)

;; PERF: 关闭双向文本扫描(单 LTR 文本用,启动期加速)
(setq-default bidi-display-reordering 'left-to-right
              bidi-paragraph-direction 'left-to-right)

;; PERF: 关闭 BPA(成对括号算法),减少重绘
(setq bidi-inhibit-bpa t)  ; Emacs 27+

;; 减少非焦点窗口的渲染
(setq-default cursor-in-non-selected-windows nil)
(setq highlight-nonselected-windows nil)

;; 快速但不精确的滚动(未语法高亮区域)
(setq fast-but-imprecise-scrolling t)


;;
;; 6. GUI 元素预先关闭(避免闪烁)
;;

(unless (daemonp)
  (push '(menu-bar-lines . 0) default-frame-alist)
  (push '(tool-bar-lines . 0) default-frame-alist)
  (push '(vertical-scroll-bars . nil) default-frame-alist)
  (push '(horizontal-scroll-bars . nil) default-frame-alist))

;; tool-bar mode 在 init 时显式关
(when (fboundp 'tool-bar-mode)
  (tool-bar-mode -1))

;; scroll-bar mode
(when (fboundp 'scroll-bar-mode)
  (scroll-bar-mode -1))


;;
;; 7. 设定 user-emacs-directory(化学多 profile 支持)
;;

;; Doom 的 profile 范式: --profile NAME 时切换到 ~/.emacs.d-profiles/NAME/
;; 自建可以简化: 不要这个功能,直接 user-emacs-directory


;;
;; 8. 在末尾重置非可持续的优化
;;

;; 把 file-name-handler-alist 恢复(必须!否则 tramp 等失效)
(setq file-name-handler-alist
      (append (let ((default-directory (expand-file-name "~/")))
                (list (cons "\\`/ssh:" 'tramp-file-name-handler)
                      (cons "\\`/sudo:" 'tramp-file-name-handler)))
              file-name-handler-alist))

;; 也可以不重置,Emacs 在 after-init 阶段会自动处理

;;; early-init-snippets/optimal.el ends here
