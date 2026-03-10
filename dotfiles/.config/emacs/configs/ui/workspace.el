;;; workspace.el --- 工作区布局与文件树 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置 Treemacs 文件树和 VS Code 风格的工作区布局。

;;; Code:

(require 'seq)
(require 'cl-lib)

;; Treemacs 文件树
(use-package treemacs
  :bind ("C-c t" . treemacs)
  :custom
  (treemacs-width 30)
  (treemacs-position 'left)
  (treemacs-git-mode 'simple)
  :config
  (treemacs-project-follow-mode 1)
  (treemacs-follow-mode 1))

;; Nerd Icons 主题
(use-package treemacs-nerd-icons
  :after treemacs
  :config
  (treemacs-load-theme "nerd-icons"))

;; 快捷键帮助
(defun my/show-shortcuts-help ()
  "显示完整的快捷键帮助。"
  (interactive)
  (let ((buf (get-buffer-create "*Shortcuts Help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert "\n")
        (insert (propertize "快捷键完整参考\n\n" 'face '(:height 1.5 :weight bold)))
        (cl-labels
            ((section (title)
               (insert (propertize title 'face '(:weight bold :foreground "#7aa2f7" :height 1.2)))
               (insert "\n\n"))
             (subsection (title)
               (insert (propertize title 'face '(:weight bold :foreground "#bb9af7")))
               (insert "\n"))
             (row (key desc)
               (insert (format "  %-18s %s\n"
                              (propertize key 'face 'font-lock-keyword-face)
                              desc))))

          ;; 基础操作
          (section "═══ 基础操作 ═══")
          (subsection "文件操作")
          (row "C-x C-f" "打开文件")
          (row "C-x C-s" "保存当前文件")
          (row "C-x C-w" "另存为")
          (row "C-x s" "保存所有文件")
          (row "C-x C-c" "退出 Emacs")
          (insert "\n")

          (subsection "缓冲区管理")
          (row "C-x b" "切换缓冲区")
          (row "C-S-b" "快速切换缓冲区（增强）")
          (row "C-x k" "关闭当前缓冲区")
          (row "C-x C-b" "列出所有缓冲区")
          (row "C-x <left/right>" "切换到上/下一个缓冲区")
          (insert "\n")

          (subsection "窗口管理")
          (row "C-x 0" "关闭当前窗口")
          (row "C-x 1" "只保留当前窗口")
          (row "C-x 2" "水平分割窗口")
          (row "C-x 3" "垂直分割窗口")
          (row "C-x o" "切换到下一个窗口")
          (row "C-w h/j/k/l" "切换到 左/下/上/右 窗口（Vim 风格）")
          (insert "\n")

          ;; 编辑操作
          (section "═══ 编辑操作 ═══")
          (subsection "复制粘贴")
          (row "C-S-c" "复制（选区或当前行）")
          (row "C-S-x" "剪切（选区或当前行）")
          (row "C-S-v" "粘贴")
          (row "M-y" "粘贴历史（在粘贴后使用）")
          (row "C-w" "剪切选区（Emacs 原生）")
          (row "M-w" "复制选区（Emacs 原生）")
          (row "C-y" "粘贴（Emacs 原生）")
          (insert "\n")

          (subsection "撤销重做")
          (row "C-/" "撤销")
          (row "C-?" "重做")
          (row "C-x u" "撤销（另一种方式）")
          (insert "\n")

          (subsection "选择与标记")
          (row "C-SPC" "设置标记（开始选择）")
          (row "C-x h" "全选")
          (row "M-h" "选择当前段落")
          (row "C-M-h" "选择当前函数")
          (insert "\n")

          (subsection "删除操作")
          (row "C-d" "删除光标后的字符")
          (row "DEL" "删除光标前的字符")
          (row "M-d" "删除光标后的单词")
          (row "M-DEL" "删除光标前的单词")
          (row "C-k" "删除到行尾")
          (row "C-S-k" "删除整行")
          (insert "\n")

          ;; 搜索与导航
          (section "═══ 搜索与导航 ═══")
          (subsection "文件内搜索")
          (row "C-s" "向前搜索")
          (row "C-r" "向后搜索")
          (row "M-%" "查找替换")
          (row "C-M-s" "正则表达式搜索")
          (insert "\n")

          (subsection "项目搜索")
          (row "C-p" "项目内快速找文件")
          (row "C-S-f" "全文搜索（ripgrep）")
          (row "C-c p s s" "项目内搜索")
          (row "C-c p f" "项目内查找文件")
          (insert "\n")

          (subsection "光标移动")
          (row "C-f/b" "前进/后退一个字符")
          (row "M-f/b" "前进/后退一个单词")
          (row "C-n/p" "下一行/上一行")
          (row "C-a/e" "行首/行尾")
          (row "M-a/e" "句首/句尾")
          (row "M-{/}" "段首/段尾")
          (row "C-v/M-v" "向下/向上翻页")
          (row "M-</>" "文件开头/结尾")
          (row "M-g g" "跳转到指定行")
          (insert "\n")

          ;; 项目管理
          (section "═══ 项目管理 ═══")
          (subsection "Projectile")
          (row "C-c p p" "切换项目")
          (row "C-c p f" "项目内查找文件")
          (row "C-c p s s" "项目内搜索")
          (row "C-c p k" "关闭项目所有缓冲区")
          (row "C-c p d" "打开项目根目录")
          (insert "\n")

          (subsection "文件树")
          (row "C-c t" "打开/关闭 Treemacs")
          (row "?" "Treemacs 帮助（在 Treemacs 中）")
          (insert "\n")

          ;; Git 操作
          (section "═══ Git 操作 ═══")
          (subsection "Magit")
          (row "C-x g" "打开 Magit 状态")
          (row "C-c g b" "显示当前行 Git blame")
          (insert "\n")

          (subsection "Magit 状态页操作")
          (row "s" "暂存文件/区块")
          (row "u" "取消暂存")
          (row "c c" "提交")
          (row "P p" "推送到远程")
          (row "F p" "从远程拉取")
          (row "b b" "切换分支")
          (row "b c" "创建新分支")
          (row "l l" "查看日志")
          (row "d d" "查看差异")
          (row "q" "退出 Magit")
          (insert "\n")

          ;; AI 工具
          (section "═══ AI 工具 ═══")
          (subsection "Ellama AI 助手")
          (row "C-c a c" "开始 AI 对话")
          (row "C-c a q" "询问选中的代码")
          (row "C-c a e" "让 AI 改写代码")
          (row "C-c a i" "让 AI 补写代码")
          (row "C-c a a" "让 AI 添加代码")
          (row "C-c a s" "总结选中的内容")
          (insert "\n")

          ;; LSP 与代码
          (section "═══ 代码编辑 ═══")
          (subsection "LSP 功能")
          (row "M-." "跳转到定义")
          (row "M-," "返回")
          (row "M-?" "查找引用")
          (row "C-." "代码操作菜单")
          (row "C-c l r" "重命名符号")
          (row "C-c l f" "格式化代码")
          (insert "\n")

          (subsection "补全")
          (row "TAB" "触发补全")
          (row "C-n/p" "选择下一个/上一个补全项")
          (row "RET" "确认补全")
          (insert "\n")

          ;; Org Mode
          (section "═══ Org Mode ═══")
          (subsection "基础操作")
          (row "TAB" "折叠/展开标题")
          (row "S-TAB" "全局折叠/展开")
          (row "C-c C-t" "切换 TODO 状态")
          (row "C-c C-s" "设置计划时间")
          (row "C-c C-d" "设置截止时间")
          (row "C-c C-c" "执行当前项操作")
          (insert "\n")

          (subsection "Org Roam 笔记")
          (row "C-c n f" "查找/创建笔记")
          (row "C-c n i" "插入笔记链接")
          (row "C-c n l" "显示反向链接")
          (insert "\n")

          (subsection "Org Agenda")
          (row "C-c a" "打开议程视图")
          (row "C-c c" "打开日历")
          (insert "\n")

          ;; Evil 模式
          (section "═══ Evil (Vim) 模式 ═══")
          (subsection "模式切换")
          (row "C-c v v" "切换到 Vim 普通模式")
          (row "C-c v e" "切换到 Emacs 模式")
          (row "i" "插入模式（在 Evil 中）")
          (row "ESC" "返回普通模式（在 Evil 中）")
          (insert "\n")

          (subsection "Evil 普通模式")
          (row "h/j/k/l" "左/下/上/右移动")
          (row "w/b" "下一个/上一个单词")
          (row "0/$" "行首/行尾")
          (row "gg/G" "文件开头/结尾")
          (row "dd" "删除当前行")
          (row "yy" "复制当前行")
          (row "p/P" "粘贴到后面/前面")
          (row "u" "撤销")
          (row "C-r" "重做")
          (row "v" "可视模式")
          (row "V" "可视行模式")
          (row "C-v" "可视块模式")
          (row ":" "命令模式")
          (insert "\n")

          ;; 工作区
          (section "═══ 工作区布局 ═══")
          (row "<f5>" "重建 VS Code 风格布局")
          (row "C-c v t" "打开终端")
          (insert "\n")

          ;; 帮助系统
          (section "═══ 帮助系统 ═══")
          (row "F1 ?" "显示此帮助")
          (row "C-h k" "查看按键绑定")
          (row "C-h f" "查看函数文档")
          (row "C-h v" "查看变量文档")
          (row "C-h m" "查看当前模式帮助")
          (row "C-h a" "搜索命令")
          (insert "\n")

          ;; 其他
          (section "═══ 其他 ═══")
          (row "C-g" "取消当前命令")
          (row "M-x" "执行命令")
          (row "C-x C-e" "执行光标前的 Lisp 表达式")
          (row "C-c m" "打开邮件（Notmuch）")
          (insert "\n\n")

          (insert (propertize "提示：" 'face '(:weight bold)))
          (insert " 按 ")
          (insert (propertize "q" 'face 'font-lock-keyword-face))
          (insert " 关闭此帮助窗口\n"))
        (goto-char (point-min))))
    (pop-to-buffer buf)))

;; 辅助函数
(defun my/find-code-window ()
  "查找代码编辑窗口。"
  (seq-find
   (lambda (win)
     (with-selected-window win
       (and (not (window-parameter win 'window-side))
            (not (derived-mode-p 'treemacs-mode 'vterm-mode)))))
   (window-list)))

;; VS Code 风格布局：左树+中代码+下终端+右AI
(defun my/vscode-layout ()
  "重置为类似 VS Code 的布局。"
  (interactive)
  (let* ((terminal-height 12)
         (code-win nil)
         (vterm-win
          (seq-find
           (lambda (win)
             (with-selected-window win
               (derived-mode-p 'vterm-mode)))
           (window-list))))
    ;; 打开 Treemacs
    (unless (and (fboundp 'treemacs-is-visible) (treemacs-is-visible))
      (treemacs))
    ;; 获取代码窗口
    (setq code-win (or (my/find-code-window) (selected-window)))
    (select-window code-win)
    ;; 创建底部终端（仅当不存在时）
    (unless (window-live-p vterm-win)
      (when (> (window-height) (+ terminal-height 5))
        (split-window-below (- (window-height) terminal-height))
        (other-window 1)
        (if (fboundp 'vterm)
            (vterm)
          (shell))
        (other-window -1)))
    ;; 打开右侧 AI 面板
    (when (fboundp 'my/ai-open-panel)
      (ignore-errors (my/ai-open-panel)))
    ;; 焦点回到代码窗口
    (when (window-live-p code-win)
      (select-window code-win))))

;; 判断是否应该自动触发布局
(defun my/should-auto-layout-p ()
  "判断当前是否应该自动触发 VSCode 布局。"
  (and (buffer-file-name)
       (not (derived-mode-p 'org-mode 'org-agenda-mode))
       (not (string-match-p "\\*.*\\*" (buffer-name)))
       (or (and (fboundp 'projectile-project-p) (projectile-project-p))
           (vc-backend (buffer-file-name)))))

;; 跟踪当前项目
(defvar my/current-project nil
  "当前项目的根目录，用于检测项目切换。")

;; 打开项目文件时自动应用布局
(defun my/auto-layout-on-file-open ()
  "打开文件时，如果切换到了新项目则自动应用布局。"
  (when (my/should-auto-layout-p)
    (let ((project-root (and (fboundp 'projectile-project-root)
                             (projectile-project-root))))
      (when (and project-root
                 (not (equal project-root my/current-project)))
        (setq my/current-project project-root)
        (run-with-idle-timer 0.1 nil #'my/vscode-layout)))))

;; 快捷键绑定
(global-set-key (kbd "<f5>") #'my/vscode-layout)
(global-set-key (kbd "<f1> ?") #'my/show-shortcuts-help)
(add-hook 'find-file-hook #'my/auto-layout-on-file-open)

(provide 'workspace)
;;; workspace.el ends here
