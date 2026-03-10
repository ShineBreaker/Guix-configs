;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; core-ai.el --- AI Agent 面板与工作流配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 目标：尽量复刻 Zed/Cline 风格体验。
;; 1) 使用 ellama + llm（Guix 管理）
;; 2) 默认接入 zed.json 中的 OpenAI-compatible Aliyun URL
;; 3) 将 AI 会话固定在右侧边栏
;; 4) 提供代码问答/改写/补全的快捷入口

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'button)
(require 'llm-openai)
(declare-function vterm "vterm")
(declare-function vterm-send-string "vterm")
(declare-function vterm-send-return "vterm")
(declare-function ellama-new-session "ellama")
(declare-function ellama-get-session-buffer "ellama")
(declare-function ellama-session-id "ellama")

(defgroup my/ai nil
  "个人 AI Agent 配置。"
  :group 'tools)

(defcustom my/ai-openai-compatible-url "https://coding.dashscope.aliyuncs.com/v1"
  "OpenAI-compatible 接口地址（来自 zed.json）。"
  :type 'string
  :group 'my/ai)

(defcustom my/ai-model "glm-5"
  "默认聊天模型（可切换为 qwen3-coder-next 等）。"
  :type 'string
  :group 'my/ai)

(defcustom my/ai-api-key-env-vars
  '("OPENAI_API_KEY" "DASHSCOPE_API_KEY" "ALIYUN_API_KEY")
  "按顺序尝试读取 API Key 的环境变量名。"
  :type '(repeat string)
  :group 'my/ai)

(defcustom my/ai-side-window-width 30
  "右侧 AI 面板宽度；默认 30 列，与左侧 Treemacs 一致。"
  :type '(choice float integer)
  :group 'my/ai)

(defcustom my/ai-show-usage-on-empty-panel t
  "当 AI 面板为空时，是否自动插入使用指南。"
  :type 'boolean
  :group 'my/ai)

(defcustom my/ai-suppress-llm-nonfree-warning t
  "是否关闭 llm 的非自由服务提示，避免弹出 *Warnings* 窗口。"
  :type 'boolean
  :group 'my/ai)

(defvar llm-warn-on-nonfree)

(defun my/ai-apply-warning-policy ()
  "应用 llm 告警策略，避免多余 *Warnings* 弹窗。"
  (when (and my/ai-suppress-llm-nonfree-warning
             (boundp 'llm-warn-on-nonfree))
    (setq llm-warn-on-nonfree nil)))

;; 模块加载时先应用一次，防止会话首个请求就弹 warning。
(my/ai-apply-warning-policy)

(defcustom my/ai-use-gnome-keyring t
  "是否优先从 GNOME Keyring（secret-tool）读取 API Key。"
  :type 'boolean
  :group 'my/ai)

(defcustom my/ai-keyring-lookup-attrs
  '(("service" . "emacs-ai")
    ("provider" . "dashscope"))
  "secret-tool 查询 API Key 使用的属性。"
  :type '(alist :key-type string :value-type string)
  :group 'my/ai)

(defun my/ai-read-api-key-from-keyring ()
  "从 GNOME Keyring 读取 API Key。"
  (when (and my/ai-use-gnome-keyring
             (executable-find "secret-tool"))
    (let* ((attrs (apply #'append
                         (mapcar (lambda (kv) (list (car kv) (cdr kv)))
                                 my/ai-keyring-lookup-attrs)))
           (lines (ignore-errors
                    (apply #'process-lines "secret-tool" "lookup" attrs))))
      (when-let ((raw (car lines)))
        (let ((val (string-trim raw)))
          (unless (string-empty-p val) val))))))

(defun my/ai-read-api-key ()
  "按优先级读取 API Key：GNOME Keyring -> 环境变量。"
  (or (my/ai-read-api-key-from-keyring)
      (seq-some (lambda (name)
                  (let ((v (getenv name)))
                    (when (and v (not (string-empty-p v))) v)))
                my/ai-api-key-env-vars)))

(defun my/ai-build-provider ()
  "构建 OpenAI-compatible provider；缺少 key 时返回 nil。"
  (when-let ((key (my/ai-read-api-key)))
    (make-llm-openai-compatible
     :url my/ai-openai-compatible-url
     :key key
     :chat-model my/ai-model)))

(defun my/ai-configure-provider (&optional quiet)
  "根据当前 key 来源更新 `ellama-provider'。QUIET 非空时不提示失败信息。"
  (my/ai-apply-warning-policy)
  (if-let ((provider (my/ai-build-provider)))
      (progn
        (setq ellama-provider provider
              ellama-providers `(("Aliyun" . ,provider)))
        t)
    (unless quiet
      (message "[AI] 未检测到 API Key。可用 secret-tool store service emacs-ai provider dashscope"))
    nil))

(defun my/ai-ellama-buffer-p (buffer _action)
  "判断 BUFFER 是否为 ellama 会话 buffer。"
  (with-current-buffer buffer
    (derived-mode-p 'ellama-session-mode)))

(defun my/ai-buffer-p (&optional buffer)
  "判断 BUFFER 是否属于 AI 侧栏相关缓冲区。"
  (with-current-buffer (or buffer (current-buffer))
    (or (derived-mode-p 'ellama-session-mode
                        'my/ai-guide-mode
                        'my/ai-unavailable-mode)
        (string-prefix-p "ellama " (buffer-name))
        (string-prefix-p "*AI-" (buffer-name)))))

(defun my/ai-prepare-buffer-layout ()
  "统一 AI 面板缓冲区：关闭行号并开启自动换行。"
  (when (my/ai-buffer-p)
    (setq-local display-line-numbers nil)
    (setq-local truncate-lines nil)
    (setq-local word-wrap t)
    (visual-line-mode 1)
    (dolist (win (get-buffer-window-list (current-buffer) nil t))
      (my/ai-prepare-window-layout win))))

(defun my/ai-prepare-window-layout (&optional window)
  "统一 AI 面板 WINDOW 的边距；帮助类面板使用居中排版。"
  (let ((win (or window (selected-window))))
    (when (window-live-p win)
      (set-window-fringes win 0 0 t)
      (with-current-buffer (window-buffer win)
        (if (derived-mode-p 'my/ai-guide-mode 'my/ai-unavailable-mode)
            (let* ((content-width
                    (max 1
                         (save-excursion
                           (goto-char (point-min))
                           (let ((mx 1))
                             (while (not (eobp))
                               (setq mx
                                     (max mx
                                          (string-width
                                           (buffer-substring-no-properties
                                            (line-beginning-position)
                                            (line-end-position)))))
                               (forward-line 1))
                             mx))))
                   (win-width (window-body-width win))
                   (spare (max 0 (- win-width content-width)))
                   (left (/ spare 2))
                   (right (- spare left)))
              (set-window-margins win left right))
          ;; 聊天面板保持紧凑排版，不留左侧空列。
          (set-window-margins win 0 0))))))

(defun my/ai-recenter-info-panels (_frame)
  "窗口尺寸变化后，重算 AI 帮助类面板的居中。"
  (dolist (win (window-list nil 'nomini))
    (with-current-buffer (window-buffer win)
      (when (derived-mode-p 'my/ai-guide-mode 'my/ai-unavailable-mode)
        (my/ai-prepare-window-layout win)))))

(defun my/ai-display-side-buffer (buffer)
  "将 BUFFER 稳定显示在右侧 AI 面板。"
  (with-current-buffer buffer
    (my/ai-prepare-buffer-layout))
  (let ((win (display-buffer buffer
                             `((display-buffer-in-side-window)
                               (side . right)
                               (slot . 2)
                               (window-width . ,my/ai-side-window-width)
                               (window-parameters . ((no-delete-other-windows . t)
                                                     (no-other-window . nil)))))))
    (my/ai-prepare-window-layout win))
  buffer)

(define-derived-mode my/ai-guide-mode special-mode "AI-Guide"
  "AI 使用指南模式。")

(defun my/ai-start-chat-session ()
  "创建或打开一个 ellama 会话并显示到右侧。"
  (interactive)
  (if-let ((buf (my/ai--find-chat-buffer)))
      (my/ai-display-side-buffer buf)
    (require 'ellama)
    (let* ((session (ellama-new-session ellama-provider "Panel" t))
           (buf (ellama-get-session-buffer (ellama-session-id session))))
      (my/ai-display-side-buffer buf))))

(defun my/ai-open-guide-panel ()
  "在右侧显示 AI 使用指南面板。"
  (interactive)
  (let ((buf (get-buffer-create "*AI-Guide*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/ai-guide-mode)
        (insert "AI Agent 使用指南\n\n")
        (insert "快捷键:\n")
        (insert "  C-c a a:\n")
        (insert "    打开/聚焦 AI 面板\n")
        (insert "  C-c a q:\n")
        (insert "    询问当前选区\n")
        (insert "    (无选区则整个文件)\n")
        (insert "  C-c a e:\n")
        (insert "    按要求改写代码\n")
        (insert "  C-c a i:\n")
        (insert "    补写代码\n")
        (insert "  C-c a c:\n")
        (insert "    直接发起问答\n\n")
        (insert "建议流程：选中代码\n")
        (insert "             ↓\n")
        (insert "          C-c a q\n")
        (insert "             ↓\n")
        (insert "        根据结果再用\n")
        (insert "      C-c a e 细化修改。\n\n")
        (insert-button "[开始 AI 会话]"
                       'action (lambda (_btn) (my/ai-start-chat-session))
                       'follow-link t)
        (insert "\n")
        (insert-button "[关闭这个区域]"
                       'action (lambda (_btn)
                                 (when-let ((win (get-buffer-window buf)))
                                   (delete-window win)))
                       'follow-link t)
        (insert "\n\n按键：n=开始会话, q=关闭区域\n")
        (goto-char (point-min)))
      (local-set-key (kbd "n") #'my/ai-start-chat-session)
      (local-set-key (kbd "q")
                     (lambda ()
                       (interactive)
                       (when-let ((win (get-buffer-window buf)))
                         (delete-window win)))))
    (my/ai-display-side-buffer buf)))

(use-package ellama
  :commands (ellama-chat ellama-ask-about ellama-code-add ellama-code-edit)
  :config
  ;; 避免回答时因为 llm 非自由提示弹出额外 *Warnings* 窗口。
  (my/ai-apply-warning-policy)

  ;; 把 ellama 会话统一放到右侧，形成固定 Agent 栏。
  (add-to-list 'display-buffer-alist
               `(my/ai-ellama-buffer-p
                 (display-buffer-in-side-window)
                 (side . right)
                 (slot . 2)
                 (window-width . ,my/ai-side-window-width)
                 (window-parameters . ((no-delete-other-windows . t)
                                       (no-other-window . nil)))))

  ;; 默认语言偏好与会话命名风格。
  (setq ellama-language "Chinese"
        ellama-user-nick "You"
        ellama-assistant-nick "Agent")

  ;; AI 会话区统一 UI：无行号 + 自动换行。
  (add-hook 'ellama-session-mode-hook #'my/ai-prepare-buffer-layout)
  (add-hook 'org-mode-hook
            (lambda ()
              (when (my/ai-buffer-p)
                (my/ai-prepare-buffer-layout))))

  ;; 映射 zed.json 的 openai_compatible(Aliyun) 配置。
  (my/ai-configure-provider))

(defun my/ai--find-chat-buffer ()
  "查找已有 ellama 会话 buffer。"
  (seq-find (lambda (buf)
              (with-current-buffer buf
                (derived-mode-p 'ellama-session-mode)))
            (buffer-list)))

(defun my/ai-open-panel ()
  "打开右侧 AI Agent 面板；若无会话则新建会话。"
  (interactive)
  (my/ai-apply-warning-policy)
  ;; 每次打开面板前都重试绑定 provider，避免启动时 keyring 尚不可用导致卡死在回退逻辑。
  (unless (and (boundp 'ellama-provider) ellama-provider)
    (my/ai-configure-provider t))
  (if (and (boundp 'ellama-provider) ellama-provider)
      (if-let ((buf (my/ai--find-chat-buffer)))
          (my/ai-display-side-buffer buf)
        (if my/ai-show-usage-on-empty-panel
            (my/ai-open-guide-panel)
          (my/ai-start-chat-session)))
    (my/ai-open-unavailable-panel)))

(defun my/ai-unavailable-close-panel ()
  "关闭当前 AI 侧栏窗口。"
  (interactive)
  (when-let ((win (get-buffer-window "*AI-Agent-Unavailable*")))
    (delete-window win)))

(defun my/ai-unavailable-open-terminal ()
  "在 AI 侧栏打开普通终端（不自动运行 codex）。"
  (interactive)
  (let ((buf (if (fboundp 'vterm)
                 (vterm "*AI-Terminal*")
               (get-buffer-create "*AI-Terminal*"))))
    (with-current-buffer buf
      (unless (derived-mode-p 'vterm-mode)
        (shell buf)))
    (display-buffer buf
                    `((display-buffer-in-side-window)
                      (side . right)
                      (slot . 2)
                      (window-width . ,my/ai-side-window-width)))))

(define-derived-mode my/ai-unavailable-mode special-mode "AI-Unavailable"
  "AI 不可用时的引导面板模式。")

(defun my/ai-open-unavailable-panel ()
  "当 AI provider 不可用时，显示可选操作面板。"
  (interactive)
  (let ((buf (get-buffer-create "*AI-Agent-Unavailable*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/ai-unavailable-mode)
        (insert "AI Agent 当前不可用\n\n")
        (insert "原因：未读取到可用 API Key（GNOME Keyring/环境变量）。\n\n")
        (insert "如何添加 Key（GNOME Keyring）：\n")
        (insert "  secret-tool store --label=\"DashScope API Key (Emacs)\" service emacs-ai provider dashscope\n")
        (insert "如何验证：\n")
        (insert "  secret-tool lookup service emacs-ai provider dashscope\n")
        (insert "Emacs 内验证：\n")
        (insert "  (my/ai-read-api-key-from-keyring)\n\n")
        (insert "可选操作：\n")
        (insert-button "[打开右侧终端]"
                       'action (lambda (_btn) (my/ai-unavailable-open-terminal))
                       'follow-link t)
        (insert "\n")
        (insert-button "[刷新并重试 AI]"
                       'action (lambda (_btn) (my/ai-open-panel))
                       'follow-link t)
        (insert "\n")
        (insert-button "[关闭这个区域]"
                       'action (lambda (_btn) (my/ai-unavailable-close-panel))
                       'follow-link t)
        (insert "\n\n快捷键：o=打开终端, r=刷新重试, q=关闭区域\n")
        (goto-char (point-min)))
      (local-set-key (kbd "o") #'my/ai-unavailable-open-terminal)
      (local-set-key (kbd "r") #'my/ai-open-panel)
      (local-set-key (kbd "q") #'my/ai-unavailable-close-panel))
    (my/ai-display-side-buffer buf)))

(defun my/ai-open-codex-panel ()
  "右侧打开 Codex 终端面板（当 ellama provider 不可用时作为回退）。"
  (interactive)
  (let ((buf (get-buffer "*AI-Codex*")))
    (unless (and buf (buffer-live-p buf) (get-buffer-process buf))
      (setq buf (if (fboundp 'vterm)
                    (vterm "*AI-Codex*")
                  (get-buffer-create "*AI-Codex*")))
      (with-current-buffer buf
        (unless (derived-mode-p 'vterm-mode)
          (shell buf))
        (when (derived-mode-p 'vterm-mode)
          (vterm-send-string "codex")
          (vterm-send-return))))
    (display-buffer buf
                    `((display-buffer-in-side-window)
                      (side . right)
                      (slot . 2)
                      (window-width . ,my/ai-side-window-width)))))

(defun my/ai-ask-codebase ()
  "针对当前区域或当前文件发起 AI 询问。"
  (interactive)
  (if (use-region-p)
      (call-interactively #'ellama-ask-about)
    (save-excursion
      (goto-char (point-min))
      (push-mark (point-max) nil t)
      (activate-mark)
      (call-interactively #'ellama-ask-about)
      (deactivate-mark))))

(global-set-key (kbd "C-c a a") #'my/ai-open-panel)
(global-set-key (kbd "C-c a q") #'my/ai-ask-codebase)
(global-set-key (kbd "C-c a e") #'ellama-code-edit)
(global-set-key (kbd "C-c a i") #'ellama-code-add)
(global-set-key (kbd "C-c a c") #'ellama-chat)
(add-hook 'window-size-change-functions #'my/ai-recenter-info-panels)

(provide 'core-ai)
;;; ai.el ends here
