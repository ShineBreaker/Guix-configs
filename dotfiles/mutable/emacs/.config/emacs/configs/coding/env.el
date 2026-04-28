;;; env.el --- 项目环境传播（envrc + 自动 venv 检测） -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 将项目本地的环境变量（PATH、PYTHONPATH 等）传播到 Emacs 子进程，
;; 使 eglot / apheleia / flycheck 能找到项目虚拟环境中的工具。
;;
;; 设计原则：
;; - envrc（direnv）作为核心环境传播机制，buffer-local 级别隔离
;; - 无 .envrc 的 Python 项目通过自动 venv 检测作为 fallback
;; - 不引入 pyvenv，避免与 envrc 的状态管理冲突
;;
;; 工作流：
;; 1. 有 .envrc 的项目：envrc 自动加载，PATH/VIRTUAL_ENV 等按 buffer 隔离
;;    - `uv` 项目：.envrc 中 `source .venv/bin/activate` 或 `layout python`
;;    - `guix shell` 项目：.envrc 中 `source guix-shell-profile`
;;    - 修改 .envrc 后需 `direnv allow`（终端）或 `envrc-reload`（Emacs）
;; 2. 无 .envrc 的 Python 项目：自动检测 .venv/bin/python，设置 python-shell 变量
;; 3. Java 项目：自动检测 JAVA_HOME，通过 eglot-workspace-configuration 传递给 jdtls
;;
;; 环境传播链路：
;;   envrc → buffer-local exec-path/process-environment
;;         → make-process（eglot/apheleia/flycheck 底层）
;;         → 子进程继承正确的 PATH
;;
;; 依赖（需通过 Guix 安装）：
;; - emacs-envrc（direnv buffer-local 集成）
;; - direnv（系统级，通常已安装）
;;
;; Troubleshooting：
;; - LSP 找不到 pylsp → 检查 .envrc 是否 `direnv allow`，或 envrc-reload
;; - formatter 找不到 black → 同上，或确认 .venv/bin/black 存在
;; - envrc 不生效 → M-x envrc-reload，或检查 direnv status

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; envrc — direnv buffer-local 环境变量注入
;; ═════════════════════════════════════════════════════════════════════════════

(use-package envrc
  :defer 0.5
  :if (executable-find "direnv")
  :config
  (envrc-global-mode 1)
  (custom/diag "env" "envrc-global-mode 已启用 (direnv=%s)" (executable-find "direnv")))

;; ═════════════════════════════════════════════════════════════════════════════
;; Python 虚拟环境自动检测（无 .envrc 时的 fallback）
;; ═════════════════════════════════════════════════════════════════════════════

(defcustom custom/python-venv-names '(".venv" "venv" ".env")
  "Python 虚拟环境目录名称搜索列表（按优先级排列）。"
  :type '(repeat string)
  :group 'custom)

(defun custom/detect-python-venv (&optional dir)
  "从 DIR 向上搜索 Python 虚拟环境，返回 venv 根目录或 nil。
DIR 默认为 `default-directory'。搜索 `custom/python-venv-names' 中的目录名。"
  (let ((project-root (or dir default-directory)))
    (when-let ((venv-dir
                (seq-some
                 (lambda (name)
                   (let ((candidate (expand-file-name name project-root)))
                     (when (and (file-directory-p candidate)
                                (file-executable-p
                                 (expand-file-name "bin/python" candidate)))
                       candidate)))
                 custom/python-venv-names)))
      venv-dir)))

(defun custom/activate-python-venv-maybe ()
  "当当前 buffer 处于 Python 模式且项目有 venv 时，设置 python-shell 变量。
仅在 envrc 未激活（无 .envrc）时作为 fallback。不修改 exec-path，
因为 eglot/apheleia 通过 make-process 继承 buffer 环境。"
  (when (and (derived-mode-p 'python-base-mode 'python-ts-mode)
             (not (and (bound-and-true-p envrc-mode)
                       envrc--current-status
                       (eq envrc--current-status 'on)))
             (fboundp 'projectile-project-root))
    (when-let ((project-root (projectile-project-root))
               (venv-dir (custom/detect-python-venv project-root)))
      (let ((python-bin (expand-file-name "bin/python" venv-dir)))
        (unless (and (boundp 'python-shell-interpreter)
                     (string= python-shell-interpreter python-bin))
          (setq-local python-shell-interpreter python-bin)
          (setq-local python-shell-virtualenv-root venv-dir)
          (custom/diag "env" "Python venv 自动检测: %s" venv-dir))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Java 环境自动检测
;; ═════════════════════════════════════════════════════════════════════════════

;; 检测逻辑：
;; 1. 优先使用 envrc 传播的 JAVA_HOME（来自项目 .envrc）
;; 2. 其次检测 PATH 中的 java 可执行文件，推断 JAVA_HOME
;; 3. 推断结果通过 eglot-workspace-configuration 传递给 jdtls
;;
;; jdtls 本身也能自动定位 JDK，此功能主要辅助：
;; - 项目需要特定 JDK 版本时（通过 .envrc 设置 JAVA_HOME）
;; - jdtls 初始化时加速 SDK 路径发现

(defun custom/detect-java-home ()
  "自动检测 JAVA_HOME 路径。
优先级：环境变量 JAVA_HOME > 从 PATH 中的 java 推断 > nil。
返回 JAVA_HOME 路径字符串或 nil。

此函数被 lsp.el 中的 eglot-workspace-configuration 引用，
在 eglot 初始化时将 JAVA_HOME 传递给 jdtls。"
  (or (getenv "JAVA_HOME")
      (when-let ((java-bin (executable-find "java")))
        (let ((resolved (file-truename java-bin)))
          (when (string-match "\\(.*\\)/bin/java$" resolved)
            (let ((home (match-string 1 resolved)))
              (when (file-directory-p home)
                home)))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Hook 注册
;; ═════════════════════════════════════════════════════════════════════════════

;; 仅在 Python 模式下触发 venv 检测，避免对所有文件类型无差别搜索
(with-eval-after-load 'python
  (add-hook 'python-base-mode-hook #'custom/activate-python-venv-maybe))

;; projectile 切换项目后重新检测
(with-eval-after-load 'projectile
  (add-hook 'projectile-after-switch-project-hook
            (defun custom/venv-detect-after-project-switch ()
              "项目切换后对当前 buffer 重新检测 venv。"
              (when (derived-mode-p 'python-base-mode 'python-ts-mode)
                (custom/activate-python-venv-maybe)))))

(provide 'env)
;;; env.el ends here
