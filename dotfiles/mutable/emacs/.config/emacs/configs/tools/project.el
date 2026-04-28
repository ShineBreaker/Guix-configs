;;; project.el --- 项目管理 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 Projectile 项目管理工具。
;;
;; 功能：
;; - 自动识别包含 .git、.projectile 等标记的目录为项目根
;; - 项目内文件搜索、grep、替换等操作
;; - consult-projectile: 通过 Consult 界面统一搜索项目文件/缓冲区
;; - 项目前缀：`C-x p`
;;
;; 快捷键：
;; - `C-x p p` — consult-projectile 项目文件搜索
;;
;; 性能优化：Projectile 采用延迟加载，通过 `:commands` 和 `:defer t` 确保
;; 仅在执行项目相关操作或打开项目文件时才初始化。
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; 诊断工具
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/diagnose-project-dir ()
  "诊断当前项目/目录状态，输出到 *Messages* 缓冲区。"
  (interactive)
  (let ((code-win (when (fboundp 'custom--find-editor-window)
                    (custom--find-editor-window))))
    (message "═══ [诊断] 项目目录状态 ═══")
    (message "  当前缓冲区: %s" (buffer-name (current-buffer)))
    (message "  当前缓冲区 default-directory: %s" default-directory)
    (message "  当前缓冲区 buffer-file-name: %s" (or buffer-file-name "(nil)"))
    (message "  projectile-project-root: %s"
             (or (and (fboundp 'projectile-project-root)
                      (projectile-project-root))
                 "(projectile 未就绪)"))
    (when (window-live-p code-win)
      (message "  代码窗口: %s" code-win)
      (message "  代码窗口缓冲区: %s" (buffer-name (window-buffer code-win)))
      (message "  代码窗口 default-directory: %s"
               (buffer-local-value 'default-directory (window-buffer code-win))))
    (when (fboundp 'projectile-project-p)
      (message "  projectile-project-p: %s" (projectile-project-p)))
    (message "═══ [诊断] 结束 ═══")))

;; ═════════════════════════════════════════════════════════════════════════════
;; Treemacs 导航
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--treemacs-local-window (&optional frame)
  "返回 FRAME 中的 Treemacs 窗口；若不存在则返回 nil。"
  (let ((target-frame (or frame (selected-frame))))
    (cond
     ((fboundp 'treemacs-get-local-window)
      (with-selected-frame target-frame
        (treemacs-get-local-window)))
     ((and (fboundp 'treemacs-get-local-buffer)
           (with-selected-frame target-frame
             (buffer-live-p (treemacs-get-local-buffer))))
      (with-selected-frame target-frame
        (get-buffer-window (treemacs-get-local-buffer) target-frame))))))

(defun custom--treemacs-normalize-path (path)
  "规范化 PATH 并返回目录风格路径。"
  (file-name-as-directory
   (expand-file-name path)))

(defun custom--treemacs-frame-workspace (&optional frame)
  "返回 FRAME 专属的 Treemacs workspace。"
  (let* ((target-frame (or frame (selected-frame)))
         (workspace (frame-parameter target-frame 'custom--treemacs-workspace)))
    (unless workspace
      (setq workspace
            (treemacs-workspace->create!
             :name (format "Frame::%s"
                           (or (frame-parameter target-frame 'name)
                               "unnamed"))
             :projects nil))
      (set-frame-parameter target-frame 'custom--treemacs-workspace workspace))
    workspace))

(defun custom--treemacs-activate-workspace (workspace)
  "将 WORKSPACE 设为当前 Treemacs workspace。

使用 gv-define-setter 公共 API。使用 `eval' 延迟 setf 宏展开到运行时，
避免 load 时即时编译将 setf 展开为对尚未加载函数的直接调用。"
  (condition-case err
      ;; eval 阻止编译期 setf 宏展开：load 时即时编译会将
      ;; (setf (treemacs-current-workspace) x) 编译为对函数
      ;; (setf treemacs-current-workspace) 的直接调用，但该
      ;; gv setter 在 treemacs-workspaces.el 加载后才注册。
      (eval `(setf (treemacs-current-workspace) ,workspace) t)
    (error
     (message "[treemacs] activate-workspace 失败: %s"
              (error-message-string err)))))

(defun custom--treemacs-current-root (&optional frame)
  "返回 FRAME 当前 Treemacs 根目录；若不存在则返回 nil。"
  (let ((target-frame (or frame (selected-frame))))
    (with-selected-frame target-frame
      (let* ((workspace (or (frame-parameter target-frame 'custom--treemacs-workspace)
                            (ignore-errors (treemacs-current-workspace))))
             (project (and workspace
                           (car (treemacs-workspace->projects workspace))))
             (path (and project
                        (ignore-errors (treemacs-project->path project)))))
        (when path
          (custom--treemacs-normalize-path path))))))

(defun custom--treemacs-nav-timer (&optional frame)
  "返回 FRAME 上待执行的 Treemacs 导航 timer。"
  (frame-parameter (or frame (selected-frame)) 'custom--treemacs-nav-timer))

(defun custom--treemacs-set-nav-timer (timer &optional frame)
  "记录 FRAME 当前的 Treemacs 导航 TIMER。"
  (set-frame-parameter (or frame (selected-frame))
                       'custom--treemacs-nav-timer timer))

(defun custom--treemacs-cancel-nav-timer (&optional frame)
  "取消 FRAME 上残留的 Treemacs 导航 timer。"
  (when-let ((timer (custom--treemacs-nav-timer frame)))
    (cancel-timer timer)
    (custom--treemacs-set-nav-timer nil frame)))

(defun custom--treemacs-reveal-path (path &optional frame)
  "在 FRAME 的 Treemacs 窗口中定位 PATH。
使用 `save-selected-window` 保持当前用户窗口不变，避免在错误上下文里
直接调用 `treemacs-find-file`。"
  (when path
    (when-let ((treemacs-win (custom--treemacs-local-window frame)))
      (let* ((expanded-path (expand-file-name path))
             (target-path (if (file-directory-p expanded-path)
                              (directory-file-name expanded-path)
                            expanded-path)))
        (save-selected-window
          (with-selected-window treemacs-win
            (ignore-errors
              (cond
               ((fboundp 'treemacs-goto-file-node)
                (treemacs-goto-file-node target-path))
               ((and (not (file-directory-p expanded-path))
                     (fboundp 'treemacs-find-file))
                (treemacs-find-file target-path))))))))))

(defun custom--treemacs-render-root (dir &optional frame)
  "在 FRAME 的 Treemacs 中将 DIR 渲染为唯一根目录。"
  (let* ((target-frame (or frame (selected-frame)))
         (target-dir (directory-file-name (expand-file-name dir))))
    (with-selected-frame target-frame
      ;; 确保 treemacs 及其子模块（scope、workspaces）已完全加载。
      ;; treemacs.el 依次 require treemacs-scope + treemacs-workspaces。
      (require 'treemacs nil t)
      (unless (custom--treemacs-local-window target-frame)
        ;; 隔离 (treemacs) 的初始化错误（如 GUI frame 未就绪），
        ;; 避免 treemacs 自身初始化问题中断 workspace 设置
        (condition-case err
            (treemacs)
          (error
           (message "[treemacs] 创建窗口失败: %s" (error-message-string err)))))
      (condition-case err
          (when-let ((treemacs-win (custom--treemacs-local-window target-frame)))
            (let* ((workspace (custom--treemacs-frame-workspace target-frame))
                   (project-name (file-name-nondirectory target-dir)))
              (custom--treemacs-activate-workspace workspace)
              ;; eval 阻止编译期 setf 宏展开，原因同 activate-workspace
              (eval `(setf (treemacs-workspace->projects ,workspace)
                           (list (treemacs-project->create!
                                  :name ,(if (string-empty-p project-name) target-dir project-name)
                                  :path ,target-dir
                                  :path-status (treemacs--get-path-status ,target-dir))))
                    t)
              (when-let ((treemacs-buffer (treemacs-get-local-buffer)))
                (with-current-buffer treemacs-buffer
                  (treemacs--consolidate-projects)))
              (with-selected-window treemacs-win
                (goto-char (point-min))
                (when-let ((btn (treemacs-current-button)))
                  (unless (treemacs-is-node-expanded? btn)
                    (treemacs--expand-root-node btn))))))
        (error
         (message "[treemacs] 渲染根目录失败: %s" (error-message-string err)))))))

(defun custom--treemacs-navigate-to-now (dir &optional _is-project reveal-path)
  "在当前 frame 的 Treemacs 中导航到 DIR。
REVEAL-PATH 非 nil 时，在导航完成后额外定位该文件/目录。"
  (let* ((target-frame (selected-frame))
         (target-dir (custom--treemacs-normalize-path dir))
         (current-root (custom--treemacs-current-root target-frame))
         (same-root (and current-root
                         (string= current-root target-dir))))
    (if same-root
        ;; 同一根目录下仅在有明确文件/子目录目标时才做 reveal。
        ;; 若当前上下文只是根目录本身（例如 dired 打开 plain/），再次 reveal 根目录
        ;; 会导致已展开的子节点被重新折叠。
        (when reveal-path
          (custom--treemacs-reveal-path reveal-path target-frame))
      (custom--treemacs-render-root target-dir target-frame)
      (custom/diag "treemacs" "切换 Treemacs 根目录: %s" target-dir)
      (when reveal-path
        (custom--treemacs-reveal-path reveal-path target-frame)))))

(defun custom--projectile-sync-timer (&optional frame)
  "返回 FRAME 上待执行的项目切换同步 timer。"
  (frame-parameter (or frame (selected-frame)) 'custom--projectile-sync-timer))

(defun custom--projectile-set-sync-timer (timer &optional frame)
  "记录 FRAME 上当前项目切换同步 TIMER。"
  (set-frame-parameter (or frame (selected-frame))
                       'custom--projectile-sync-timer timer))

(defun custom--projectile-cancel-sync-timer (&optional frame)
  "取消 FRAME 上残留的项目切换同步 timer。"
  (when-let ((timer (custom--projectile-sync-timer frame)))
    (cancel-timer timer)
    (custom--projectile-set-sync-timer nil frame)))

(defun custom--projectile-workspace-target-buffer (project-root)
  "为 PROJECT-ROOT 选择稳定的工作区目标 buffer。"
  (or (when (and (fboundp 'custom--workspace-editor-buffer-p)
                 (custom--workspace-editor-buffer-p (current-buffer)))
        (current-buffer))
      (when (fboundp 'custom--find-editor-window)
        (when-let ((editor-win (custom--find-editor-window))
                   (editor-buffer (window-buffer editor-win)))
          (when (and (fboundp 'custom--workspace-editor-buffer-p)
                     (custom--workspace-editor-buffer-p editor-buffer))
            editor-buffer)))
      (ignore-errors (dired-noselect project-root))))

(defun custom--projectile-sync-workspace-now (frame project-root target-buffer)
  "在 FRAME 中将工作区同步到 PROJECT-ROOT，必要时显示 TARGET-BUFFER。"
  (when (frame-live-p frame)
    (with-selected-frame frame
      (setq default-directory (file-name-as-directory project-root))
      (when (fboundp 'custom/ensure-workspace-layout)
        (custom/ensure-workspace-layout target-buffer project-root)))))

(defun custom--projectile-schedule-workspace-sync (project-root target-buffer &optional reveal-in-treemacs)
  "为空闲时同步 PROJECT-ROOT 的工作区状态。
TARGET-BUFFER 用于编辑区显示；REVEAL-IN-TREEMACS 非 nil 时额外同步 Treemacs。"
  (let ((target-frame (selected-frame)))
    (setq default-directory (file-name-as-directory project-root))
    (custom--projectile-cancel-sync-timer target-frame)
    (custom--projectile-set-sync-timer
     (run-with-idle-timer
     0.15 nil
     (lambda (frame dir buffer reveal-p)
       (custom--projectile-set-sync-timer nil frame)
       (custom--projectile-sync-workspace-now frame dir buffer)
        (when reveal-p
          (ignore-errors
            (custom/treemacs-navigate-to
             dir t
             (and (buffer-live-p buffer)
                  (with-current-buffer buffer
                    (or buffer-file-name default-directory)))))))
      target-frame project-root target-buffer reveal-in-treemacs)
     target-frame)))

(defun custom--projectile-known-projects ()
  "返回当前可用的 Projectile 项目列表。"
  (delete-dups
   (seq-filter #'file-directory-p
               (mapcar #'file-name-as-directory projectile-known-projects))))

(defun custom/switch-project ()
  "使用 Projectile 项目列表切换项目，并走稳定的工作区同步流程。

不同于 `projectile-switch-project'，该命令不会在 daemon/client 场景中
触发交互式 `projectile-find-file'，而是直接打开项目目录并同步工作区。"
  (interactive)
  (require 'projectile)
  (unless (boundp 'projectile-known-projects)
    (user-error "Projectile 尚未初始化"))
  (let* ((projects (custom--projectile-known-projects))
         (project-root (completing-read "切换到项目: " projects nil t nil nil
                                        (car projects))))
    (unless (and project-root (not (string-empty-p project-root)))
      (user-error "未选择项目"))
    (setq project-root (file-name-as-directory (expand-file-name project-root)))
    (unless (file-directory-p project-root)
      (user-error "项目目录不存在: %s" project-root))
    (projectile-add-known-project project-root)
    (custom--projectile-schedule-workspace-sync
     project-root
     (ignore-errors (dired-noselect project-root))
     t)))

(defun custom/treemacs-navigate-to (dir &optional is-project reveal-path)
  "在空闲时于当前 frame 的 Treemacs 中导航到 DIR。
通过 idle timer 推迟实际导航，避免在 `emacsclient`/workspace 同步过程中
同步操作 Treemacs 导致命令循环阻塞或错误进入读取路径提示。"
  (let ((target-frame (selected-frame)))
    (custom--treemacs-cancel-nav-timer target-frame)
    (custom--treemacs-set-nav-timer
    (run-with-idle-timer
     0.05 nil
     (lambda (frame target-dir project-p target-path)
       (when (frame-live-p frame)
         (custom--treemacs-set-nav-timer nil frame)
         (with-selected-frame frame
           (custom--treemacs-navigate-to-now target-dir project-p target-path))))
     target-frame dir is-project reveal-path)
    target-frame)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Projectile 配置
;; ═════════════════════════════════════════════════════════════════════════════

(use-package projectile
  :defer t
  :commands (projectile-switch-project
             projectile-find-file
             projectile-project-p
             projectile-project-root
             projectile-add-known-project
             projectile-known-projects
             projectile-cache-current-file
             projectile-kill-buffers)
  :custom
  (projectile-mode-line '(:eval (format " [%s]" (projectile-project-name))))
  (projectile-completion-system 'default)
  (projectile-enable-caching t)
  :config
  (projectile-mode 1)

  (defun custom/projectile-sync-workspace-after-switch ()
    "在切换项目后同步工作区各区域到当前项目目录。"
    (when-let* ((project-root (ignore-errors (projectile-project-root))))
      (custom--projectile-schedule-workspace-sync
       project-root
       (custom--projectile-workspace-target-buffer project-root)
       nil)))

  (add-hook 'projectile-after-switch-project-hook
            #'custom/projectile-sync-workspace-after-switch)

  ;; ═════════════════════════════════════════════════════════════════════════
  ;; 手动打开项目文件夹
  ;; ═════════════════════════════════════════════════════════════════════════

  (defun custom/open-project-folder ()
    "打开任意文件夹：设置工作目录并显示工作区布局。

Treemacs 行为：
- 目录含 .git → 添加为项目，独占显示
- 目录无 .git → 仅导航到该目录路径"
    (interactive)
    (require 'projectile)
    (let ((dir (read-directory-name "项目目录: ")))
      (when (file-directory-p dir)
        (setq dir (file-name-as-directory dir))
        (setq default-directory dir)
        (let ((is-git (file-directory-p (expand-file-name ".git" dir)))
              (target-buffer (ignore-errors (dired-noselect dir))))
          (when is-git
            (projectile-add-known-project dir))
          (custom--projectile-schedule-workspace-sync dir target-buffer is-git))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Treemacs + Projectile 集成
;; ═════════════════════════════════════════════════════════════════════════════

(use-package treemacs-projectile
  :after (treemacs projectile)
  :defer t)

;; ═════════════════════════════════════════════════════════════════════════════
;; Consult-projectile - 统一项目搜索
;; ═════════════════════════════════════════════════════════════════════════════

;; 通过 Consult 界面搜索项目文件、缓冲区和 recentf
(use-package consult-projectile
  :after (consult projectile)
  :defer t
  :commands (consult-projectile consult-projectile-find-file
             consult-projectile-switch-project)
  :bind (("C-x p p" . consult-projectile)))

(provide 'project)
;;; project.el ends here
