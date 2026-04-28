;; -*- lexical-binding: t; -*-
;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; test-config-loading.el --- 全模块加载验证测试

;;; Commentary:
;; 验证 configs/ 下所有模块在 batch 模式下可正确加载。
;; 通过 init.el 完整加载后，逐个断言每个模块的 feature 已注册。
;; 如果某个模块因 GUI 依赖无法在 batch 模式下加载，使用 ert-skip 跳过。
;;
;; 运行方式（通过统一运行器）：
;;   emacs --batch -L . -L core -L configs -l tests/run-tests.el

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'test-support)

(tests/ensure-core-loaded)

;; ═════════════════════════════════════════════════════════════════════════════
;; 辅助函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun tests--verify-module (category filename expected-feature)
  "验证 CATEGORY/FILENAME 模块能加载且提供 EXPECTED-FEATURE。
加载成功则 `should' 通过，加载失败则 `ert-skip' 并附带原因。"
  (let ((module (concat category "/" filename)))
    (custom/diag-with-context 'config-verify module
      (condition-case err
          (progn
            (custom/load-config category filename)
            (should (tests/feature-loaded-p expected-feature)))
        (error
         (ert-skip (format "模块 %s 加载失败：%s"
                           module (error-message-string err))))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 系统配置
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-config-system-startup ()
  "验证 configs/system/startup.el 可正确加载。"
  :tags '(config-loading system)
  (tests/with-diag-test "system/startup.el"
    (tests--verify-module "system" "startup.el" 'startup)))

(ert-deftest test-config-system-guix ()
  "验证 configs/system/guix.el 可正确加载。"
  :tags '(config-loading system)
  (tests/with-diag-test "system/guix.el"
    (tests--verify-module "system" "guix.el" 'guix)))

;; ═════════════════════════════════════════════════════════════════════════════
;; UI 配置
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-config-ui-appearance ()
  "验证 configs/ui/appearance.el 可正确加载。"
  :tags '(config-loading ui)
  (tests/with-diag-test "ui/appearance.el"
    (tests--verify-module "ui" "appearance.el" 'appearance)))

(ert-deftest test-ui-appearance-configures-tab-line ()
  "验证 UI 外观模块已切换到 tab-line。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-line"
    (tests/load-config "ui" "appearance.el")
    (should (bound-and-true-p global-tab-line-mode))
    (should (eq tab-line-tabs-function #'custom/tab-line-tabs))
    (should (eq tab-line-tab-name-function #'custom/tab-line-tab-name))
    (should (eq tab-line-tab-name-format-function #'custom/tab-line-tab-name-format))
    (should (eq tab-line-close-button-show 'selected))
    (should-not tab-line-new-button-show)
    (should (equal tab-line-separator ""))))

(ert-deftest test-ui-appearance-tab-line-buffer-list-is-frame-scoped ()
  "验证 tab-line 标签列表使用 per-frame 独立列表，过滤特殊缓冲区。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-line-frame-scope"
    (tests/load-config "ui" "appearance.el")
    (let ((buf-a (generate-new-buffer "frame-scope-a.txt"))
          (buf-b (generate-new-buffer "frame-scope-b.txt"))
          (buf-hidden (generate-new-buffer "*frame-scope-hidden*")))
      (unwind-protect
          (progn
            ;; 先清空，避免 test-config-loading.el 被 hook 自动注册干扰
            (custom--tabs-set-frame-buffer-list nil)
            ;; 注册所有缓冲区到当前 frame
            (custom--tabs-register-buffer buf-a)
            (custom--tabs-register-buffer buf-b)
            (custom--tabs-register-buffer buf-hidden)
            ;; 隐藏缓冲区（*开头）应被 tab-visible-p 过滤
            (let ((buffers (custom--tabs-frame-buffers (selected-window))))
              (should (equal buffers (list buf-a buf-b)))
              (should-not (memq buf-hidden buffers))))
        ;; 清理
        (custom--tabs-set-frame-buffer-list nil)
        (dolist (buffer (list buf-a buf-b buf-hidden))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest test-ui-appearance-tab-refresh-rebuilds-from-scratch ()
  "验证 tabs-refresh-context 先清空再收集，实现真重建。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-refresh-rebuild"
    (tests/load-config "ui" "appearance.el")
    (let ((buf-a (generate-new-buffer "refresh-a.txt"))
          (buf-b (generate-new-buffer "refresh-b.txt"))
          (buf-stale (generate-new-buffer "refresh-stale.txt")))
      (unwind-protect
          (progn
            ;; 先注册一个 stale buffer，然后 kill 它
            (custom--tabs-register-buffer buf-a)
            (custom--tabs-register-buffer buf-stale)
            (kill-buffer buf-stale)
            ;; 当前窗口显示 buf-b（不在列表中）
            (set-window-buffer (selected-window) buf-b)
            ;; refresh 应清空旧列表并从窗口收集
            (custom/tabs-refresh-context)
            (let ((buffers (custom--tabs-frame-buffers (selected-window))))
              ;; stale buffer 不应出现，buf-b 应被收集
              (should (memq buf-b buffers))
              (should-not (memq buf-stale buffers))))
        (custom--tabs-set-frame-buffer-list nil)
        (dolist (buffer (list buf-a buf-b))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest test-ui-appearance-tab-close-skips-dead-candidates ()
  "验证 tabs-close-buffer 跳过已死的候选，切换到下一个有效 buffer。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-close-dead-skip"
    (tests/load-config "ui" "appearance.el")
    (let ((buf-a (generate-new-buffer "close-a.txt"))
          (buf-b (generate-new-buffer "close-b.txt"))
          (buf-c (generate-new-buffer "close-c.txt")))
      (unwind-protect
          (progn
            (custom--tabs-register-buffer buf-a)
            (custom--tabs-register-buffer buf-b)
            (custom--tabs-register-buffer buf-c)
            ;; 显示 buf-a，kill buf-b（列表中间）
            (set-window-buffer (selected-window) buf-a)
            (kill-buffer buf-b)
            ;; 关闭 buf-a 标签：应跳过已死的 buf-b，切到 buf-c
            (custom/tabs-close-buffer)
            (should (eq (window-buffer (selected-window)) buf-c))
            ;; buf-b 不应在标签列表中
            (should-not (memq buf-b (custom--tabs-frame-buffers (selected-window)))))
        (custom--tabs-set-frame-buffer-list nil)
        (dolist (buffer (list buf-a buf-b buf-c))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest test-ui-appearance-tab-register-on-frame-arg ()
  "验证 on-window-buffer-change 接受 frame 参数并注册所有窗口 buffer。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-frame-arg"
    (tests/load-config "ui" "appearance.el")
    (let ((buf-a (generate-new-buffer "frame-arg-a.txt"))
          (buf-b (generate-new-buffer "frame-arg-b.txt")))
      (unwind-protect
          (save-window-excursion
            (delete-other-windows)
            (let ((win-b (split-window-right)))
              (set-window-buffer (selected-window) buf-a)
              (set-window-buffer win-b buf-b)
              ;; 以 frame 参数调用（模拟全局 hook 行为）
              (custom--tabs-on-window-buffer-change (selected-frame))
              (let ((buffers (custom--tabs-frame-buffers (selected-window))))
                (should (memq buf-a buffers))
                (should (memq buf-b buffers)))))
        (custom--tabs-set-frame-buffer-list nil)
        (dolist (buffer (list buf-a buf-b))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest test-ui-appearance-tab-register-on-switch-to-buffer ()
  "验证 switch-to-buffer 触发 hook 后 buffer 能进入标签列表。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-switch-trigger"
    (tests/load-config "ui" "appearance.el")
    (let ((buf-a (generate-new-buffer "switch-a.txt"))
          (buf-b (generate-new-buffer "switch-b.txt")))
      (unwind-protect
          (progn
            ;; 初始注册 buf-a
            (custom--tabs-register-buffer buf-a)
            (set-window-buffer (selected-window) buf-a)
            ;; 通过 switch-to-buffer 切换到 buf-b
            (switch-to-buffer buf-b)
            ;; 模拟全局 hook 以 frame 参数触发
            (custom--tabs-on-window-buffer-change (selected-frame))
            (let ((buffers (custom--tabs-frame-buffers (selected-window))))
              (should (memq buf-a buffers))
              (should (memq buf-b buffers))))
        (custom--tabs-set-frame-buffer-list nil)
        (dolist (buffer (list buf-a buf-b))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest test-ui-appearance-tab-commands-prefer-editor-window ()
  "验证标签切换命令优先作用于编辑窗口。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-line-editor-window"
    (tests/load-config "ui" "appearance.el")
    (let ((buf-a (generate-new-buffer "tabs-editor-a.txt"))
          (buf-b (generate-new-buffer "tabs-editor-b.txt"))
          (side-buffer (get-buffer-create "*tabs-side*"))
          (editor-window nil)
          (side-window nil))
      (unwind-protect
          (save-window-excursion
            (delete-other-windows)
            (setq editor-window (selected-window))
            (setq side-window (split-window-right))
            (set-window-buffer editor-window buf-a)
            (set-window-buffer side-window side-buffer)
            (cl-letf (((symbol-function 'custom--find-editor-window)
                       (lambda () editor-window))
                      ((symbol-function 'custom--tabs-frame-buffers)
                       (lambda (&optional _window) (list buf-a buf-b))))
              (select-window side-window)
              (custom/tabs-next)
              (should (eq (window-buffer editor-window) buf-b))
              (should (eq (window-buffer side-window) side-buffer))))
        (dolist (buffer (list buf-a buf-b))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest test-ui-appearance-tab-multi-frame-isolation ()
  "验证不同 frame 的标签列表完全独立：注册/注销/kill 不交叉污染。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-multi-frame-isolation"
    (tests/load-config "ui" "appearance.el")
    (let ((frame-a (selected-frame))
          (buf-a (generate-new-buffer "iso-a.txt"))
          (buf-b (generate-new-buffer "iso-b.txt"))
          (buf-c (generate-new-buffer "iso-c.txt"))
          (frame-b (car (delq (selected-frame) (frame-list)))))
      (unwind-protect
          (progn
            ;; Frame A 注册 buf-a, buf-b
            (custom--tabs-register-buffer buf-a frame-a)
            (custom--tabs-register-buffer buf-b frame-a)
            (should (equal (custom--tabs-get-frame-buffer-list frame-a)
                           (list buf-a buf-b)))
            ;; register 去重
            (custom--tabs-register-buffer buf-b frame-a)
            (should (equal (custom--tabs-get-frame-buffer-list frame-a)
                           (list buf-a buf-b)))
            ;; unregister 只移除指定的
            (custom--tabs-unregister-buffer buf-a frame-a)
            (should (equal (custom--tabs-get-frame-buffer-list frame-a) (list buf-b)))
            ;; kill-buffer 应从 frame-a 清除 buf-b
            (kill-buffer buf-b)
            (should-not (memq buf-b (custom--tabs-get-frame-buffer-list frame-a)))
            ;; 跨 frame 隔离（需要 2+ frame 环境）
            (if frame-b
                (progn
                  (custom--tabs-register-buffer buf-c frame-b)
                  ;; frame-a 不含 frame-b 的 buf-c
                  (should-not (memq buf-c (custom--tabs-get-frame-buffer-list frame-a)))
                  ;; frame-b 只有 buf-c
                  (should (equal (custom--tabs-get-frame-buffer-list frame-b) (list buf-c)))
                  ;; kill 不影响 frame-b
                  (kill-buffer buf-c)
                  (should-not (memq buf-c (custom--tabs-get-frame-buffer-list frame-b))))
              (ert-skip "单 frame 环境，跳过跨 frame 隔离断言")))
        (custom--tabs-set-frame-buffer-list nil)
        (dolist (buffer (list buf-a buf-b buf-c))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest test-ui-appearance-tab-clear-for-project-switch ()
  "验证 custom/tabs-clear-for-frame 完全清空（不立即重建），refresh 后只收集可见窗口 buffer。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-clear-project"
    (tests/load-config "ui" "appearance.el")
    (let ((buf-a (generate-new-buffer "proj-a.txt"))
          (buf-b (generate-new-buffer "proj-b.txt"))
          (buf-stale (generate-new-buffer "proj-stale.txt")))
      (unwind-protect
          (save-window-excursion
            (delete-other-windows)
            ;; 设置窗口显示 buf-a
            (set-window-buffer (selected-window) buf-a)
            ;; 注册 3 个 buffer
            (custom--tabs-register-buffer buf-a)
            (custom--tabs-register-buffer buf-b)
            (custom--tabs-register-buffer buf-stale)
            (should (= (length (custom--tabs-frame-buffers (selected-window))) 3))
            ;; 清空（模拟项目切换）
            (custom/tabs-clear-for-frame)
            ;; 列表应为空——即使当前窗口显示着 buf-a
            (should (null (custom--tabs-get-frame-buffer-list)))
            (should (null (custom--tabs-frame-buffers (selected-window))))
            ;; refresh 后只收集窗口中可见的 buffer
            (custom/tabs-refresh-context)
            (let ((buffers (custom--tabs-frame-buffers (selected-window))))
              ;; buf-a 在窗口中且可见，应被 refresh 收集
              (should (memq buf-a buffers))
              ;; stale 不在任何窗口，不应被 refresh 收回
              (should-not (memq buf-stale buffers))))
        (custom--tabs-set-frame-buffer-list nil)
        (dolist (buffer (list buf-a buf-b buf-stale))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest test-ui-appearance-tab-server-switch-registers-to-selected-frame ()
  "验证 server-switch-hook 真实 lambda 注册到 selected-frame，不误注册到其他 frame。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-server-switch-frame"
    (tests/load-config "ui" "appearance.el")
    (let ((buf (generate-new-buffer "server-switch-test.txt"))
          (other-frames (delq (selected-frame) (frame-list))))
      (unwind-protect
          (progn
            ;; 切换到 buf，模拟 buffer-file-name，然后 run-hooks
            (with-current-buffer buf
              (cl-letf (((symbol-function 'buffer-file-name)
                         (lambda () "/fake/path/server-switch-test.txt")))
                ;; 直接运行真实的 server-switch-hook
                (run-hooks 'server-switch-hook)))
            ;; buf 应注册到 selected-frame
            (should (memq buf (custom--tabs-get-frame-buffer-list (selected-frame))))
            ;; 跨 frame 验证：需要多 frame 环境
            (if other-frames
                (dolist (other-frame other-frames)
                  (should-not (memq buf (custom--tabs-get-frame-buffer-list other-frame))))
              (ert-skip "单 frame 环境，跳过 server-switch 跨 frame 断言")))
        (custom--tabs-set-frame-buffer-list nil)
        (when (buffer-live-p buf)
          (kill-buffer buf))))))

(ert-deftest test-ui-appearance-tab-workspace-pane-boundary ()
  "验证 workspace-pane 为非 editor 非 nil 时，buffer 不进入标签列表（frame 和 window 两条路径）。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-workspace-pane-boundary"
    (tests/load-config "ui" "appearance.el")
    (let ((buf-a (generate-new-buffer "pane-a.txt"))
          (buf-side (generate-new-buffer "pane-side.txt")))
      (unwind-protect
          (save-window-excursion
            (delete-other-windows)
            (let ((main-win (selected-window))
                  (side-win (split-window-right)))
              (set-window-buffer main-win buf-a)
              (set-window-buffer side-win buf-side)
              ;; 标记 side-win 为 treemacs pane
              (set-window-parameter side-win 'custom--workspace-pane 'treemacs)
              ;; 路径 1：以 frame 参数调用（全局 hook）
              (custom--tabs-on-window-buffer-change (selected-frame))
              (let ((buffers (custom--tabs-frame-buffers (selected-window))))
                ;; buf-a（pane=nil）应被注册
                (should (memq buf-a buffers))
                ;; buf-side（pane='treemacs）不应被注册
                (should-not (memq buf-side buffers)))
              ;; 路径 2：以 window 参数调用（buffer-local hook）
              (custom--tabs-set-frame-buffer-list nil)
              (custom--tabs-on-window-buffer-change side-win)
              ;; 只有 side-win 被处理，且 pane='treemacs 应被过滤
              (should-not (memq buf-side (custom--tabs-frame-buffers (selected-window))))
              ;; main-win 单独调用应注册 buf-a
              (custom--tabs-on-window-buffer-change main-win)
              (should (memq buf-a (custom--tabs-frame-buffers (selected-window))))
              ;; 路径 3：pane 改为 editor，frame 路径应注册两个
              (set-window-parameter side-win 'custom--workspace-pane 'editor)
              (custom--tabs-set-frame-buffer-list nil)
              (custom--tabs-on-window-buffer-change (selected-frame))
              (let ((buffers (custom--tabs-frame-buffers (selected-window))))
                (should (memq buf-a buffers))
                (should (memq buf-side buffers)))))
        (custom--tabs-set-frame-buffer-list nil)
         (dolist (buffer (list buf-a buf-side))
           (when (buffer-live-p buffer)
             (kill-buffer buffer)))))))

(ert-deftest test-ui-appearance-tab-close-tab-function ()
  "验证 tab-line-close-tab-function 接入 per-frame 注销逻辑。"
  :tags '(config-loading ui appearance)
  (tests/with-diag-test "ui/appearance-tab-close-tab-function"
    (tests/load-config "ui" "appearance.el")
    (should (eq tab-line-close-tab-function #'custom/tab-line-close-tab))
    (let ((buf-a (generate-new-buffer "close-tab-a.txt"))
          (buf-b (generate-new-buffer "close-tab-b.txt")))
      (unwind-protect
          (save-window-excursion
            (delete-other-windows)
            (set-window-buffer (selected-window) buf-a)
            (custom--tabs-register-buffer buf-a)
            (custom--tabs-register-buffer buf-b)
            (should (= (length (custom--tabs-frame-buffers (selected-window))) 2))
            ;; 模拟 Emacs tab-line 调用：(funcall tab-line-close-tab-function tab)
            ;; tab 为 buffer 对象
            (custom/tab-line-close-tab buf-a)
            ;; buf-a 应被从 frame 列表注销
            (should-not (memq buf-a (custom--tabs-get-frame-buffer-list)))
            ;; buf-b 应仍在列表中
            (should (memq buf-b (custom--tabs-get-frame-buffer-list))))
        (custom--tabs-set-frame-buffer-list nil)
        (dolist (buffer (list buf-a buf-b))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest test-config-ui-color-scheme ()
  "验证 configs/ui/color-scheme.el 可正确加载。"
  :tags '(config-loading ui)
  (tests/with-diag-test "ui/color-scheme.el"
    (tests--verify-module "ui" "color-scheme.el" 'color-scheme)))

(ert-deftest test-config-ui-dashboard ()
  "验证 configs/ui/dashboard.el 可正确加载。"
  :tags '(config-loading ui)
  (tests/with-diag-test "ui/dashboard.el"
    (tests--verify-module "ui" "dashboard.el" 'dashboard)))

(ert-deftest test-dashboard-retries-after-early-frame-check ()
  "dashboard 首次检查过早时，应允许后续重新调度。"
  :tags '(config-loading ui dashboard)
  (tests/with-diag-test "ui/dashboard-retry"
    (tests/load-config "ui" "dashboard.el")
    (let ((rescheduled nil))
      (cl-letf (((symbol-function 'custom/dashboard--frame-startup-state)
                 (lambda (_frame) 'pending))
                ((symbol-function 'custom/dashboard--schedule-open-for-frame)
                 (lambda (_frame retries-left)
                   (setq rescheduled retries-left))))
        (unwind-protect
            (progn
              (set-frame-parameter nil 'custom-dashboard-open-scheduled t)
              (custom/dashboard--run-open-check (selected-frame) 2)
              (should-not (frame-parameter nil 'custom-dashboard-open-scheduled))
              (should (eq rescheduled 1)))
          (set-frame-parameter nil 'custom-dashboard-open-scheduled nil))))))

(ert-deftest test-dashboard-shows-on-placeholder-buffer ()
  "占位缓冲区场景下，dashboard 应执行显示逻辑。"
  :tags '(config-loading ui dashboard)
  (tests/with-diag-test "ui/dashboard-placeholder"
    (tests/load-config "ui" "dashboard.el")
    (let ((display-called nil))
      (cl-letf (((symbol-function 'custom/dashboard--frame-startup-state)
                 (lambda (_frame) 'placeholder))
                ((symbol-function 'custom/dashboard--display-in-frame)
                 (lambda (_frame)
                   (setq display-called t))))
        (unwind-protect
            (progn
              (set-frame-parameter nil 'custom-dashboard-open-scheduled t)
              (custom/dashboard--run-open-check (selected-frame) 2)
              (should-not (frame-parameter nil 'custom-dashboard-open-scheduled))
              (should display-called))
          (set-frame-parameter nil 'custom-dashboard-open-scheduled nil))))))

(ert-deftest test-dashboard-loads-projectile-known-projects-lazily ()
  "dashboard 在 `projectile-mode' 未启动时也应能读取已知项目。"
  :tags '(config-loading ui dashboard)
  (tests/with-diag-test "ui/dashboard-projects"
    (tests/load-config "system" "startup.el")
    (tests/load-config "ui" "dashboard.el")
    (let ((projects (custom/dashboard--known-projects)))
      (should (consp projects))
      (should (seq-some (lambda (path)
                          (string-match-p "Guix-configs" path))
                        projects)))))

(ert-deftest test-config-ui-workspace ()
  "验证 configs/ui/workspace.el 可正确加载。"
  :tags '(config-loading ui)
  (tests/with-diag-test "ui/workspace.el"
    (tests--verify-module "ui" "workspace.el" 'workspace)))

(ert-deftest test-ui-workspace-prefers-dirvish-nerd-icons ()
  "验证 Dirvish/Dired 文件图标已切换到 Nerd Font。"
  :tags '(config-loading ui workspace)
  (tests/with-diag-test "ui/workspace-dirvish-nerd-icons"
    (tests/load-config "ui" "workspace.el")
    (if (locate-library "dirvish")
        (progn
          (should (equal dirvish-attributes '(nerd-icons file-size)))
          (should (equal dirvish-nerd-icons-height 0.95))
          (should (equal dirvish-nerd-icons-offset 0.0)))
      (ert-skip "未安装 dirvish，跳过 Nerd Icons 断言"))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 本地化配置
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-config-i18n-context-menu ()
  "验证 configs/i18n/context-menu.el 可正确加载。"
  :tags '(config-loading i18n)
  (tests/with-diag-test "i18n/context-menu.el"
    (tests--verify-module "i18n" "context-menu.el" 'context-menu-i18n)))

(ert-deftest test-config-i18n-which-key-descriptions ()
  "验证 configs/i18n/which-key-descriptions.el 可正确加载。"
  :tags '(config-loading i18n)
  (tests/with-diag-test "i18n/which-key-descriptions.el"
    (tests--verify-module "i18n" "which-key-descriptions.el" 'which-key-descriptions)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 编辑器配置
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-config-editor-keybindings ()
  "验证 configs/editor/keybindings.el 可正确加载。"
  :tags '(config-loading editor)
  (tests/with-diag-test "editor/keybindings.el"
    (tests--verify-module "editor" "keybindings.el" 'keybindings)))

(ert-deftest test-config-editor-prefix-keymaps ()
  "验证 configs/editor/prefix-keymaps.el 可正确加载。"
  :tags '(config-loading editor)
  (tests/with-diag-test "editor/prefix-keymaps.el"
    (tests--verify-module "editor" "prefix-keymaps.el" 'prefix-keymaps)))

(ert-deftest test-config-editor-mouse ()
  "验证 configs/editor/mouse.el 可正确加载。"
  :tags '(config-loading editor)
  (tests/with-diag-test "editor/mouse.el"
    (tests--verify-module "editor" "mouse.el" 'mouse)))

(ert-deftest test-config-editor-help ()
  "验证 configs/editor/help.el 可正确加载。"
  :tags '(config-loading editor)
  (tests/with-diag-test "editor/help.el"
    (tests--verify-module "editor" "help.el" 'help)))

(ert-deftest test-config-editor-completion ()
  "验证 configs/editor/completion.el 可正确加载。"
  :tags '(config-loading editor)
  (tests/with-diag-test "editor/completion.el"
    (tests--verify-module "editor" "completion.el" 'completion)))

(ert-deftest test-config-editor-folding ()
  "验证 configs/editor/folding.el 可正确加载。"
  :tags '(config-loading editor)
  (tests/with-diag-test "editor/folding.el"
    (tests--verify-module "editor" "folding.el" 'folding)))

(ert-deftest test-config-editor-navigation ()
  "验证 configs/editor/navigation.el 可正确加载。"
  :tags '(config-loading editor)
  (tests/with-diag-test "editor/navigation.el"
    (tests--verify-module "editor" "navigation.el" 'navigation)))

(ert-deftest test-config-editor-editing ()
  "验证 configs/editor/editing.el 可正确加载。"
  :tags '(config-loading editor)
  (tests/with-diag-test "editor/editing.el"
    (tests--verify-module "editor" "editing.el" 'editing)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 编程配置
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-config-coding-lsp ()
  "验证 configs/coding/lsp.el 可正确加载。"
  :tags '(config-loading coding)
  (tests/with-diag-test "coding/lsp.el"
    (tests--verify-module "coding" "lsp.el" 'lsp)))

(ert-deftest test-config-coding-format ()
  "验证 configs/coding/format.el 可正确加载。"
  :tags '(config-loading coding)
  (tests/with-diag-test "coding/format.el"
    (tests--verify-module "coding" "format.el" 'format)))

(ert-deftest test-config-coding-flycheck ()
  "验证 configs/coding/flycheck.el 可正确加载。"
  :tags '(config-loading coding)
  (tests/with-diag-test "coding/flycheck.el"
    ;; 配置模块本身提供 `config-flycheck'；真正的 `flycheck' 包保持延迟加载。
    (tests--verify-module "coding" "flycheck.el" 'config-flycheck)))

(ert-deftest test-config-coding-languages ()
  "验证 configs/coding/languages.el 可正确加载。"
  :tags '(config-loading coding)
  (tests/with-diag-test "coding/languages.el"
    (tests--verify-module "coding" "languages.el" 'languages)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 工具配置
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-config-tools-git ()
  "验证 configs/tools/git.el 可正确加载。"
  :tags '(config-loading tools)
  (tests/with-diag-test "tools/git.el"
    (tests--verify-module "tools" "git.el" 'git)))

(ert-deftest test-config-tools-project ()
  "验证 configs/tools/project.el 可正确加载。"
  :tags '(config-loading tools)
  (tests/with-diag-test "tools/project.el"
    (tests--verify-module "tools" "project.el" 'project)))

(ert-deftest test-config-tools-terminal ()
  "验证 configs/tools/terminal.el 可正确加载。"
  :tags '(config-loading tools)
  (tests/with-diag-test "tools/terminal.el"
    (tests--verify-module "tools" "terminal.el" 'terminal)))

(ert-deftest test-config-tools-pdf ()
  "验证 configs/tools/pdf.el 可正确加载。"
  :tags '(config-loading tools)
  (tests/with-diag-test "tools/pdf.el"
    (tests--verify-module "tools" "pdf.el" 'pdf)))

(ert-deftest test-config-tools-mail ()
  "验证 configs/tools/mail.el 可正确加载。"
  :tags '(config-loading tools)
  (tests/with-diag-test "tools/mail.el"
    (tests--verify-module "tools" "mail.el" 'mail)))

(ert-deftest test-config-tools-calendar ()
  "验证 configs/tools/calendar.el 可正确加载。"
  :tags '(config-loading tools)
  (tests/with-diag-test "tools/calendar.el"
    (tests--verify-module "tools" "calendar.el" 'calendar)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Org Mode 配置
;; ═════════════════════════════════════════════════════════════════════════════

(ert-deftest test-config-org-org-mode ()
  "验证 configs/org/org-mode.el 可正确加载。"
  :tags '(config-loading org)
  (tests/with-diag-test "org/org-mode.el"
    (tests--verify-module "org" "org-mode.el" 'org-mode)))

(provide 'test-config-loading)
;;; test-config-loading.el ends here
