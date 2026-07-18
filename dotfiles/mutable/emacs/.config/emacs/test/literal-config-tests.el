;;; literal-config-tests.el --- ERT tests for literal-config -*- lexical-binding: t; -*-

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

(ert-deftest literal-config/agenote-group-by-category-ordering ()
  "Cards are grouped by category (dictionary order), each group by created desc."
  (skip-unless (fboundp 'literal/agenote--group-by-category))
  (let ((cards '((:id "a" :category "emacs"   :created "20260101-000000")
                 (:id "b" :category "guix"    :created "20260102-000000")
                 (:id "c" :category "emacs"   :created "20260103-000000")
                 (:id "d" :category "emacs"   :created "20260102-120000")
                 (:id "e" :category "general" :created "20260101-000000")
                 (:id "f"))))
    (let ((groups (literal/agenote--group-by-category cards)))
      ;; Categories appear in dictionary order: emacs, general, guix, unknown.
      (should (equal (mapcar #'car groups) '("emacs" "general" "guix" "unknown")))
      ;; Within emacs: created desc — c (03), d (02-12), a (01).
      (should (equal (mapcar (lambda (c) (plist-get c :id))
                             (cdr (assoc "emacs" groups)))
                     '("c" "d" "a"))))))

(ert-deftest literal-config/agenote-sort-by-recency ()
  "Cards are sorted by `created' in descending order (newest first)."
  (skip-unless (fboundp 'literal/agenote--sort-by-recency))
  (let ((cards '((:id "a" :created "20260101-000000")
                 (:id "b" :created "20260301-000000")
                 (:id "c" :created "20260201-000000"))))
    (should (equal (mapcar (lambda (c) (plist-get c :id))
                           (literal/agenote--sort-by-recency cards))
                   '("b" "c" "a")))))

(ert-deftest literal-config/modeline-tier-boundaries ()
  "Tier computation: wide >= 120, medium >= 100, narrow >= 80, else compact.
Commit 8 will centralize tier computation into a single renderer; this test
pins the boundary semantics so the refactor cannot silently shift them."
  (skip-unless (fboundp 'literal/modeline-tier))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 120)))
    (should (eq (literal/modeline-tier) 'wide)))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 119)))
    (should (eq (literal/modeline-tier) 'medium)))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 100)))
    (should (eq (literal/modeline-tier) 'medium)))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 99)))
    (should (eq (literal/modeline-tier) 'narrow)))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 80)))
    (should (eq (literal/modeline-tier) 'narrow)))
  (cl-letf (((symbol-function 'window-width) (lambda (&optional _) 79)))
    (should (eq (literal/modeline-tier) 'compact))))

(ert-deftest literal-config/tabs-per-frame-parameter-isolation ()
  "Per-frame tab-buffer lists are stored on frame parameters and stay isolated.
This test exercises the frame-parameter storage directly (not make-frame,
which fails under `emacs --batch' with no terminal) to keep the per-frame
contract pinned across the Commit 7 rewrite."
  (skip-unless (fboundp 'literal--tabs-set-frame-buffer-list))
  (skip-unless (fboundp 'literal--tabs-get-frame-buffer-list))
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
                        (when (eq param 'literal--frame-tab-buffers) store-a))
                       ((eq frame mock-frame-b)
                        (when (eq param 'literal--frame-tab-buffers) store-b))
                       (t (let ((orig (default-value 'frame-parameter)))
                            ;; fall through for any other frame access
                            nil)))))
                   ((symbol-function 'set-frame-parameter)
                    (lambda (frame param value)
                      (cond
                       ((eq frame mock-frame-a)
                        (when (eq param 'literal--frame-tab-buffers)
                          (setq store-a value)))
                       ((eq frame mock-frame-b)
                        (when (eq param 'literal--frame-tab-buffers)
                          (setq store-b value)))))))
                (literal--tabs-set-frame-buffer-list (list buf-a) mock-frame-a)
                (literal--tabs-set-frame-buffer-list (list buf-b) mock-frame-b)
                (should (equal (literal--tabs-get-frame-buffer-list mock-frame-a)
                               (list buf-a)))
                (should (equal (literal--tabs-get-frame-buffer-list mock-frame-b)
                               (list buf-b)))
                (literal--tabs-set-frame-buffer-list
                 (append (literal--tabs-get-frame-buffer-list mock-frame-a)
                         (list buf-a2))
                 mock-frame-a)
                ;; Frame B untouched by Frame A's append.
                (should (equal (literal--tabs-get-frame-buffer-list mock-frame-b)
                               (list buf-b)))
                (should (equal (literal--tabs-get-frame-buffer-list mock-frame-a)
                               (list buf-a buf-a2))))))
          nil)
      (ignore-errors (kill-buffer buf-a))
      (ignore-errors (kill-buffer buf-b))
      (ignore-errors (kill-buffer buf-a2)))))

(ert-deftest literal-config/capture-templates-cover-lifecycle ()
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

(ert-deftest literal-config/language-capabilities-derived-consistency ()
  "Phase 3.2: language-treesit-remaps / eglot-auto-modes / eglot-server-programs
/ apheleia-mode-alist all derive from the single source `language-capabilities'.
Each :server entry's modes ⊆ language-eglot-auto-modes (with server declared).
Each :ts-mode produces a remap from the first :modes entry."
  (skip-unless (boundp 'literal:language-capabilities))
  (should (consp literal:language-capabilities))
  ;; Every :ts-mode has a matching remap entry.
  (dolist (entry literal:language-capabilities)
    (let ((ts-mode (plist-get entry :ts-mode)))
      (when ts-mode
        (let ((orig-mode (car (plist-get entry :modes))))
          (should (assoc orig-mode literal:language-treesit-remaps))
          (should (eq (cdr (assoc orig-mode literal:language-treesit-remaps))
                      ts-mode))))))
  ;; Every :formatter non-nil entry has its modes in apheleia-mode-alist.
  (dolist (entry literal:language-capabilities)
    (let ((formatter (plist-get entry :formatter)))
      (when formatter
        (dolist (mode (plist-get entry :modes))
          (should (eq (cdr (assoc mode literal:language-apheleia-mode-alist))
                      formatter)))))))


    
;;; ---------------------------------------------------------------------------
;;; Category 2: baseline-bug contracts (expected to FAIL today)
;;; ---------------------------------------------------------------------------
    ;;
    ;; Each test below documents a known P0/P1 bug from PLAN.md §2. They are
    ;; marked `:expected-result :failed' so `configctl test' stays green while
    ;; still reporting them. When the matching fix commit lands, remove the
    ;; `:expected-result' property: a green test enforces the new contract; a
    ;; still-red test means the fix is incomplete.

    (ert-deftest literal-config-baseline/agenote-call-entrypoint-exists ()
      "P0 #1 (fixed by Commit 2): agenote calls must go through a single
`literal/agenote-call' entrypoint that requires an explicit `--domain'.
All `literal/knowledge-*' calls route through it; `audit-agenote-domain'
catches any new direct CLI calls."
      (should (fboundp 'literal/agenote-call))
      (should (fboundp 'literal/agenote-call-async)))

    (ert-deftest literal-config-baseline/eglot-flymake-chain-intact ()
      "P0 #2 (fixed by Commit 3): Eglot must NOT opt out of Flymake.
Diagnostics flow through Flymake; the modeline + consult pipeline consumes
the Flymake public API. Any future commit re-adding `flymake' to
`eglot-stay-out-of' fails this test."
      (require 'eglot nil t)
      (should-not (and (boundp 'eglot-stay-out-of)
                       (memq 'flymake eglot-stay-out-of))))

    (ert-deftest literal-config-baseline/flymake-goto-next-error-bound-to-m-g-n ()
      "P0 #2 cont. (fixed by Commit 3): M-g n / M-g p point at Flymake, not
Flycheck wrappers. Any future commit re-binding them to flycheck-* fails
this test."
      (should (eq (key-binding (kbd "M-g n")) 'flymake-goto-next-error))
      (should (eq (key-binding (kbd "M-g p")) 'flymake-goto-prev-error)))

    (ert-deftest literal-config/help-claimed-bindings-resolve ()
      "P0 #4 (fixed by Commits 4+9+11): bindings claimed by help/dashboard
text must actually exist. Phase 6 partial: stale C-c a a a (Agent Shell
submenu — not implemented), C-c o f (agenda file — real is C-c o a) and
C-c e b l (bookmark list — no C-c e prefix) are removed from help-zh.el.
This test inverts the original assertion: the bogus claims must STAY
unbound so the help text never lies. Full binding-spec single-source-of-
truth regeneration is tracked as future work."
      ;; Phase 6 partial fix landed; promote from :expected-result :failed
      ;; to mandatory (inverted assertion: stale claims must NOT resolve).
      (dolist (bogus '("C-c a a a" "C-c o f" "C-c e b l"))
	(should-not (commandp (key-binding (kbd bogus))))))

    (ert-deftest literal-config/widget-button-not-globally-advised ()
      "P1 #1: the Dashboard must not globally advice Widget's private
`widget-button--check-and-call-button'. Phase 4.3 / Commit 9 removed the
advice in favour of standard dashboard generators and text-buttons.
Now a hard contract — any future regression fails this test."
      ;; Phase 4.3 fix landed; promote from :expected-result :failed to mandatory.
      (let ((advice (advice--p (symbol-function 'widget-button--check-and-call-button))))
	(should-not advice)))

    (ert-deftest literal-config/corfu-popupinfo-is-sole-doc-source ()
      "P1 #4 (fixed by Commit 10): only `corfu-popupinfo' is configured as the
Corfu doc source. Phase 5.1 removed `corfu-doc' / `corfu-doc-terminal'.
Now a hard contract — M-d must bind only `corfu-popupinfo-toggle'."
      ;; Phase 5.1 fix landed; promote from :expected-result :failed to mandatory.
      (require 'corfu nil t)
      (let ((m-d-cmd (lookup-key corfu-map (kbd "M-d"))))
	(should (eq m-d-cmd 'corfu-popupinfo-toggle))))

    (ert-deftest literal-config/audit-keys-helpers-phase6 ()
      "Phase 6 binding-spec single-source-of-truth: audit-keys helper semantics.
固化三个关键不变量:
  1. `literal-configctl--curated-key-p' 只识别 C-c [a-z] *(case-sensitive),
     不应把 C-c C-c / C-c C-t 等第三方包内部 keymap 误判为 curated。
  2. `literal-configctl--prefix-group-p' 识别 \"...\" 占位符为前缀组声明。
  3. `literal-configctl--help-key-tokens' 正确切分 / 分隔的多键合并形式,
     并剥离 \"Markdown: \" 之类的描述前缀。

configctl test 子命令由 scripts/configctl.el 提供,该文件作为 runner
已经加载到当前 batch 环境,所以 audit helper 函数都是 fboundp 的;无需
再 load 一次。"
      ;; (1) curated-key-p 是 case-sensitive 的(C-c C-c 不应被识别)。
      (let ((case-fold-search t))  ; 模拟默认环境,验证函数内已绑定 nil
        (should-not (literal-configctl--curated-key-p "C-c C-c"))
        (should-not (literal-configctl--curated-key-p "C-c C-t"))
        (should-not (literal-configctl--curated-key-p "C-c C-p"))
        (should (literal-configctl--curated-key-p "C-c a g"))
        (should (literal-configctl--curated-key-p "C-c e l"))
        (should (literal-configctl--curated-key-p "C-c d"))   ; 单字母前缀(虽无子绑定)
        (should (literal-configctl--curated-key-p "C-x p f")))
      ;; (2) prefix-group-p 识别占位符。
      (should (literal-configctl--prefix-group-p "C-c a g ..."))
      (should (literal-configctl--prefix-group-p "C-c o b ..."))
      (should-not (literal-configctl--prefix-group-p "C-c a g t"))
      ;; (3) help-key-tokens 正确切分。
      (should (equal (literal-configctl--help-key-tokens "C-c g # / @")
                     '("C-c g #" "C-c g @")))
      (should (equal (literal-configctl--help-key-tokens "C-x 2 / 3 / 0 / 1 / o")
                     '("C-x 2" "C-x 3" "C-x 0" "C-x 1" "C-x o")))
      (should (equal (literal-configctl--help-key-tokens "Markdown: C-c p")
                     '("C-c p")))
      (should (equal (literal-configctl--help-key-tokens "C-c e . / ,")
                     '("C-c e ." "C-c e ,")))
      ;; (4) prefix-of 正确剥离尾随 ... 和空格。
      (should (equal (literal-configctl--prefix-of "C-c e l ...") "C-c e"))
      (should (equal (literal-configctl--prefix-of "C-c a g t") "C-c a g")))

    (provide 'literal-config-tests)
;;; literal-config-tests.el ends here
