;; =============================================================================
;; 1. 性能优化 (Startup & IO)
;; =============================================================================

;; 临时提高垃圾回收阈值以加速启动，启动完成后恢复到合理值 (16MB)
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024)
                  gc-cons-percentage 0.1)))

;; 提升与外部进程通信时的读写吞吐量 (特别是对于 LSP/Eglot 极有帮助)
(setq read-process-output-max (* 3 1024 1024))

;; 禁用启动画面
(setq inhibit-startup-screen t
      initial-scratch-message nil)

;; =============================================================================
;; 2. 基础 UI 与交互
;; =============================================================================

(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

;; 行号与 Tab-bar
(global-display-line-numbers-mode 1)
(setq display-line-numbers-type 'relative)
(tab-bar-mode 1)
(setq tab-bar-show 1)

;; 鼠标与右键菜单支持 (xterm-mouse-mode 使得在终端下也能用鼠标)
(xterm-mouse-mode 1)
(context-menu-mode 1)

;; 加载自定义主题
(add-to-list 'custom-theme-load-path (expand-file-name "themes" user-emacs-directory))
(load-theme 'noctalia t)

;; =============================================================================
;; 3. 键绑定体系 (Evil)
;; =============================================================================

;; 必须在 Evil 加载前设置
(setq evil-want-keybinding nil
      evil-want-integration t)

(use-package evil
  :init
  (evil-mode 1))

(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

;; =============================================================================
;; 4. 现代补全前端 (类似 VSCode 的交互体验)
;; =============================================================================

(use-package vertico
  :init
  (vertico-mode 1))

(use-package marginalia
  :init
  (marginalia-mode 1))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

(use-package consult
  ;; 建议绑定一些常用的 consult 快捷键替代原生命令
  :bind (("C-x b" . consult-buffer)
         ("M-y"   . consult-yank-pop)
         ("M-s r" . consult-ripgrep)))

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)
         ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :after (embark consult))

(use-package which-key
  :init
  (which-key-mode 1))

;; Corfu: 代码补全弹出框 (替代 auto-complete/company)
(use-package corfu
  :custom
  (corfu-auto t)
  (corfu-auto-prefix 2)
  (corfu-quit-no-match 'separator)
  :init
  (global-corfu-mode 1))

;; =============================================================================
;; 5. 编程语言支持 (Tree-sitter, LSP, Scheme/Lisp)
;; =============================================================================

;; Tree-sitter: 替换原生 mode 为 ts-mode

(setq treesit-extra-load-path '("~/.guix-home/profile/lib/tree-sitter"))

(setq major-mode-remap-alist
      '((c-mode      . c-ts-mode)
        (c++-mode    . c++-ts-mode)
        (python-mode . python-ts-mode)
        (rust-mode   . rust-ts-mode)
        (java-mode   . java-ts-mode)))

;; Eglot: LSP 客户端
(use-package eglot
  :hook ((c-ts-mode . eglot-ensure)
         (c++-ts-mode . eglot-ensure)
         (python-ts-mode . eglot-ensure)
         (rust-ts-mode . eglot-ensure))
  :config
  ;; 注册 LSP 服务器
  (add-to-list 'eglot-server-programs '((c-ts-mode c++-ts-mode) . ("ccls")))
  (add-to-list 'eglot-server-programs '(python-ts-mode . ("pylsp")))
  (add-to-list 'eglot-server-programs '(rust-ts-mode . ("rust-analyzer"))))

;; Eglot 保存时自动格式化 (针对 Python 优化)
(defun my/eglot-format-buffer-on-save ()
  "仅在当前 buffer 开启了 eglot 管理时，才进行格式化。"
  (when (and (bound-and-true-p eglot--managed-mode)
             (derived-mode-p 'python-ts-mode 'python-mode))
    (add-hook 'before-save-hook #'eglot-format-buffer -10 t)))

(add-hook 'python-base-mode-hook #'my/eglot-format-buffer-on-save)

;; Lisp 家族
(use-package geiser
  :custom
  (geiser-active-implementations '(guile))
  :hook (scheme-mode . geiser-mode))

(use-package sly
  :custom
  (inferior-lisp-program "sbcl"))

;; =============================================================================
;; 6. 界面与布局工作流 (Dashboard, Treemacs & Vterm)
;; =============================================================================

(use-package dashboard
  :config
  (dashboard-setup-startup-hook)
  (setq dashboard-items '((recents   . 10)
                          (projects  . 5)
                          (bookmarks . 5))))

(use-package treemacs
  :bind ("C-c t" . treemacs)
  :custom
  (treemacs-width 28)
  (treemacs-position 'left)
  ;; 启用项目跟踪
  (treemacs-project-follow-mode t)           ;; 自动跟随当前项目
  (treemacs-follow-mode t)
  (treemacs-git-mode 'simple))

;; VSCode 布局一键触发
(defun my/vscode-layout ()
  "强制重置为 VSCode 布局：左树、右码、底终端。避免重复创建 vterm。"
  (interactive)

  ;; 获取当前项目目录
  (let* ((project-root
          (or (and (fboundp 'projectile-project-root)
                   (projectile-project-root))
              (and (fboundp 'project-current)
                   (project-current)
                   (project-root (project-current)))
              (and buffer-file-name
                   (file-name-directory buffer-file-name))
              default-directory))
         (windows (window-list))
         (code-window nil)
         (terminal-height 12)
         ;; 检查是否已存在 vterm 窗口
         (existing-vterm-window
          (catch 'found
            (dolist (win windows)
              (with-selected-window win
                (when (eq major-mode 'vterm-mode)
                  (throw 'found win))))
            nil)))

    ;; 1. 确保 Treemacs 开启并切换到当前项目
    (if (and (fboundp 'treemacs-is-visible) (treemacs-is-visible))
        (treemacs-add-and-display-current-project-exclusively)
      (progn
        (treemacs)))

    ;; 2. 找到代码区窗口
    (dolist (win windows)
      (with-selected-window win
        (when (and (not (eq major-mode 'treemacs-mode))
                   (not (eq major-mode 'vterm-mode))
                   (not (string-match-p "\\*vterm\\*" (buffer-name))))
          (setq code-window win))))

    (unless code-window
      (if (eq major-mode 'treemacs-mode)
          (progn
            (split-window-right treemacs-width)
            (setq code-window (next-window)))
        (setq code-window (selected-window))))

    (select-window code-window)

    ;; 3. 只在不存在 vterm 时才创建新的
    (unless existing-vterm-window
      (when (> (window-height) (+ terminal-height 5))
        (split-window-below (- (window-height) terminal-height))
        (other-window 1)
        (let ((default-directory project-root))
          (condition-case nil
              (vterm (generate-new-buffer-name "*vterm*"))
            (error
             (condition-case nil
                 (ansi-term (getenv "SHELL"))
               (error (shell))))))
        (other-window -1)))))

(add-hook 'emacs-startup-hook #'my/vscode-layout)

(global-set-key (kbd "<f9>") #'my/vscode-layout)

(message "配置文件加载完成。")
