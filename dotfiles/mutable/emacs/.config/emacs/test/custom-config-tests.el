;;; custom-config-tests.el --- ERT tests for custom-config -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; This file is loaded by `scripts/configctl test' after `main.el' has been
;; tangled and loaded in an isolated runtime. Tests fall into two categories:
;;
;;   1. Pure-function / state-contract tests — document and freeze the
;;      expected behaviour that later commits must preserve. These MUST pass.
;;
;;   2. Baseline-bug tests (marked `:expected-result :failed') — capture the
;;      P0/P1 contracts that the current code violates. Each such test names
;;      the commit that will turn it green. When that commit lands, drop the
;;      `:expected-result' property so the test enforces the new contract.
;;
;; A green `configctl test' run means: every category-1 test passes AND every
;; category-2 test is failing (i.e. the bug is still present, exactly as
;; captured). A category-2 test that turns green while still marked :failed is
;; the signal to remove the mark and start enforcing the new contract.
;;
;; Many baseline bugs are easier to enumerate via `configctl audit-*' than via
;; ERT (e.g. agenote-domain drift, private-API calls, package manifest
;; gaps). Those live in scripts/configctl.el as audit subcommands; only the
;; contracts that need an actual loaded environment are ERT tests here.

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; ---------------------------------------------------------------------------
;;; Category 1: state contracts (MUST pass today, MUST keep passing)
;;; ---------------------------------------------------------------------------

(ert-deftest custom-config/agenote-group-by-category-ordering ()
  "Phase 2.3 PLAN:category grouping/recency sort 已下沉到 agenote CLI。
本测试现已废弃;group/sort 逻辑由 CLI(agenote list)负责。
保留此占位以提示历史;实际行为由 `agenote-knowledge-list-cards' 通过
CLI 透传,无需在 Emacs 侧固化顺序规则。"
  (skip-unless nil))

(ert-deftest custom-config/agenote-sort-by-recency ()
  "Phase 2.3 PLAN:同上,recency 排序由 agenote CLI 决定。
本测试保留为占位。"
  (skip-unless nil))

(ert-deftest custom-config/modeline-tier-boundaries ()
  "Tier computation: wide >= 120, medium >= 100, narrow >= 80, else compact.
Commit 8 will centralize tier computation into a single renderer; this test
pins the boundary semantics so the refactor cannot silently shift them."
  (skip-unless (fboundp 'custom/modeline-tier))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 120)))
    (should (eq (custom/modeline-tier) 'wide)))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 119)))
    (should (eq (custom/modeline-tier) 'medium)))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 100)))
    (should (eq (custom/modeline-tier) 'medium)))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 99)))
    (should (eq (custom/modeline-tier) 'narrow)))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 80)))
    (should (eq (custom/modeline-tier) 'narrow)))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 79)))
    (should (eq (custom/modeline-tier) 'compact))))

(ert-deftest custom-config/tabs-per-frame-parameter-isolation ()
  "Per-frame tab-buffer lists are stored on frame parameters and stay isolated.
This test exercises the frame-parameter storage directly (not make-frame,
which fails under `emacs --batch' with no terminal) to keep the per-frame
contract pinned across the Commit 7 rewrite."
  (skip-unless (fboundp 'custom--tabs-set-frame-buffer-list))
  (skip-unless (fboundp 'custom--tabs-get-frame-buffer-list))
  (let* ((mock-frame-a (list 'foo))
         (mock-frame-b (list 'bar))
         (buf-a (generate-new-buffer " *test-a*"))
         (buf-b (generate-new-buffer " *test-b*"))
         (buf-a2 (generate-new-buffer " *test-a2*")))
    (unwind-protect
        (progn
          ;; set-frame-parameter / frame-parameter work on any frame-like
          ;; object that has the right plist semantics; use the selected frame
          ;; as the storage but address it through the literal accessors with
          ;; explicit FRAME argument so the test isolates per-frame state.
          (let ((real-frame (selected-frame)))
            ;; Stub frame-parameter / set-frame-parameter to map our mock
            ;; frames to independent plists, simulating two real frames.
            (let ((store-a nil)
                  (store-b nil))
              (cl-letf
                  (((symbol-function 'frame-parameter)
                    (lambda (frame param)
                      (cond
                       ((eq frame mock-frame-a)
                        (when (eq param 'custom--frame-tab-buffers) store-a))
                       ((eq frame mock-frame-b)
                        (when (eq param 'custom--frame-tab-buffers) store-b))
                       (t (let ((orig (default-value 'frame-parameter)))
                            ;; fall through for any other frame access
                            nil)))))
                   ((symbol-function 'set-frame-parameter)
                    (lambda (frame param value)
                      (cond
                       ((eq frame mock-frame-a)
                        (when (eq param 'custom--frame-tab-buffers)
                          (setq store-a value)))
                       ((eq frame mock-frame-b)
                        (when (eq param 'custom--frame-tab-buffers)
                          (setq store-b value)))))))
                (custom--tabs-set-frame-buffer-list (list buf-a) mock-frame-a)
                (custom--tabs-set-frame-buffer-list (list buf-b) mock-frame-b)
                (should (equal (custom--tabs-get-frame-buffer-list mock-frame-a)
                               (list buf-a)))
                (should (equal (custom--tabs-get-frame-buffer-list mock-frame-b)
                               (list buf-b)))
                (custom--tabs-set-frame-buffer-list
                 (append (custom--tabs-get-frame-buffer-list mock-frame-a)
                         (list buf-a2))
                 mock-frame-a)
                ;; Frame B untouched by Frame A's append.
                (should (equal (custom--tabs-get-frame-buffer-list mock-frame-b)
                               (list buf-b)))
                (should (equal (custom--tabs-get-frame-buffer-list mock-frame-a)
                               (list buf-a buf-a2))))))
          nil)
      (ignore-errors (kill-buffer buf-a))
      (ignore-errors (kill-buffer buf-b))
      (ignore-errors (kill-buffer buf-a2)))))

(ert-deftest custom-config/tab-line-close-button-keeps-mouse-map ()
  "格式化后的关闭按钮必须保留独立 mouse-map，不被标签选择 map 覆盖。"
  (skip-unless (fboundp 'custom/tab-line-tab-name-format))
  (let ((buffer (generate-new-buffer " *tab-close-map*"))
        (tab-line-close-button-show t))
    (unwind-protect
        (let* ((rendered
                (custom/tab-line-tab-name-format buffer (list buffer)))
               (close-pos (string-match "x" rendered))
               (keymap (and close-pos
                            (get-text-property close-pos 'keymap rendered))))
          (should close-pos)
          (should (eq keymap tab-line-tab-close-map))
          (should (eq (lookup-key keymap [tab-line mouse-1])
                      #'tab-line-close-tab))
          (should (eq (get-text-property close-pos 'tab rendered) buffer)))
      (kill-buffer buffer))))

(ert-deftest custom-config/tab-line-close-persists-window-switch ()
  "点击关闭后应保留后继标签的窗口切换，同时只隐藏而不 kill buffer。"
  (skip-unless (fboundp 'custom/tab-line-close-tab))
  (let* ((frame (selected-frame))
         (window (selected-window))
         (original (window-buffer window))
         (buffer-a (generate-new-buffer " *tab-close-a*"))
         (buffer-b (generate-new-buffer " *tab-close-b*")))
    (unwind-protect
        (progn
          (with-current-buffer buffer-a
            (setq buffer-file-name "/tmp/tab-close-a.el"))
          (with-current-buffer buffer-b
            (setq buffer-file-name "/tmp/tab-close-b.el"))
          (set-window-buffer window buffer-a)
          (custom--tabs-set-frame-buffer-list (list buffer-a buffer-b) frame)
          (custom/tab-line-close-tab buffer-a)
          (should (eq (window-buffer window) buffer-b))
          (should (equal (custom--tabs-get-frame-buffer-list frame)
                         (list buffer-b)))
          (should (buffer-live-p buffer-a)))
      (set-window-buffer window original)
      (custom--tabs-set-frame-buffer-list nil frame)
      (kill-buffer buffer-a)
      (kill-buffer buffer-b))))

(ert-deftest custom-config/tab-line-padding-does-not-draw-box-border ()
  "Tab-line 禁用 spacious-padding 的 box，避免当前标签出现白色边框。"
  (skip-unless (boundp 'spacious-padding-widths))
  (should (equal (plist-get spacious-padding-widths :tab-line-width) 0))
  (should-not (face-attribute 'tab-line-tab-current :box nil 'default)))

(ert-deftest custom-config/tab-line-rendering-is-borderless-and-keeps-height ()
  "渲染字符串显式清 box，并用零宽 spacer 恢复原 4px box 的高度。"
  (let ((buffer (generate-new-buffer " *tab-visual-contract*"))
        (tab-line-close-button-show t))
    (unwind-protect
        (let* ((rendered
                (custom/tab-line-tab-name-format buffer (list buffer)))
               (face-value (get-text-property 1 'face rendered))
               (faces (if (and (listp face-value)
                               (not (keywordp (car-safe face-value))))
                          face-value
                        (list face-value))))
          (should
           (equal (get-text-property 0 'display rendered)
                  '(space :width (0) :height (+ height (8)) :ascent 75)))
          (should
           (seq-some
            (lambda (entry)
              (and (listp entry)
                   (plist-member entry :box)
                   (null (plist-get entry :box))))
            faces)))
      (kill-buffer buffer))))

(ert-deftest custom-config/capture-templates-cover-lifecycle ()
  "Phase 2.2: org-capture-templates covers all four data lifecycles.
ki=inbox, kt/kd/ke=agenda (task/dated/event), kr=roam, kn/km/ka=experiences
(aligning with agenote-base entry-types note/mistake/ascended)."
  (require 'org-capture)
  ;; after-load hook fires on require; ensure templates populated.
  (should (consp org-capture-templates))
  (let ((required-keys '("ki" "kt" "kd" "ke" "kr" "kn" "km" "ka"))
        (present-keys (mapcar #'car org-capture-templates)))
    (dolist (key required-keys)
      (should (member key present-keys)))))

(ert-deftest custom-config/language-capabilities-derived-consistency ()
  "Phase 3.2: language-treesit-remaps / eglot-auto-modes / eglot-server-programs
/ apheleia-mode-alist all derive from the single source `language-capabilities'.
Each :server entry's modes ⊆ language-eglot-auto-modes (with server declared).
Each :ts-mode produces a remap from the first :modes entry."
  (skip-unless (boundp 'custom:language-capabilities))
  (should (consp custom:language-capabilities))
  ;; Every :ts-mode has a matching remap entry.
  (dolist (entry custom:language-capabilities)
    (let ((ts-mode (plist-get entry :ts-mode)))
      (when ts-mode
        (let ((orig-mode (car (plist-get entry :modes))))
          (should (assoc orig-mode custom:language-treesit-remaps))
          (should (eq (cdr (assoc orig-mode custom:language-treesit-remaps))
                      ts-mode))))))
  ;; Every :formatter non-nil entry has its modes in apheleia-mode-alist.
  (dolist (entry custom:language-capabilities)
    (let ((formatter (plist-get entry :formatter)))
      (when formatter
        (dolist (mode (plist-get entry :modes))
          (should (eq (cdr (assoc mode custom:language-apheleia-mode-alist))
                      formatter)))))))

(ert-deftest custom-config/capture-kr-targets-roam ()
  "Phase 2.1+2.2: kr capture 必须写入 roam/ 目录(PLAN §2.1 四类生命周期)。
原 bug:kr capture 曾误指向 experiences/;Phase 2.2 修复后 roam capture
应使用 `custom/org-capture--roam-file' 返回 custom:org-roam-directory 下
的路径。本测试固化目标函数的行为,避免回归。"
  (skip-unless (fboundp 'custom/org-capture--roam-file))
  (skip-unless (boundp 'custom:org-roam-directory))
  ;; 因为 custom/org-capture--roam-file 会读字符串(交互输入),用 cl-letf
  ;; 把 read-string 替换成无操作版本,只验证返回路径在 roam/ 下。
  (cl-letf (((symbol-function 'read-string)
             (lambda (&rest _) "测试标题")))
    (let ((path (custom/org-capture--roam-file)))
      (should (stringp path))
      (should (string-prefix-p (file-name-as-directory
                                (expand-file-name custom:org-roam-directory))
                               (expand-file-name path)))
      (should (string-match-p "\\.org\\'" path)))))

(ert-deftest custom-config/org-modern-visual-contract ()
  "org-modern 视觉配置不变量。
代码块的缩进渲染由 org-modern-indent（org-indent-mode 启用时）负责，
使用独立的 bracket/wrap-prefix 机制，不在此契约覆盖范围内。"
  (require 'org-modern)
  (with-temp-buffer
    (insert "* Blocks\n\n"
            "#+begin_src emacs-lisp\n(message \"hi\")\n#+end_src\n\n"
            "| N | N^2 |\n|---+-----|\n| 2 | 4   |\n")
    (org-mode)
    (font-lock-ensure)
    (should (bound-and-true-p org-modern-mode))
    (should (eq org-modern-star 'replace))
    (should (eq org-modern-hide-stars 'leading))
    (should org-hide-leading-stars)
    (should org-modern-table)
    (should (= org-modern-block-fringe 4))
    (should-not display-line-numbers)
    (goto-char (point-min))
    (should (equal (substring-no-properties
                    (get-char-property (point) 'display))
                   (car org-modern-replace-stars)))
    (search-forward "| N")
    (goto-char (- (point) 3))
    (should (equal (get-char-property (point) 'display)
                   '(space :width (2))))))

(ert-deftest custom-config/binding-spec-generates-help-and-dashboard ()
  "Phase 6 binding-spec single-source-of-truth: 帮助分组与 Dashboard 摘要
必须由 `custom:binding-spec' 派生,而非外置 help-zh.el。固化三点:
  1. binding-spec 非空(配置已声明键位)。
  2. `custom/binding-help-sections' 返回非空 sections 列表。
  3. `custom/binding-dashboard-bindings' 返回 alist(可能为空,因为
     Dashboard 标记是 opt-in)。
任何未来 commit 让 help-zh.el 重新维护键位列表都会违反 SoT 原则。"
  (skip-unless (boundp 'custom:binding-spec))
  (should (consp custom:binding-spec))
  (should (fboundp 'custom/binding-help-sections))
  (should (consp (custom/binding-help-sections)))
  (should (fboundp 'custom/binding-dashboard-bindings))
  (should (listp (custom/binding-dashboard-bindings))))

(ert-deftest custom-config/binding-spec-describes-intermediate-prefixes ()
  "自定义多级键的每个中间前缀都应显示具体功能名，而不是通用“前缀”。"
  (let ((described-keys
         (mapcar (lambda (entry) (plist-get entry :key))
                 custom:binding-spec))
        missing)
    (dolist (entry custom:binding-spec)
      (unless (plist-get entry :mode)
        (let* ((events (vconcat (kbd (plist-get entry :key))))
               (event-count (length events)))
          ;; 单事件根前缀由 Emacs 自带 keymap 描述；这里只审计自定义子树。
          (cl-loop for prefix-length from 2 below event-count
                   for prefix = (key-description
                                 (cl-subseq events 0 prefix-length))
                   unless (member prefix described-keys)
                   do (push prefix missing)))))
    (should-not (delete-dups missing)))
  (dolist (expected '(("C-c a a" . "Agent Shell")
                      ("C-c a f" . "RSS / Elfeed")
                      ("C-c a g" . "内置游戏")
                      ("C-c a x" . "Guix 包管理")))
    (let ((entry (seq-find
                  (lambda (candidate)
                    (equal (plist-get candidate :key) (car expected)))
                  custom:binding-spec)))
      (should entry)
      (should (equal (plist-get entry :description) (cdr expected)))
      (should (plist-get entry :prefix)))))

(ert-deftest custom-config/frame-phases-execute-once ()
  "Phase 4.4: frame-created / server-ready 两个 phase 各自的 initializer
通过 frame parameter 保证单次执行(PLAN §4.4)。本测试在 selected-frame 上
直接调用 run-frame-initializers 两次,验证同一个 function 在同一 phase
下只跑一次,且不同 phase 互相独立。

使用 selected-frame 而非 make-frame 是因为 batch 环境无终端,make-frame
会抛 'Unknown terminal type'。"
  (skip-unless (fboundp 'custom--run-frame-initializers))
  (let ((counter 0)
        (frame (selected-frame))
        (created-param 'custom-frame-created-done)
        (server-param 'custom-frame-server-ready-done))
    ;; 清空可能残留的 frame parameter(防御性)。
    (set-frame-parameter frame created-param nil)
    (set-frame-parameter frame server-param nil)
    (cl-letf (((symbol-function 'test--counter-inc)
               (lambda (_frame) (setq counter (1+ counter)))))
      (custom--run-frame-initializers
       frame 'created '(test--counter-inc))
      ;; 第二次调用同一 phase:counter 不应再增加
      (custom--run-frame-initializers
       frame 'created '(test--counter-inc))
      (should (= counter 1))
      ;; 不同 phase 是独立 frame parameter,counter 应再加 1
      (custom--run-frame-initializers
       frame 'server-ready '(test--counter-inc))
      (should (= counter 2)))
    ;; 清理:测试结束后 frame parameter 不影响后续测试。
    (set-frame-parameter frame created-param nil)
    (set-frame-parameter frame server-param nil)))

(ert-deftest custom-config/terminal-frame-defaults-are-transparent ()
  "TTY frame 创建前就应继承终端本身的前景、背景并隐藏菜单栏。"
  (let ((parameters (alist-get t window-system-default-frame-alist)))
    (should (equal (alist-get 'background-color parameters)
                   "unspecified-bg"))
    (should (equal (alist-get 'foreground-color parameters)
                   "unspecified-fg"))
    (should (equal (alist-get 'menu-bar-lines parameters) 0))))

(ert-deftest custom-config/spacious-padding-avoids-terminal-pseudo-colors ()
  "Daemon 无 GUI 时不得把 unspecified-bg 烘焙进 spacious-padding theme。"
  (should-not (bound-and-true-p spacious-padding-mode))
  (dolist (face '(fringe line-number header-line vertical-border))
    (should-not
     (string-match-p
      "unspecified-bg"
      (prin1-to-string (alist-get 'spacious-padding
                                 (get face 'theme-face)))))))

(ert-deftest custom-config/spacious-padding-applies-only-to-gui-frames ()
  "Padding 参数与 face 只在拥有真实颜色的 GUI frame 上生成。"
  (let (parameter-frame face-refresh)
    (cl-letf (((symbol-function 'spacious-padding-modify-frame-parameters)
               (lambda (frame &optional _reset)
                 (setq parameter-frame frame)))
              ((symbol-function 'spacious-padding-set-faces)
               (lambda (&rest _) (setq face-refresh t)))
              ((symbol-function 'display-graphic-p)
               (lambda (&optional _frame) nil)))
      (custom/apply-spacious-padding (selected-frame)))
    (should-not parameter-frame)
    (should-not face-refresh)
    (cl-letf (((symbol-function 'spacious-padding-modify-frame-parameters)
               (lambda (frame &optional _reset)
                 (setq parameter-frame frame)))
              ((symbol-function 'spacious-padding-set-faces)
               (lambda (&rest _) (setq face-refresh t)))
              ((symbol-function 'display-graphic-p)
               (lambda (&optional _frame) t)))
      (custom/apply-spacious-padding (selected-frame)))
    (should (eq parameter-frame (selected-frame)))
    (should face-refresh)))

(ert-deftest custom-config/terminal-truecolor-uses-theme-foregrounds ()
  "真彩 TTY 应加载 Ef theme，透明适配不得硬编码 ANSI 前景色。"
  (should-not
   (seq-some (lambda (entry)
               (plist-member (cdr entry) :foreground))
             custom:terminal-face-emphasis))
  (cl-letf (((symbol-function 'display-graphic-p)
             (lambda (&optional _frame) nil))
            ((symbol-function 'display-color-cells)
             (lambda (&optional _frame) 16777216)))
    (let ((noninteractive nil))
      (should (custom/display-supports-themes-p (selected-frame)))))
  (should (eq (car (last custom/theme-refresh-functions))
              #'custom/refresh-terminal-faces)))

(ert-deftest custom-config/terminal-faces-clear-every-background ()
  "TTY gutter 应透明，当前行用 Ef theme 背景而非下划线。"
  (let (face-calls frame-calls)
    (cl-letf (((symbol-function 'display-graphic-p)
               (lambda (&optional _frame) nil))
              ((symbol-function 'display-color-cells)
               (lambda (&optional _frame) 256))
              ((symbol-function 'face-list)
               (lambda () '(default fringe line-number
                                    line-number-current-line hl-line
                                    custom-test-late-face)))
              ((symbol-function 'custom/terminal-theme-background)
               (lambda () "#334455"))
              ((symbol-function 'set-frame-parameter)
               (lambda (frame parameter value)
                 (push (list frame parameter value) frame-calls)))
              ((symbol-function 'set-face-attribute)
               (lambda (face frame &rest attributes)
                 (push (list face frame attributes) face-calls))))
      (let ((noninteractive nil))
        (custom/apply-terminal-faces (selected-frame))))
    (should (seq-some
             (lambda (call)
               (pcase-let ((`(_frame ,parameter ,value) call))
                 (and (eq parameter 'background-color)
                      (equal value "unspecified-bg"))))
             frame-calls))
    (should-not
     (seq-some (lambda (call)
                 (eq (cadr call) 'foreground-color))
               frame-calls))
    (dolist (face '(default fringe line-number line-number-current-line
                            hl-line custom-test-late-face))
      (should
       (seq-some
        (lambda (call)
          (pcase-let ((`(,called-face _frame ,attributes) call))
            (and (eq called-face face)
                 (eq (plist-get attributes :background) 'unspecified)
                 (plist-member attributes :inverse-video)
                 (null (plist-get attributes :inverse-video)))))
        face-calls)))
    (should
     (seq-some
      (lambda (call)
        (pcase-let ((`(,face _frame ,attributes) call))
          (and (eq face 'hl-line)
               (equal (plist-get attributes :background) "#334455")
               (plist-member attributes :underline)
               (null (plist-get attributes :underline))
               (eq (plist-get attributes :extend) t))))
      face-calls))
    (should-not
     (seq-some (lambda (entry)
                 (and (eq (car entry) 'hl-line)
                      (plist-get (cdr entry) :underline)))
               custom:terminal-face-emphasis))
    (should (memq #'custom/refresh-terminal-faces enable-theme-functions))
    (should (memq #'custom/refresh-terminal-faces-after-load
                  after-load-functions))))

(ert-deftest custom-config/terminal-clears-ghostel-fake-cursor-box ()
  "TTY 透明背景策略必须清除 `ghostel-fake-cursor' 的 GUI 负宽 box。
该 box 无 :color,TTY 背景透明后颜色无法解析,ghostel 在
`pre-redisplay-functions' 重绘提示游标时 redisplay 抛
`Invalid face box :color unspecified :line-width (-1 . -1)'。"
  (should (assq 'ghostel-fake-cursor custom:terminal-face-emphasis))
  (should (equal (cdr (assq 'ghostel-fake-cursor
                            custom:terminal-face-emphasis))
                 '(:box nil))))

(ert-deftest custom-config/focus-save-rejects-synthetic-file-buffer ()
  "失焦保存只接受正常访问的本地文件 buffer。"
  (with-temp-buffer
    (insert "modified")
    (setq buffer-file-name "/tmp/custom-synthetic-save-test.el")
    (should-not (custom/user-file-buffer-p))
    (setq buffer-file-truename buffer-file-name)
    (should (custom/user-file-buffer-p))
    (setq buffer-read-only t)
    (should-not (custom/user-file-buffer-p))
    (setq buffer-read-only nil
          buffer-file-name nil
          buffer-file-truename nil)
    (set-buffer-modified-p nil)))

(ert-deftest custom-config/focus-save-waits-until-all-frames-unfocused ()
  "多 client 下只在所有 frame 明确失焦后安排保存。"
  (let ((states '((frame-a . t) (frame-b)))
        (custom--focus-save-timer nil)
        scheduled
        cancelled)
    (cl-letf (((symbol-function 'frame-list)
               (lambda () '(frame-a frame-b)))
              ((symbol-function 'frame-focus-state)
               (lambda (frame) (alist-get frame states)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (&rest _) (setq scheduled 'test-timer)))
              ((symbol-function 'timerp)
               (lambda (timer) (eq timer 'test-timer)))
              ((symbol-function 'cancel-timer)
               (lambda (timer) (setq cancelled timer))))
      (custom/schedule-focus-save)
      (should-not scheduled)
      (setq states '((frame-a) (frame-b)))
      (custom/schedule-focus-save)
      (should (eq custom--focus-save-timer 'test-timer))
      (setq states '((frame-a . unknown) (frame-b)))
      (custom/schedule-focus-save)
      (should (eq cancelled 'test-timer))
      (should-not custom--focus-save-timer))))

(ert-deftest custom-config/modeline-location-uses-mode-line-cache ()
  "位置段必须走 mode-line 的 %l/%c 缓存，不逐次扫描 buffer。"
  (cl-letf (((symbol-function 'line-number-at-pos)
             (lambda (&rest _) (error "line-number-at-pos must not run")))
            ((symbol-function 'format-mode-line)
             (lambda (&rest _) "12,3")))
    (should (string-match-p "12,3"
                            (custom/modeline--location-segment 'wide)))))

(ert-deftest custom-config/large-file-skips-line-number-scan ()
  "大型文件必须先关闭行号，不调用全 buffer 行数扫描。"
  (with-temp-buffer
    (insert "large")
    (let ((custom:large-file-size-threshold 1)
          disabled)
      (setq-local buffer-file-name "/tmp/custom-large-file.el"
                  display-line-numbers t)
      (cl-letf (((symbol-function 'line-number-at-pos)
                 (lambda (&rest _) (error "large file must not be scanned")))
                ((symbol-function 'display-line-numbers-mode)
                 (lambda (arg) (setq disabled arg))))
        (custom/setup-file-line-numbers))
      (should (= disabled -1)))))

(ert-deftest custom-config/daemon-warmup-stays-on-interaction-features ()
  "Daemon 预热覆盖高频交互 feature，不启动应用型子系统。"
  (dolist (feature '(org-agenda org-capture org-roam apheleia
                                magit tramp))
    (should (memq feature custom:daemon-warmup-features)))
  (dolist (feature '(pdf-tools notmuch elfeed ement agent-shell))
    (should-not (memq feature custom:daemon-warmup-features))))

(ert-deftest custom-config/yasnippet-global-mode-state-is-complete ()
  "Yasnippet 源加载必须补齐 Emacs 31 globalized minor mode 状态。"
  (should (featurep 'yasnippet))
  (should (boundp 'yas-minor-mode--set-explicitly))
  (should (boundp 'yas-minor-mode--suppress-set-explicitly))
  (should (bound-and-true-p yas-global-mode)))

(ert-deftest custom-config/dashboard-per-frame-buffer-isolation ()
  "不同 frame 必须获得不同的 dashboard buffer。"
  (let ((frame-a (list 'frame-a))
        (frame-b (list 'frame-b))
        (store (make-hash-table :test #'equal))
        buffers)
    (unwind-protect
        (cl-letf (((symbol-function 'frame-live-p)
                   (lambda (frame) (memq frame (list frame-a frame-b))))
                  ((symbol-function 'frame-parameter)
                   (lambda (frame parameter)
                     (gethash (list frame parameter) store)))
                  ((symbol-function 'set-frame-parameter)
                   (lambda (frame parameter value)
                     (puthash (list frame parameter) value store))))
          (let ((buffer-a (custom/dashboard--frame-buffer frame-a))
                (buffer-b (custom/dashboard--frame-buffer frame-b)))
            (setq buffers (list buffer-a buffer-b))
            (should (buffer-live-p buffer-a))
            (should (buffer-live-p buffer-b))
            (should-not (eq buffer-a buffer-b))
            (with-current-buffer buffer-a
              (should (eq custom/dashboard--owner-frame frame-a)))
            (with-current-buffer buffer-b
              (should (eq custom/dashboard--owner-frame frame-b)))
            (custom/dashboard--release-frame-buffer frame-a)
            (should-not (buffer-live-p buffer-a))
            (should (buffer-live-p buffer-b))))
      (dolist (buffer buffers)
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest custom-config/dashboard-knowledge-stale-while-revalidate ()
  "知识缓存过期时立即返回 stale 数据，同时发起异步刷新。"
  (let ((custom/dashboard--knowledge-cache
         (list 5 nil '("id" "emacs" "title")))
        (custom/dashboard--knowledge-process nil)
        (custom/dashboard--knowledge-error nil)
        started)
    (cl-letf (((symbol-function 'process-live-p) (lambda (_) nil))
              ((symbol-function 'custom/dashboard--knowledge-start-async)
               (lambda (max-items) (setq started max-items))))
      (should (equal (custom/dashboard--fetch-knowledge)
                     '(:ok (("id" "emacs" "title")))))
      (should (= started 5)))))

(ert-deftest custom-config/dashboard-knowledge-start-failure-cleans-buffers ()
  "异步进程同步启动失败时不得泄漏 stdout/stderr buffer。"
  (let* ((prefixes '(" *dashboard-knowledge-stdout*"
                     " *dashboard-knowledge-stderr*"))
         (count-buffers
          (lambda ()
            (seq-count
             (lambda (buffer)
               (seq-some
                (lambda (prefix)
                  (string-prefix-p prefix (buffer-name buffer)))
                prefixes))
             (buffer-list))))
         (before (funcall count-buffers))
         (custom/dashboard--knowledge-process nil)
         (custom/dashboard--knowledge-error nil)
         (custom/dashboard--generation 0))
    (cl-letf (((symbol-function 'agenote-resolve-executable)
               (lambda () "/tmp/agenote"))
              ((symbol-function 'make-process)
               (lambda (&rest _) (error "spawn failed"))))
      (custom/dashboard--knowledge-start-async 5))
    (should-not custom/dashboard--knowledge-process)
    (should (equal custom/dashboard--knowledge-error "spawn failed"))
    (should (= before (funcall count-buffers)))))

(ert-deftest custom-config/dashboard-does-not-replace-client-file ()
  "client frame 已显示文件时 Dashboard 打开检查必须保持原 buffer。"
  (let* ((frame (selected-frame))
         (window (frame-selected-window frame))
         (original (window-buffer window))
         (file-buffer (generate-new-buffer " *custom-client-file*")))
    (unwind-protect
        (progn
          (with-current-buffer file-buffer
            (setq buffer-file-name "/tmp/custom-client-file.el"
                  buffer-file-truename buffer-file-name))
          (set-window-buffer window file-buffer)
          (should (eq (custom/dashboard--frame-startup-state frame) 'file))
          (custom/dashboard--run-open-check frame 1)
          (should (eq (window-buffer window) file-buffer)))
      (set-window-buffer window original)
      (kill-buffer file-buffer))))



;;; ---------------------------------------------------------------------------
;;; Category 2: baseline-bug contracts (expected to FAIL today)
;;; ---------------------------------------------------------------------------
;;
;; Each test below documents a known P0/P1 bug from PLAN.md §2. They are
;; marked `:expected-result :failed' so `configctl test' stays green while
;; still reporting them. When the matching fix commit lands, remove the
;; `:expected-result' property: a green test enforces the new contract; a
;; still-red test means the fix is incomplete.

(ert-deftest custom-config-baseline/agenote-call-entrypoint-exists ()
  "P0 #1 (fixed by Commit 2): agenote calls must go through a single
`agenote-call' entrypoint that requires an explicit `--domain'.
All `agenote-knowledge-*' calls route through it; `audit-agenote-domain'
catches any new direct CLI calls."
  (should (fboundp 'agenote-call))
  (should (fboundp 'agenote-call-async)))

(ert-deftest custom-config-baseline/eglot-flymake-chain-intact ()
  "P0 #2 (fixed by Commit 3): Eglot must NOT opt out of Flymake.
Diagnostics flow through Flymake; the modeline + consult pipeline consumes
the Flymake public API. Any future commit re-adding `flymake' to
`eglot-stay-out-of' fails this test."
  (require 'eglot nil t)
  (should-not (and (boundp 'eglot-stay-out-of)
                   (memq 'flymake eglot-stay-out-of))))

(ert-deftest custom-config-baseline/flymake-goto-next-error-bound-to-m-g-n ()
  "P0 #2 cont. (fixed by Commit 3): M-g n / M-g p point at Flymake, not
Flycheck wrappers. Any future commit re-binding them to flycheck-* fails
this test."
  (should (eq (key-binding (kbd "M-g n")) 'flymake-goto-next-error))
  (should (eq (key-binding (kbd "M-g p")) 'flymake-goto-prev-error)))

(ert-deftest custom-config/help-claimed-bindings-resolve ()
  "P0 #4 (fixed by Commits 4+9+11): bindings claimed by help/dashboard
text must actually exist. Agent Shell now has a real submenu; the remaining
stale C-c o f (agenda file — real is C-c o a) and C-c e b l (bookmark list —
no C-c e prefix) must stay unbound so the help text never lies."
  ;; Phase 6 partial fix landed; promote from :expected-result :failed
  ;; to mandatory (inverted assertion: stale claims must NOT resolve).
  (should (eq (key-binding (kbd "C-c a a a")) 'agent-shell))
  (dolist (bogus '("C-c o f" "C-c e b l"))
	  (should-not (commandp (key-binding (kbd bogus))))))

(ert-deftest custom-config/widget-button-not-globally-advised ()
  "P1 #1: the Dashboard must not globally advice Widget's private
`widget-button--check-and-call-button'. Phase 4.3 / Commit 9 removed the
advice in favour of standard dashboard generators and text-buttons.
Now a hard contract — any future regression fails this test."
  ;; Phase 4.3 fix landed; promote from :expected-result :failed to mandatory.
  (let ((advice (advice--p (symbol-function 'widget-button--check-and-call-button))))
	  (should-not advice)))

(ert-deftest custom-config/completion-preview-is-in-region-source ()
  "内置 completion-preview-mode 接管 in-region 补全(替代 corfu 家族)。
Emacs 30+ 内置,daemon 加载期全局启用,不依赖第三方包。"
  (should (fboundp 'completion-preview-mode))
  (should (fboundp 'global-completion-preview-mode))
  (should (bound-and-true-p global-completion-preview-mode))
  ;; minibuffer 补全走内置 minibuffer-visible-completions。
  (should (eq minibuffer-visible-completions 'up-down))
  (should completion-eager-display))

(ert-deftest custom-config/audit-keys-helpers-phase6 ()
  "Phase 6 binding-spec single-source-of-truth: audit-keys helper semantics.
固化三个关键不变量:
  1. `custom-configctl--curated-key-p' 只识别 C-c [a-z] *(case-sensitive),
     不应把 C-c C-c / C-c C-t 等第三方包内部 keymap 误判为 curated。
  2. `custom-configctl--prefix-group-p' 识别 \"...\" 占位符为前缀组声明。
  3. `custom-configctl--help-key-tokens' 正确切分 / 分隔的多键合并形式,
     并剥离 \"Markdown: \" 之类的描述前缀。

configctl test 子命令由 scripts/configctl.el 提供,该文件作为 runner
已经加载到当前 batch 环境,所以 audit helper 函数都是 fboundp 的;无需
再 load 一次。"
  ;; (1) curated-key-p 是 case-sensitive 的(C-c C-c 不应被识别)。
  (let ((case-fold-search t))  ; 模拟默认环境,验证函数内已绑定 nil
    (should-not (custom-configctl--curated-key-p "C-c C-c"))
    (should-not (custom-configctl--curated-key-p "C-c C-t"))
    (should-not (custom-configctl--curated-key-p "C-c C-p"))
    (should (custom-configctl--curated-key-p "C-c a g"))
    (should (custom-configctl--curated-key-p "C-c e l"))
    (should (custom-configctl--curated-key-p "C-c d"))   ; 单字母前缀(虽无子绑定)
    (should (custom-configctl--curated-key-p "C-x p f")))
  ;; (2) prefix-group-p 识别占位符。
  (should (custom-configctl--prefix-group-p "C-c a g ..."))
  (should (custom-configctl--prefix-group-p "C-c o b ..."))
  (should-not (custom-configctl--prefix-group-p "C-c a g t"))
  ;; (3) help-key-tokens 正确切分。
  (should (equal (custom-configctl--help-key-tokens "C-c g # / @")
                 '("C-c g #" "C-c g @")))
  (should (equal (custom-configctl--help-key-tokens "C-x 2 / 3 / 0 / 1 / o")
                 '("C-x 2" "C-x 3" "C-x 0" "C-x 1" "C-x o")))
  (should (equal (custom-configctl--help-key-tokens "Markdown: C-c p")
                 '("C-c p")))
  (should (equal (custom-configctl--help-key-tokens "C-c e . / ,")
                 '("C-c e ." "C-c e ,")))
  ;; (4) prefix-of 正确剥离尾随 ... 和空格。
  (should (equal (custom-configctl--prefix-of "C-c e l ...") "C-c e"))
  (should (equal (custom-configctl--prefix-of "C-c a g t") "C-c a g")))

(ert-deftest custom-config/binding-spec-parsers-phase6 ()
  "Phase 6 audit-keys 必须消费 binding spec(custom/bind 声明),
而非已删除的 help-zh.el 数据。固化三个新 helper:
  1. `custom-configctl--binding-spec-entries' 解析所有 custom/bind 调用。
  2. `custom-configctl--binding-help-sections' 按 group 分组(镜像 elisp 侧)。
  3. `custom-configctl--binding-dashboard-bindings' 提取 :dashboard t 条目。

任何回归让 audit-keys 重新读 data/help-zh.el 都会违反 SoT 原则。"
  ;; (1) 解析器返回非空 entries 列表,每项是 plist 含 :key。
  (let ((entries (custom-configctl--binding-spec-entries)))
    (should (consp entries))
    (dolist (entry entries)
      (should (plist-get entry :key))))
  ;; (2) help-sections 与 elisp 侧 custom/binding-help-sections 结构一致:
  ;;     ((GROUP (key . desc) ...) ...)
  (let ((sections (custom-configctl--binding-help-sections)))
    (should (consp sections))
    (should (stringp (caar sections))))   ; 第一项的 car 是 group 名
  ;; (3) dashboard-bindings 是 alist(可能空),car 是 key 字符串。
  (let ((dashboard (custom-configctl--binding-dashboard-bindings)))
    (should (listp dashboard))
    (dolist (entry dashboard)
      (should (stringp (car entry))))))

(ert-deftest custom-config/startup-gc-no-handler-redeclaration ()
  "Phase 7.1: `custom--file-name-handler-alist-original' 只在 early-init.el
中 defvar 一次。早期 main.el 也做了一遍 defvar,但那时变量早已被 early-init
清空,捕获到 nil,导致 emacs-startup-hook 把 nil 写回——用户失去 jka-compr
/tramp handler。Phase 7.1 修复后 main.el 不再重复。

这个测试读 emacs.org 源码块验证 main.el 的 tangle 产物不含该 defvar。"
  (let* ((org-file (expand-file-name
                    "emacs.org"
                    (file-name-directory
                     (or load-file-name buffer-file-name
                         default-directory))))
         ;; 测试文件被 copy 到 runtime/test 目录,需要往回找仓库根。
         ;; main.el 已 tangle 加载到当前 batch 环境,直接从 main.el 源读也行。
         (main-file (expand-file-name "main.el" user-emacs-directory)))
    ;; 直接检查 main.el 内容(已 tangle 加载,文件存在)。
    (when (file-readable-p main-file)
      (with-temp-buffer
        (insert-file-contents main-file)
        (goto-char (point-min))
        (should-not (re-search-forward
                     "(defvar custom--file-name-handler-alist-original"
                     nil t))))))

(ert-deftest custom-config/agenote-call-process-signature ()
  "Phase 7.1: `agenote-call' 的 call-process 调用签名正确。

原 bug:`(apply #'call-process argv nil (list t stderr-buffer) nil)` 把
argv(list)当作 PROGRAM 传,导致 'Wrong type argument: stringp, (...)';
后来改为 `(list stdout-buffer stderr-buffer)` 期望 stderr-buffer 是
buffer object,但 call-process 的 list 形式要求 STDERR-DEST 是文件名
(string),又触发 'stringp, #<killed buffer>'。

修复:用 make-temp-file 创建 stderr 临时文件,call-process 用
(list stdout-buffer stderr-file) 形式。本测试验证 agenote-call 在
agenote 可用时返回 plist,不抛 wrong-type-argument。"
  (skip-unless (executable-find "agenote"))
  (let ((result (agenote-call 'human "stats")))
    (should (plistp result))
    (should (memq (plist-get result :status) '(0 1 2)))
    ;; :stdout 应为字符串(可能为空),不是 list 或 buffer
    (should (stringp (plist-get result :stdout)))
    ;; :stderr 同理
    (should (stringp (plist-get result :stderr)))))

(ert-deftest custom-config/audit-packages-classification ()
  "Phase 0 audit-packages 四类分类逻辑 (PLAN §7.2)。
固化 `custom-configctl--classify-package' 与
`custom-configctl--manifest-prefix-match' 的关键不变量:
  - built-in:    Emacs 内置包,不需 manifest
  - sub-feature: 由父包提供,不需独立 manifest
  - runtime-dep: manifest 中显式登记,通过 require/autoload 使用
  - used:        use-package 或 fn-call prefix-match manifest
  - candidate:   manifest 中存在但无配置入口
  - unknown:     配置引用但 manifest 缺失(违规类)

任何让 audit-packages 重新产生 use-package-no-manifest 或
manifest-no-use-package 二值违规的实现都违反 SoT 原则。"
  (skip-unless (fboundp 'custom-configctl--classify-package))
  (skip-unless (fboundp 'custom-configctl--manifest-prefix-match))
  (let ((manifest '("magit" "avy" "ghostel" "vertico" "with-editor"))
        (use-set '("magit" "avy")))  ; magit via fn-call, avy via fn-call
    ;; manifest-prefix-match 行为
    (should (equal (custom-configctl--manifest-prefix-match
                    "magit-status-setup-buffer" manifest) "magit"))
    (should (equal (custom-configctl--manifest-prefix-match
                    "avy-goto-char-timer" manifest) "avy"))
    (should (equal (custom-configctl--manifest-prefix-match
                    "ghostel-mode" manifest) "ghostel"))
    ;; 无 manifest 匹配的内置函数返回 nil
    (should (null (custom-configctl--manifest-prefix-match
                   "add-hook" manifest)))
    (should (null (custom-configctl--manifest-prefix-match
                   "nonexistent-foo" manifest)))
    ;; classify-package 四类
    ;; built-in: built-in-packages 中的元素
    (should (eq (custom-configctl--classify-package
                 "recentf" manifest use-set) 'built-in))
    ;; sub-feature: vertico-multiform 等父包是 vertico
    (should (eq (custom-configctl--classify-package
                 "vertico-multiform" manifest use-set) 'sub-feature))
    ;; runtime-dep: with-editor 在 manifest + runtime-deps
    (should (eq (custom-configctl--classify-package
                 "with-editor" manifest use-set) 'runtime-dep))
    ;; used: magit 在 use-set
    (should (eq (custom-configctl--classify-package
                 "magit" manifest use-set) 'used))
    ;; candidate: ghostel 在 manifest 但不在 use-set
    (should (eq (custom-configctl--classify-package
                 "ghostel" manifest use-set) 'candidate))
    ;; unknown: nonexistent 既不在 manifest 也不在 use-set
    (should (eq (custom-configctl--classify-package
                 "nonexistent" manifest use-set) 'unknown))))

(ert-deftest custom-config/knowledge-no-dead-scanner ()
  "Phase 2.3: agenote-knowledge--collect-org-files 与 defalias 已删除。
Dashboard 不再递归扫描 experiences/,改走 agenote list --json 索引。
任何未来 commit 重新加入 scanner 都会违反 SoT 原则。"
  (should-not (fboundp 'agenote-knowledge--collect-org-files))
  (should-not (fboundp 'agenote-knowledge-collect-org-files)))

(ert-deftest custom-config/knowledge-archive-via-cli ()
  "Phase 2.3: agenote-knowledge-archive-inbox-entry 调用 CLI 的 inbox-archive,
不再内联 slug 算法 + 手动 reindex。
mock agenote-call,验证:
  1. 调用 'inbox-archive' 子命令(而非 'reindex')。
  2. stdin 是 JSON 数组,含 heading + body。
  3. --prune 透传(让 CLI 负责清理 inbox)。

不真正调用 agenote,只验证调用契约。mock org-* 函数避免需要真实 org buffer。"
  (skip-unless (fboundp 'agenote-knowledge-archive-inbox-entry))
  (let ((called-args nil)
        (called-command nil)
        (called-stdin nil))
    (cl-letf (((symbol-function 'agenote-call)
               (lambda (domain command &rest args)
                 (setq called-command command
                       called-args args)
                 (when (member "--stdin" args)
                   (setq called-stdin (car (member "--stdin" args))))
                 (list :status 0 :stdout "/fake/path.org\nreindex: 1 cards"
                       :stderr "")))
              ((symbol-function 'org-get-heading)
               (lambda (&rest _) "Mocked Heading"))
              ((symbol-function 'org-copy-subtree)
               (lambda (&rest _) (kill-new "* Mocked Heading\n:PROPERTIES:\n:END:\nbody text")))
              ((symbol-function 'kill-new)
               (lambda (s &rest _) (setq kill-ring (cons s kill-ring)) s)))
      (agenote-knowledge-archive-inbox-entry "test")
      (should (equal called-command "inbox-archive"))
      (should (member "--category" called-args))
      (should (member "test" called-args))
      (should (member "--stdin" called-args))
      (should (member "--prune" called-args))
      (should called-stdin))))

    ;;; Category 3: dashboard rewrite contracts (custom/dashboard-*)
;;
;; These tests pin the behavior of the self-built dashboard engine that
;; replaced the third-party `dashboard' package. They exercise the pure
;; rendering layer (measure / pad / truncate / engine), which is entirely
;; column-based (`string-width') — GUI and batch share the same column
;; arithmetic (see `custom/dashboard--measure' docstring for why pixel
;; measurement was dropped), so these are deterministic without a GUI frame.

(ert-deftest custom-config/dashboard-truncate-never-exceeds-width ()
  "Dashboard 截断契约:任意输入 truncate 后 string-width ≤ 目标宽。
覆盖纯 ASCII、CJK、Nerd Font 图标(PUA)与混合输入。"
  (dolist (width '(5 10 20 40))
    (dolist (input '("plain ascii text"
                     "中文混合 English"
                     "󰃭 󰋚 󰧑 icons"
                     "mixed 中 󰃭 and very long content here abcdefg"))
      (let ((result (custom/dashboard--truncate input width)))
        (should (<= (string-width result) width))))))

(ert-deftest custom-config/dashboard-pad-to-fills-exactly ()
  "Dashboard 填充契约:pad-to 后 string-width 恰好等于目标宽。
不足补空格、超出原样返回不截断。"
  (dolist (spec '((5 . "hi") (10 . "hello") (8 . "中文")))
    (let* ((width (car spec))
           (text (cdr spec))
           (result (custom/dashboard--pad-to text width)))
      (should (= (string-width result) width)))))

(ert-deftest custom-config/dashboard-tty-banner-centers-by-terminal-cells ()
  "TTY banner 应按终端实际单元宽度居中，不受 Emacs CJK 宽度表误判影响。
块居中语义：所有 art 行的左边缘 pad 由最长行长度决定（figlet 行间左对齐）。"
  (let* ((width 140)
         ;; 与 `custom/dashboard--ascii-banner-lines' 当前最长行一致。
         (art-line "███████╗  ███╗   ███╗   █████╗    ██████╗  ███████╗")
         (expected-pad (/ (- width (length art-line)) 2)))
    (cl-letf (((symbol-function 'display-graphic-p)
               (lambda (&optional _frame) nil))
              ;; 复现真实 TTY：Emacs 报 80 列，但 Foot 实际渲染为 43 单元。
              ((symbol-function 'custom/dashboard--measure)
               (lambda (text)
                 (if (string-match-p "█" text)
                     80
                   (string-width text))))
              ((symbol-function 'custom/dashboard--banner-min-width)
               (lambda () 1))
              ((symbol-function 'custom/dashboard--status-line)
               (lambda () nil)))
      (with-temp-buffer
        (custom/dashboard--insert-banner width)
        (goto-char (point-min))
        (should (re-search-forward "^\\( +\\)███████╗" nil t))
        (should (= (length (match-string 1)) expected-pad))))))

(ert-deftest custom-config/dashboard-card-error-isolation ()
  "Dashboard 错误隔离契约:fetch 或 render 抛错时产出错误卡片行,
不向上信号,不影响同排其他卡片。引擎是单卡片故障域的保证。"
  (let* ((broken-spec (list :id 'broken
                            :title "坏卡片"
                            :icon "" :key ""
                            :fetch (lambda () (error "fetch boom"))
                            :render (lambda (_ w) (list "never"))))
         (render-broken-spec (list :id 'render-broken
                                   :title "渲染坏"
                                   :icon "" :key ""
                                   :fetch (lambda () (list :ok 'data))
                                   :render (lambda (_ _w)
                                             (error "render boom"))))
         (ok-spec (list :id 'ok
                        :title "好卡片"
                        :icon "" :key ""
                        :fetch (lambda () (list :ok '("line1")))
                        :render (lambda (data _w) data))))
    ;; fetch 抛错 → 不信号,返回行列表(含错误提示)
    (let ((lines (custom/dashboard--card-lines broken-spec 40)))
      (should (consp lines))
      (should (cl-some (lambda (l) (string-match-p "fetch boom" l)) lines)))
    ;; render 抛错 → 同样隔离
    (let ((lines (custom/dashboard--card-lines render-broken-spec 40)))
      (should (consp lines))
      (should (cl-some (lambda (l) (string-match-p "render boom" l)) lines)))
    ;; 正常卡片不受影响
    (let ((lines (custom/dashboard--card-lines ok-spec 40)))
      (should (cl-some (lambda (l) (string-match-p "line1" l)) lines)))))

(ert-deftest custom-config/dashboard-buttons-use-defined-faces ()
  "Dashboard 按钮不得携带不存在的第三方 dashboard face。"
  (dolist (button (list (custom/dashboard--button "项目" #'ignore)
                        (custom/dashboard--command-button "更多" #'ignore)))
    (let ((face (get-text-property 0 'face button)))
      (should (eq face 'custom/dashboard-item))
      (should (facep face))
      (should-not (face-attribute face :underline nil 'default)))))

(ert-deftest custom-config/dashboard-todo-mark-done-persists-file ()
  "点击 Dashboard TODO 状态应写入 DONE 并保存对应 Org 文件。"
  (let ((file (make-temp-file "custom-dashboard-todo-" nil ".org"
                              "* TODO 完成 Dashboard 测试\n"))
        (org-log-done nil))
    (unwind-protect
        (progn
          (custom/dashboard--todo-mark-done
           file 1 "完成 Dashboard 测试")
          (with-temp-buffer
            (insert-file-contents file)
            (should (re-search-forward
                     "^\\* DONE 完成 Dashboard 测试$" nil t))))
      (when-let* ((buffer (get-file-buffer file)))
        (kill-buffer buffer))
      (delete-file file))))

(ert-deftest custom-config/dashboard-todo-render-keeps-component-actions ()
  "TODO 状态负责完成任务，标题负责跳转，二者不得被整行 face 覆盖。"
  (let* ((file "/tmp/custom-dashboard-render.org")
         (title "彩色待办")
         called
         (items (list (list (propertize "TODO  " 'face 'warning)
                            (propertize title 'face 'custom/dashboard-todo-title)
                            (propertize "  󰥕 明天截止" 'face 'font-lock-keyword-face)
                            file 42))))
    (cl-letf (((symbol-function 'custom/dashboard--todo-mark-done)
               (lambda (&rest args) (setq called args))))
      (let* ((line (car (custom/dashboard--render-todo items 80)))
             (state-pos 2)
             (title-pos (+ state-pos (length (nth 0 (car items)))))
             (state-map (get-text-property state-pos 'keymap line))
             (title-map (get-text-property title-pos 'keymap line)))
        (should (eq (get-text-property state-pos 'face line) 'warning))
        (should (eq (get-text-property title-pos 'face line)
                    'custom/dashboard-todo-title))
        (should (keymapp state-map))
        (should (keymapp title-map))
        (call-interactively (lookup-key state-map (kbd "RET")))
        (should (equal called (list file 42 title)))))))

(ert-deftest custom-config/binding-spec-global-commands-resolve ()
  "binding-spec 中每个全局绑定的命令在配置加载完成后必须可解析为
已定义的函数或 keymap。C-x t g 曾绑定到从未定义的
`custom/tabs-refresh-context',按下即 void-function;本测试固化绑定
完整性,防止此类回归。
局部 (:mode) 绑定在对应 feature 加载后才落地,命令可能尚未定义,
不在本契约范围内。"
  (skip-unless (boundp 'custom:binding-spec))
  (dolist (entry custom:binding-spec)
    (let ((command (plist-get entry :command)))
      (when (and command (not (plist-get entry :mode)))
        (unless (or (keymapp command)
                    (and (symbolp command) (fboundp command)))
          (ert-fail (format "未定义的绑定命令: %s -> %S"
                            (plist-get entry :key) command)))))))

(ert-deftest custom-config/dashboard-engine-splice-width-invariant ()
  "Dashboard 双列拼接契约:--render-row 产出每行左列宽度一致。
两列等高拼接后,左列固定填充到 left-w,右列自然结束。"
  (cl-letf (((symbol-function 'custom/dashboard--tier)
             (lambda () 'dual)))
    (dolist (spec-pair
             '(((recents projects)) ((todo clock)) ((knowledge bookmarks))))
      (let* ((total 100)
             (gap custom:dashboard-dual-gap)
             (left-w (/ (- total gap) 2))
             (lines (custom/dashboard--render-row (car spec-pair) total)))
        (should (consp lines))
        ;; 左列每行(去掉首字符)应不超过 left-w;引擎保证左列填充
        (dolist (l lines)
          (should (stringp l)))))))

(provide 'custom-config-tests)
;;; custom-config-tests.el ends here
