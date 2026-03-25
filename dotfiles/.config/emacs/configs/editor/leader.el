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

;; ═════════════════════════════════════════════════════════════════════════════
;; 代码操作函数
;; ═════════════════════════════════════════════════════════════════════════════

;; ───────────── 替换功能 ─────────────

(defun my/code-replace-simple ()
  "执行简单字符串替换（不解释为正则）。"
  (interactive)
  (call-interactively #'query-replace))

(defun my/code-replace-regexp ()
  "执行正则表达式替换。"
  (interactive)
  (call-interactively #'query-replace-regexp))

(defun my/code-replace-project ()
  "在项目范围内执行替换。"
  (interactive)
  (require 'project)
  (cond
   ((and (project-current nil)
         (fboundp 'project-query-replace-regexp))
    (call-interactively #'project-query-replace-regexp))
   ((and (project-current nil)
         (fboundp 'project-query-replace))
    (call-interactively #'project-query-replace))
   (t
    (message "当前不在项目中，使用当前缓冲区替换")
    (call-interactively #'query-replace-regexp))))

(defun my/code-replace ()
  "智能替换：根据上下文选择合适的替换方式。
在选中区域时执行区域内替换，否则执行全局替换。"
  (interactive)
  (if (use-region-p)
      (progn
        (message "执行区域内替换 (C-r 切换正则模式)")
        (call-interactively #'query-replace))
    (call-interactively #'my/code-replace-simple)))

;; ───────────── 行操作 ─────────────

(defun my/code-delete-line ()
  "删除整行（不加入 kill-ring）。"
  (interactive)
  (save-excursion
    (beginning-of-line)
    (kill-whole-line)))

(defun my/code-copy-line ()
  "复制当前行到 kill-ring。"
  (interactive)
  (save-excursion
    (let ((start (progn (beginning-of-line) (point)))
          (end (progn (end-of-line) (point))))
      (copy-region-as-kill start (1+ end))
      (message "已复制整行"))))

(defun my/code-duplicate-line ()
  "复制当前行并在下方粘贴。"
  (interactive)
  (save-excursion
    (let ((start (line-beginning-position))
          (end (line-end-position))
          (column (current-column)))
      (copy-region-as-kill start (1+ end))
      (end-of-line)
      (newline)
      (yank)
      (move-to-column column))))

(defun my/code-duplicate-line-above ()
  "复制当前行并在上方粘贴。"
  (interactive)
  (save-excursion
    (let ((start (line-beginning-position))
          (end (line-end-position))
          (column (current-column)))
      (copy-region-as-kill start (1+ end))
      (beginning-of-line)
      (yank)
      (newline)
      (previous-line)
      (move-to-column column))))

(defun my/code-join-line ()
  "将当前行与下一行合并（类似 JetBrains 的 Ctrl+Shift+J）。"
  (interactive)
  (join-line -1))

(defun my/code-split-line ()
  "在当前位置分割行（类似 JetBrains 的 Enter）。"
  (interactive)
  (newline-and-indent))

(defun my/code-move-line-up ()
  "将当前行上移一行。"
  (interactive)
  (transpose-lines 1)
  (previous-line 2))

(defun my/code-move-line-down ()
  "将当前行下移一行。"
  (interactive)
  (forward-line 1)
  (transpose-lines 1)
  (previous-line 1))

(defun my/code-kill-to-end ()
  "从光标位置删除到行尾（类似 Ctrl+K）。"
  (interactive)
  (kill-line))

(defun my/code-kill-to-beginning ()
  "从光标位置删除到行首。"
  (interactive)
  (kill-line 0))

;; ───────────── 注释操作 ─────────────

(defun my/code-comment-line ()
  "注释/取消注释当前行。"
  (interactive)
  (save-excursion
    (comment-or-uncomment-region (line-beginning-position)
                                  (line-end-position))))

(defun my/code-comment-dwim ()
  "智能注释：有选区则注释选区，否则注释当前行。"
  (interactive)
  (if (use-region-p)
      (comment-dwim nil)
    (my/code-comment-line)))

(defun my/code-comment-block ()
  "使用块注释包围选区。"
  (interactive)
  (if (use-region-p)
      (let ((comment-style 'multi-line))
        (comment-region (region-beginning) (region-end)))
    (message "请先选择要块注释的区域")))

;; ───────────── 格式化 ─────────────

(defun my/code-format-dwim ()
  "智能格式化：有选区则格式化选区，否则格式化整个缓冲区。"
  (interactive)
  (if (use-region-p)
      (indent-region (region-beginning) (region-end))
    (if (fboundp 'eglot-format-buffer)
        (eglot-format-buffer)
      (indent-region (point-min) (point-max)))))

(defun my/code-format-region ()
  "格式化选中区域。"
  (interactive)
  (if (use-region-p)
      (indent-region (region-beginning) (region-end))
    (message "请先选择要格式化的区域")))

(defun my/code-format-buffer ()
  "格式化整个缓冲区。"
  (interactive)
  (if (and (fboundp 'eglot-managed-p) (eglot-managed-p))
      (eglot-format-buffer)
    (indent-region (point-min) (point-max))))

(defun my/code-indent-rigidly-right ()
  "将选中区域向右缩进一个 tab 宽度。"
  (interactive)
  (if (use-region-p)
      (indent-rigidly (region-beginning) (region-end) tab-width)
    (indent-rigidly (line-beginning-position) (line-end-position) tab-width)))

(defun my/code-indent-rigidly-left ()
  "将选中区域向左缩进一个 tab 宽度。"
  (interactive)
  (if (use-region-p)
      (indent-rigidly (region-beginning) (region-end) (- tab-width))
    (indent-rigidly (line-beginning-position) (line-end-position) (- tab-width))))

;; ───────────── 文本操作 ─────────────

(defun my/code-upcase-word ()
  "将当前单词转换为大写。"
  (interactive)
  (upcase-word 1))

(defun my/code-downcase-word ()
  "将当前单词转换为小写。"
  (interactive)
  (downcase-word 1))

(defun my/code-capitalize-word ()
  "将当前单词首字母大写。"
  (interactive)
  (capitalize-word 1))

(defun my/code-transpose-chars ()
  "交换光标前后的字符。"
  (interactive)
  (transpose-chars 1))

(defun my/code-transpose-words ()
  "交换光标前后的单词。"
  (interactive)
  (transpose-words 1))

(defun my/code-transpose-lines ()
  "交换当前行和上一行。"
  (interactive)
  (transpose-lines 1))

;; ───────────── 包围操作 (Surround) ─────────────

(defun my/code-surround-with (char)
  "用指定字符包围选区。"
  (interactive "c输入包围字符 (例如: ( [ { ' \"): ")
  (if (use-region-p)
      (let* ((open char)
             (close (cond ((eq open ?\() ?\))
                         ((eq open ?\[) ?\])
                         ((eq open ?\{) ?\})
                         ((eq open ?<) ?>)
                         ((eq open ?\") ?\")
                         ((eq open ?\') ?\')
                         ((eq open ?\`) ?\`)
                         (t open)))
             (beg (region-beginning))
             (end (region-end)))
        (goto-char end)
        (insert close)
        (goto-char beg)
        (insert open))
    (message "请先选择要包围的区域")))

(defun my/code-wrap-parens ()
  "用圆括号包围选区。"
  (interactive)
  (my/code-surround-with ?\())

(defun my/code-wrap-brackets ()
  "用方括号包围选区。"
  (interactive)
  (my/code-surround-with ?\[))

(defun my/code-wrap-braces ()
  "用花括号包围选区。"
  (interactive)
  (my/code-surround-with ?\{))

(defun my/code-wrap-quotes ()
  "用双引号包围选区。"
  (interactive)
  (my/code-surround-with ?\"))

(defun my/code-wrap-single-quotes ()
  "用单引号包围选区。"
  (interactive)
  (my/code-surround-with ?\'))

(defun my/code-unwrap ()
  "删除包围选区的括号/引号（向后查找）。"
  (interactive)
  (save-excursion
    (let ((beg (if (use-region-p) (region-beginning) (point)))
          (end (if (use-region-p) (region-end) (point))))
      ;; 查找包围的括号
      (goto-char beg)
      (if (re-search-backward "[[({<\"'`]" (line-beginning-position) t)
          (let ((open (char-after)))
            (delete-char 1)
            (goto-char end)
            ;; 调整位置（因为前面删除了一个字符）
            (if (= beg end)
                (goto-char end)
              (goto-char (1- end)))
            ;; 查找对应的关闭括号
            (if (re-search-forward "[])}>\"'`]" (line-end-position) t)
                (let ((close (char-before)))
                  (when (or (and (= open ?\() (= close ?\)))
                           (and (= open ?\[) (= close ?\]))
                           (and (= open ?\{) (= close ?\}))
                           (and (= open ?<) (= close ?>))
                           (and (= open ?\") (= close ?\"))
                           (and (= open ?\') (= close ?\'))
                           (and (= open ?\`) (= close ?\`)))
                    (delete-char -1)
                    (message "已移除包围字符: %c...%c" open close)))
              (message "未找到关闭括号")))
        (message "未找到包围字符")))))

;; ───────────── LSP 相关操作 ─────────────

(defun my/code-action ()
  "执行代码操作（Code Action）。"
  (interactive)
  (if (fboundp 'eglot-code-actions)
      (call-interactively #'eglot-code-actions)
    (message "LSP 未启用")))

(defun my/code-rename ()
  "重命名符号。"
  (interactive)
  (if (fboundp 'eglot-rename)
      (call-interactively #'eglot-rename)
    (message "LSP 未启用")))

(defun my/code-goto-definition ()
  "跳转到定义。"
  (interactive)
  (if (fboundp 'eglot-find-definition)
      (call-interactively #'xref-find-definitions)
    (call-interactively #'xref-find-definitions)))

(defun my/code-goto-references ()
  "查找所有引用。"
  (interactive)
  (call-interactively #'xref-find-references))

(defun my/code-show-hover ()
  "显示光标下的符号信息（悬停提示）。"
  (interactive)
  (if (fboundp 'eglot-help-at-point)
      (eglot-help-at-point)
    (if (fboundp 'eldoc-doc-buffer)
        (eldoc-doc-buffer)
      (describe-thing-in-context))))

(defun my/code-quick-fix ()
  "快速修复当前问题。"
  (interactive)
  (if (fboundp 'eglot-code-action-quickfix)
      (eglot-code-action-quickfix)
    (my/code-action)))

;; ───────────── 代码折叠 ─────────────

(defun my/code-fold-toggle ()
  "切换当前折叠状态。"
  (interactive)
  (if (fboundp 'origami-toggle-node)
      (origami-toggle-node (current-buffer) (point))
    (if (fboundp 'hs-toggle-hiding)
        (hs-toggle-hiding)
      (message "未启用代码折叠"))))

(defun my/code-fold-all ()
  "折叠所有代码块。"
  (interactive)
  (if (fboundp 'origami-close-all-nodes)
      (origami-close-all-nodes (current-buffer))
    (if (fboundp 'hs-hide-all)
        (hs-hide-all)
      (message "未启用代码折叠"))))

(defun my/code-unfold-all ()
  "展开所有代码块。"
  (interactive)
  (if (fboundp 'origami-open-all-nodes)
      (origami-open-all-nodes (current-buffer))
    (if (fboundp 'hs-show-all)
        (hs-show-all)
      (message "未启用代码折叠"))))

;; ───────────── 多光标/多选 ─────────────

(defvar my/code-mc-mark-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'my/code-mc-mark-next)
    (define-key map (kbd "p") #'my/code-mc-mark-previous)
    (define-key map (kbd "a") #'my/code-mc-mark-all)
    (define-key map (kbd "q") #'keyboard-quit)
    map)
  "多光标标记的临时键映射。")

(defun my/code-mc-mark-next ()
  "选中下一个相同单词（类似 VSCode Ctrl+D）。"
  (interactive)
  (if (fboundp 'mc/mark-next-like-this)
      (mc/mark-next-like-this 1)
    (message "请先安装 multiple-cursors 包")))

(defun my/code-mc-mark-previous ()
  "选中上一个相同单词。"
  (interactive)
  (if (fboundp 'mc/mark-previous-like-this)
      (mc/mark-previous-like-this 1)
    (message "请先安装 multiple-cursors 包")))

(defun my/code-mc-mark-all ()
  "选中所有相同单词。"
  (interactive)
  (if (fboundp 'mc/mark-all-like-this)
      (mc/mark-all-like-this)
    (message "请先安装 multiple-cursors 包")))

(defun my/code-mc-skip-next ()
  "跳过当前匹配，选中下一个。"
  (interactive)
  (if (fboundp 'mc/skip-to-next-like-this)
      (mc/skip-to-next-like-this)
    (message "请先安装 multiple-cursors 包")))

(defun my/code-mc-skip-previous ()
  "跳过当前匹配，选中上一个。"
  (interactive)
  (if (fboundp 'mc/skip-to-previous-like-this)
      (mc/skip-to-previous-like-this)
    (message "请先安装 multiple-cursors 包")))

(defun my/code-expand-selection ()
  "逐步扩大选区（类似 VSCode Shift+Alt+→）。"
  (interactive)
  (if (fboundp 'er/expand-region)
      (er/expand-region 1)
    (progn
      ;; 简单的备选实现
      (if (use-region-p)
          (let ((start (region-beginning))
                (end (region-end)))
            (goto-char start)
            (forward-word -1)
            (set-mark (point))
            (goto-char end)
            (forward-word 1))
        (let ((bounds (bounds-of-thing-at-point 'word)))
          (when bounds
            (goto-char (car bounds))
            (set-mark (point))
            (goto-char (cdr bounds))))))))

(defun my/code-contract-selection ()
  "逐步缩小选区。"
  (interactive)
  (if (fboundp 'er/contract-region)
      (er/contract-region 1)
    (message "请先安装 expand-region 包")))

(defun my/code-select-line ()
  "选中当前行。"
  (interactive)
  (end-of-line)
  (set-mark (line-beginning-position)))

(defun my/code-select-block ()
  "选中当前代码块。"
  (interactive)
  (mark-defun))

(defun my/code-select-function ()
  "选中当前函数。"
  (interactive)
  (mark-defun))

;; ───────────── 跳转与书签 ─────────────

(defun my/code-jump-back ()
  "跳回之前的位置（后退）。"
  (interactive)
  (if (fboundp 'xref-go-back)
      (xref-go-back)
    (pop-mark)))

(defun my/code-jump-forward ()
  "跳到下一个位置（前进）。"
  (interactive)
  (if (fboundp 'xref-go-forward)
      (xref-go-forward)
    (message "前进功能不可用")))

(defun my/code-toggle-bookmark ()
  "切换当前行的书签。"
  (interactive)
  (if (fboundp 'bookmark-set)
      (call-interactively #'bookmark-set)
    (message "书签功能不可用")))

(defun my/code-list-bookmarks ()
  "列出所有书签。"
  (interactive)
  (if (fboundp 'bookmark-bmenu-list)
      (bookmark-bmenu-list)
    (message "书签功能不可用")))

;; ───────────── 空行与清理 ─────────────

(defun my/code-delete-blank-lines ()
  "删除周围的空行，只保留一行。"
  (interactive)
  (delete-blank-lines))

(defun my/code-join-next-line ()
  "将下一行连接到当前行（删除换行）。"
  (interactive)
  (end-of-line)
  (delete-char 1))

(defun my/code-insert-empty-line-below ()
  "在当前行下方插入空行。"
  (interactive)
  (end-of-line)
  (newline))

(defun my/code-insert-empty-line-above ()
  "在当前行上方插入空行。"
  (interactive)
  (beginning-of-line)
  (newline)
  (forward-line -1))

;; ───────────── 智能提示与补全 ─────────────

(defun my/code-complete ()
  "触发代码补全。"
  (interactive)
  (if (fboundp 'completion-at-point)
      (completion-at-point)
    (if (fboundp 'company-complete)
        (company-complete)
      (hippie-expand nil))))

(defun my/code-show-signature ()
  "显示函数签名。"
  (interactive)
  (if (fboundp 'eldoc)
      (eldoc-print-current-symbol-info)
    (message "Eldoc 未启用")))

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

  ;; 代码操作 (SPC c) - 参考 JetBrains/VSCode 功能设计
  (my/leader-def
    "c" '(:ignore t :which-key "代码")

    ;; ═════════════ 替换操作 (r) ═════════════
    "cr" '(:ignore t :which-key "替换")
    "crs" '(my/code-replace-simple :which-key "简单替换")
    "crR" '(my/code-replace-regexp :which-key "正则替换")
    "crp" '(my/code-replace-project :which-key "项目范围替换")
    "crf" '(my/code-replace :which-key "智能替换")

    ;; ═════════════ 行操作 (l) ═════════════
    "cl" '(:ignore t :which-key "行操作")
    "cld" '(my/code-delete-line :which-key "删除行")
    "clc" '(my/code-copy-line :which-key "复制行")
    "clD" '(my/code-duplicate-line :which-key "重复行(下)")
    "clA" '(my/code-duplicate-line-above :which-key "重复行(上)")
    "clj" '(my/code-join-line :which-key "合并行")
    "cls" '(my/code-split-line :which-key "分割行")
    "clk" '(my/code-kill-to-end :which-key "删到行尾")
    "clK" '(my/code-kill-to-beginning :which-key "删到行首")
    "clm" '(my/code-move-line-down :which-key "下移行")
    "clM" '(my/code-move-line-up :which-key "上移行")
    "clb" '(my/code-delete-blank-lines :which-key "清理空行")
    "cli" '(my/code-insert-empty-line-below :which-key "下方插入空行")
    "clI" '(my/code-insert-empty-line-above :which-key "上方插入空行")

    ;; ═════════════ 注释操作 (o) ═════════════
    "co" '(:ignore t :which-key "注释")
    "col" '(my/code-comment-line :which-key "注释/取消当前行")
    "cor" '(my/code-comment-dwim :which-key "智能注释(DWIM)")
    "cob" '(my/code-comment-block :which-key "块注释")
    "coc" '(comment-line :which-key "切换行注释")

    ;; ═════════════ 格式化 (f) ═════════════
    "cf" '(:ignore t :which-key "格式化")
    "cff" '(my/code-format-dwim :which-key "智能格式化")
    "cfr" '(my/code-format-region :which-key "格式化选区")
    "cfb" '(my/code-format-buffer :which-key "格式化整个缓冲区")
    "cfi" '(my/code-indent-rigidly-right :which-key "增加缩进")
    "cfI" '(my/code-indent-rigidly-left :which-key "减少缩进")

    ;; ═════════════ 文本变换 (t) ═════════════
    "ct" '(:ignore t :which-key "文本变换")
    "ctu" '(my/code-upcase-word :which-key "转大写")
    "ctl" '(my/code-downcase-word :which-key "转小写")
    "ctc" '(my/code-capitalize-word :which-key "首字母大写")
    "ctt" '(my/code-transpose-chars :which-key "交换字符")
    "ctw" '(my/code-transpose-words :which-key "交换单词")
    "ctL" '(my/code-transpose-lines :which-key "交换行")

    ;; ═════════════ 包围操作 (w) ═════════════
    "cw" '(:ignore t :which-key "包围")
    "cww" '(my/code-surround-with :which-key "自定义包围")
    "cw(" '(my/code-wrap-parens :which-key "圆括号包围")
    "cw)" '(my/code-wrap-parens :which-key "圆括号包围")
    "cw[" '(my/code-wrap-brackets :which-key "方括号包围")
    "cw]" '(my/code-wrap-brackets :which-key "方括号包围")
    "cw{" '(my/code-wrap-braces :which-key "花括号包围")
    "cw}" '(my/code-wrap-braces :which-key "花括号包围")
    "cw\"" '(my/code-wrap-quotes :which-key "双引号包围")
    "cw'" '(my/code-wrap-single-quotes :which-key "单引号包围")
    "cwr" '(my/code-unwrap :which-key "移除包围")

    ;; ═════════════ LSP/代码导航 (g) ═════════════
    "cg" '(:ignore t :which-key "代码导航/LSP")
    "cgd" '(my/code-goto-definition :which-key "跳转到定义")
    "cgr" '(my/code-goto-references :which-key "查找引用")
    "cgh" '(my/code-show-hover :which-key "显示悬停信息")
    "cga" '(my/code-action :which-key "代码操作")
    "cgf" '(my/code-quick-fix :which-key "快速修复")
    "cgn" '(my/code-rename :which-key "重命名")
    "cgb" '(my/code-jump-back :which-key "返回")
    "cgF" '(my/code-jump-forward :which-key "前进")

    ;; ═════════════ 代码折叠 (z) ═════════════
    "cz" '(:ignore t :which-key "代码折叠")
    "czz" '(my/code-fold-toggle :which-key "切换折叠")
    "czc" '(my/code-fold-all :which-key "全部折叠")
    "czo" '(my/code-unfold-all :which-key "全部展开")

    ;; ═════════════ 选择/扩展 (s) ═════════════
    "cs" '(:ignore t :which-key "选择")
    "csl" '(my/code-select-line :which-key "选中整行")
    "csf" '(my/code-select-function :which-key "选中函数")
    "csb" '(my/code-select-block :which-key "选中代码块")
    "cse" '(my/code-expand-selection :which-key "扩大选区")
    "csE" '(my/code-contract-selection :which-key "缩小选区")

    ;; ═════════════ 多光标 (m) ═════════════
    "cm" '(:ignore t :which-key "多光标")
    "cmn" '(my/code-mc-mark-next :which-key "标记下一个")
    "cmp" '(my/code-mc-mark-previous :which-key "标记上一个")
    "cma" '(my/code-mc-mark-all :which-key "标记全部")
    "cms" '(my/code-mc-skip-next :which-key "跳过并标记下一个")
    "cmS" '(my/code-mc-skip-previous :which-key "跳过并标记上一个")

    ;; ═════════════ 书签 (b) ═════════════
    "cb" '(:ignore t :which-key "书签")
    "cbt" '(my/code-toggle-bookmark :which-key "切换书签")
    "cbl" '(my/code-list-bookmarks :which-key "列出书签")

    ;; ═════════════ 补全与提示 (a) ═════════════
    "ca" '(:ignore t :which-key "补全/提示")
    "cac" '(my/code-complete :which-key "触发补全")
    "cas" '(my/code-show-signature :which-key "显示签名")

    ;; ═════════════ 其他 ═════════════
    "c SPC" '(my/code-complete :which-key "触发补全")
    "c." '(my/code-quick-fix :which-key "快速修复"))

  ;; Git 操作 (SPC g)
  (my/leader-def
    "g" '(:ignore t :which-key "Git")
    "gs" '(magit-status :which-key "Git 状态")
    "gb" '(magit-blame :which-key "Git blame")
    "gl" '(magit-log :which-key "Git 日志")
    "gd" '(magit-diff :which-key "Git 差异"))

  ;; 切换操作 (SPC t)
  (my/leader-def
    "t" '(:ignore t :which-key "切换")
    "tt" '(treemacs :which-key "文件树")
    "tv" '(my/vterm :which-key "终端")
    "tl" '(my/vscode-layout :which-key "工作区布局")
    "ts" '(my/sidebar-toggle :which-key "功能栏"))

  ;; Org Mode (SPC o)
  (my/leader-def
    "o" '(:ignore t :which-key "Org")
    "oa" '(org-agenda :which-key "议程")
    "oc" '(cfw:open-org-calendar :which-key "日历")
    ;; ═════════════ Babel 文学编程 (b) ═════════════
    "ob" '(:ignore t :which-key "Babel")
    "obe" '(my/org-babel-execute-current-block :which-key "执行当前块")
    "obE" '(my/org-babel-execute-all :which-key "执行所有块")
    "obn" '(org-babel-next-src-block :which-key "下一个代码块")
    "obp" '(org-babel-previous-src-block :which-key "上一个代码块")
    "obt" '(my/org-babel-tangle-current-block :which-key "Tangle 当前块")
    "obT" '(my/org-babel-tangle-file :which-key "Tangle 整个文件")
    "obg" '(my/org-babel-goto-block :which-key "跳转代码块")
    "obd" '(my/org-babel-demarcate-block :which-key "分割代码块")
    "ob'" '(my/org-babel-edit-src-code :which-key "编辑代码块")
    ;; ═════════════ 插入代码块 (i) ═════════════
    "oi" '(:ignore t :which-key "插入代码块")
    "oie" '(my/org-insert-elisp-block :which-key "Emacs Lisp")
    "ois" '(my/org-insert-shell-block :which-key "Shell")
    "oip" '(my/org-insert-python-block :which-key "Python")
    "oiS" '(my/org-insert-scheme-block :which-key "Scheme")
    "oid" '(my/org-insert-dot-block :which-key "Graphviz")
    "oiu" '(my/org-insert-plantuml-block :which-key "PlantUML")
    ;; ═════════════ Org 操作 (r) ═════════════
    "or" '(:ignore t :which-key "Org 操作")
    "ort" '(my/org-todo-todo :which-key "标记 TODO")
    "ord" '(my/org-todo-done :which-key "标记完成")
    "ora" '(my/org-archive-subtree :which-key "归档")
    "orn" '(my/org-narrow-to-subtree :which-key "窄化视图")
    "orw" '(my/org-widen :which-key "恢复视图")
    "orh" '(my/org-insert-heading-after :which-key "插入标题")
    "orH" '(my/org-insert-todo-heading :which-key "插入 TODO 标题")
    ;; ═════════════ 笔记 (n) ═════════════
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
