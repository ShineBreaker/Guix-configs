;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; leader.el --- Leader 键绑定系统 -*- lexical-binding: t; -*-

;;; Commentary:
;; 参考 Spacemacs/Doom Emacs 的 Leader 键设计，减少对 Ctrl 键的依赖。
;; - SPC 作为 Leader 键（Evil Normal/Visual 状态）
;; - , 作为 Local Leader 键（针对特定 major mode）
;; - 使用 general.el 管理键绑定

;;; Code:

(use-package general
  :demand t
  :config
  ;; 定义 Leader 键为 SPC（在 Evil Normal/Visual 状态）
  (general-create-definer my/leader-def
    :states '(normal visual)
    :keymaps 'override
    :prefix "SPC")

  ;; 定义 Local Leader 键为 ,（针对特定 major mode）
  (general-create-definer my/local-leader-def
    :states '(normal visual)
    :keymaps 'override
    :prefix ",")

  ;; 文件操作 (SPC f)
  (my/leader-def
    "f" '(:ignore t :which-key "文件")
    "ff" '(find-file :which-key "打开文件")
    "fs" '(save-buffer :which-key "保存文件")
    "fS" '(write-file :which-key "另存为")
    "fr" '(consult-recent-file :which-key "最近文件"))

  ;; 缓冲区操作 (SPC b)
  (my/leader-def
    "b" '(:ignore t :which-key "缓冲区")
    "bb" '(consult-buffer :which-key "切换缓冲区")
    "bd" '(kill-current-buffer :which-key "关闭缓冲区")
    "bk" '(kill-buffer :which-key "关闭指定缓冲区")
    "bl" '(ibuffer :which-key "列出缓冲区")
    "bn" '(next-buffer :which-key "下一个缓冲区")
    "bp" '(previous-buffer :which-key "上一个缓冲区"))

  ;; 窗口操作 (SPC w)
  (my/leader-def
    "w" '(:ignore t :which-key "窗口")
    "wd" '(delete-window :which-key "关闭窗口")
    "wD" '(delete-other-windows :which-key "只保留当前窗口")
    "ws" '(split-window-below :which-key "水平分割")
    "wv" '(split-window-right :which-key "垂直分割")
    "wh" '(evil-window-left :which-key "左窗口")
    "wj" '(evil-window-down :which-key "下窗口")
    "wk" '(evil-window-up :which-key "上窗口")
    "wl" '(evil-window-right :which-key "右窗口")
    "wo" '(other-window :which-key "下一个窗口"))

  ;; 项目操作 (SPC p)
  (my/leader-def
    "p" '(:ignore t :which-key "项目")
    "pf" '(project-find-file :which-key "查找文件")
    "pp" '(projectile-switch-project :which-key "切换项目")
    "ps" '(consult-ripgrep :which-key "搜索项目")
    "pd" '(projectile-dired :which-key "项目目录")
    "pk" '(projectile-kill-buffers :which-key "关闭项目缓冲区"))

  ;; 搜索操作 (SPC s)
  (my/leader-def
    "s" '(:ignore t :which-key "搜索")
    "ss" '(consult-line :which-key "搜索当前文件")
    "sp" '(consult-ripgrep :which-key "搜索项目")
    "sb" '(consult-buffer :which-key "搜索缓冲区"))

  ;; Git 操作 (SPC g)
  (my/leader-def
    "g" '(:ignore t :which-key "Git")
    "gs" '(magit-status :which-key "Git 状态")
    "gb" '(magit-blame :which-key "Git blame")
    "gl" '(magit-log :which-key "Git 日志")
    "gd" '(magit-diff :which-key "Git 差异"))

  ;; AI 操作 (SPC a)
  (my/leader-def
    "a" '(:ignore t :which-key "AI")
    "aa" '(my/ai-open-panel :which-key "打开 AI 终端"))

  ;; 切换操作 (SPC t)
  (my/leader-def
    "t" '(:ignore t :which-key "切换")
    "tt" '(treemacs :which-key "文件树")
    "tv" '(vterm :which-key "终端")
    "tl" '(my/vscode-layout :which-key "工作区布局"))

  ;; Org Mode (SPC o)
  (my/leader-def
    "o" '(:ignore t :which-key "Org")
    "oa" '(org-agenda :which-key "议程")
    "oc" '(cfw:open-org-calendar :which-key "日历")
    "on" '(:ignore t :which-key "笔记")
    "onf" '(org-roam-node-find :which-key "查找笔记")
    "oni" '(org-roam-node-insert :which-key "插入笔记")
    "onl" '(org-roam-buffer-toggle :which-key "反向链接"))

  ;; 帮助系统 (SPC h)
  (my/leader-def
    "h" '(:ignore t :which-key "帮助")
    "hf" '(helpful-callable :which-key "查看函数")
    "hv" '(helpful-variable :which-key "查看变量")
    "hk" '(helpful-key :which-key "查看按键")
    "hm" '(describe-mode :which-key "查看模式")
    "h?" '(my/show-shortcuts-help :which-key "快捷键帮助"))

  ;; 快速操作 (SPC SPC)
  (my/leader-def
    "SPC" '(execute-extended-command :which-key "M-x")
    ":" '(eval-expression :which-key "执行表达式")
    "q" '(save-buffers-kill-terminal :which-key "退出 Emacs")))

;; Markdown 模式 Local Leader 键
(general-define-key
 :states '(normal visual)
 :keymaps 'markdown-mode-map
 :prefix ","
 "p" '(markdown-preview :which-key "预览"))

(provide 'leader)
;;; leader.el ends here
