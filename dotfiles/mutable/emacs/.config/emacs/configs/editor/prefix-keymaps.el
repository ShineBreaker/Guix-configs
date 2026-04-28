;;; prefix-keymaps.el --- 前缀键绑定系统 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 本文件集中维护 Emacs 风格的前缀键绑定体系。
;;
;; 键位体系：
;; - `C-x`：文件、缓冲区、窗口、标签
;; - `C-x s`：选择、多光标与选区扩展
;; - `C-x p`：项目
;; - `M-s`：搜索
;; - `M-g`：跳转、错误与返回
;; - `C-c g`：Git
;; - `C-c t`：切换、工作区与工具面板
;; - `C-c l`：代码 / LSP
;; - `C-c e`：编辑变换
;; - `C-c z`：折叠
;; - `C-c o`：Org 扩展
;; - `C-c a`：应用
;; - `C-c h`：帮助（因为 `C-h` 保留给光标左移）
;; - `C-c d`：调试器
;; - `C-c u`：撤销可视化
;;
;; 延迟加载适配：
;; - tab-line: 标签栏改用 Emacs 内建实现，保证多 frame 隔离。
;; - apheleia: 显式 require 确保格式化时 alist 可用。
;; - 大部分命令仍保留按需加载行为，尽量不增加启动成本。
;;
;; 设计参考：
;; - 尽量使用 Emacs 现有前缀语义，而不是再造一个单一总前缀
;; - 保留 `C-h/j/k/l`、鼠标和若干 IDE 风格直达键
;; - 介绍与帮助页中优先使用中文分组名
;;
;; 【重要】修改快捷键时：
;; 1. 在本文件中修改键绑定，并同步 `configs/i18n/which-key-descriptions.el` 的中文说明
;; 2. F1 ? / C-c h ? 帮助页要同步更新
;; 3. Dashboard 只展示少量关键入口；新增功能体系时检查其是否需要出现在 dashboard
;;
;; 主要分组：
;; - `C-x` / `C-x s` / `C-x p` / `M-s` / `M-g`：Emacs 原生语义附近的操作区
;; - `C-c g` / `C-c t` / `C-c l` / `C-c e` / `C-c z`：自定义扩展区
;; - `C-c o` / `C-c a` / `C-c h`：Org、应用、帮助
;;
;; Updated: 2026-04-18 by daemon-optimization plan

;;; Code:

(defvar custom:language-format-buffer-functions nil)

(defun custom/code--apheleia-formatter-for-current-buffer ()
  "返回当前缓冲区可用的 Apheleia formatter。"
  (when (require 'apheleia nil t)
    (catch 'formatter
      (dolist (entry apheleia-mode-alist)
        (let ((key (car entry))
              (formatter (cdr entry)))
          (when (cond
                 ((symbolp key) (derived-mode-p key))
                 ((and (stringp key) buffer-file-name)
                  (string-match-p key buffer-file-name)))
            (throw 'formatter formatter))))
      nil)))

;; ═════════════════════════════════════════════════════════════════════════════
;; 代码操作函数
;; ═════════════════════════════════════════════════════════════════════════════

;; ───────────── 替换功能 ─────────────

(defun custom/code-replace-project ()
  "在项目范围内执行替换。"
  (interactive)
  (if-let ((proj (project-current nil)))
      (call-interactively #'project-query-replace-regexp)
    (message "当前不在项目中")
    (call-interactively #'query-replace-regexp)))

;; ───────────── 行操作 ─────────────

(defun custom/code-duplicate-line ()
  "复制当前行并在下方粘贴。"
  (interactive)
  (let ((column (current-column)))
    (move-beginning-of-line 1)
    (kill-line)
    (yank)
    (open-line 1)
    (forward-line 1)
    (yank)
    (move-to-column column)))

(defun custom/code-duplicate-line-above ()
  "复制当前行并在上方粘贴。"
  (interactive)
  (let ((column (current-column)))
    (move-beginning-of-line 1)
    (kill-line)
    (yank)
    (open-line 1)
    (yank)
    (move-to-column column)))

(defun custom/code-join-line ()
  "将当前行与下一行合并。"
  (interactive)
  (join-line -1))

(defun custom/code-move-line-up ()
  "将当前行上移一行。"
  (interactive)
  (transpose-lines 1)
  (forward-line -2))

(defun custom/code-move-line-down ()
  "将当前行下移一行。"
  (interactive)
  (forward-line 1)
  (transpose-lines 1)
  (forward-line -1))

;; ───────────── 注释操作 ─────────────

(defun custom/code-comment-line ()
  "注释/取消注释当前行。"
  (interactive)
  (save-excursion
    (comment-or-uncomment-region (line-beginning-position)
                                  (line-end-position))))

(defun custom/code-comment-dwim ()
  "智能注释：有选区则注释选区，否则注释当前行。"
  (interactive)
  (if (use-region-p)
      (comment-dwim nil)
    (custom/code-comment-line)))

(defun custom/code-comment-block ()
  "使用块注释包围选区。"
  (interactive)
  (if (use-region-p)
      (let ((comment-style 'multi-line))
        (comment-region (region-beginning) (region-end)))
    (message "请先选择要块注释的区域")))

;; ───────────── 格式化 ─────────────

(defun custom/code-format-dwim ()
  "智能格式化：有选区则格式化选区，否则格式化整个缓冲区。
优先使用 apheleia，其次 eglot，最后 indent-region。"
  (interactive)
  (if (use-region-p)
      (custom/code-format-region)
    (custom/code-format-buffer)))

(defun custom/code-format-region ()
  "格式化选中区域。
当前以 `indent-region' 为主，避免调用不存在的 Apheleia region API。"
  (interactive)
  (if (use-region-p)
      (indent-region (region-beginning) (region-end))
    (message "请先选择要格式化的区域")))

(defun custom/code-format-buffer ()
  "格式化整个缓冲区。
优先使用 apheleia-format-buffer，其次 eglot-format-buffer，最后 indent-region。"
  (interactive)
  (cond
   ((when-let ((formatter (alist-get major-mode custom:language-format-buffer-functions)))
      (call-interactively formatter)
      t))
   ((when-let ((formatter (custom/code--apheleia-formatter-for-current-buffer)))
      (apheleia-format-buffer formatter)
      t))
   ((and (fboundp 'eglot-managed-p) (eglot-managed-p))
    (eglot-format-buffer))
   (t
    (indent-region (point-min) (point-max)))))

(defun custom/code-indent-rigidly-right ()
  "将选中区域向右缩进一个 tab 宽度。"
  (interactive)
  (if (use-region-p)
      (indent-rigidly (region-beginning) (region-end) tab-width)
    (indent-rigidly (line-beginning-position) (line-end-position) tab-width)))

(defun custom/code-indent-rigidly-left ()
  "将选中区域向左缩进一个 tab 宽度。"
  (interactive)
  (if (use-region-p)
      (indent-rigidly (region-beginning) (region-end) (- tab-width))
    (indent-rigidly (line-beginning-position) (line-end-position) (- tab-width))))

;; ───────────── 包围操作 (Surround) ─────────────

(defun custom/code-surround-with (char)
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

(defun custom/code-wrap-parens ()
  "用圆括号包围选区。"
  (interactive)
  (custom/code-surround-with ?\())

(defun custom/code-wrap-brackets ()
  "用方括号包围选区。"
  (interactive)
  (custom/code-surround-with ?\[))

(defun custom/code-wrap-braces ()
  "用花括号包围选区。"
  (interactive)
  (custom/code-surround-with ?\{))

(defun custom/code-wrap-quotes ()
  "用双引号包围选区。"
  (interactive)
  (custom/code-surround-with ?\"))

(defun custom/code-wrap-single-quotes ()
  "用单引号包围选区。"
  (interactive)
  (custom/code-surround-with ?\'))

(defun custom/code-unwrap ()
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

(defun custom/code-action ()
  "执行代码操作（Code Action）。"
  (interactive)
  (if (fboundp 'eglot-code-actions)
      (call-interactively #'eglot-code-actions)
    (message "LSP 未启用")))

(defun custom/code-rename ()
  "重命名符号。"
  (interactive)
  (if (fboundp 'eglot-rename)
      (call-interactively #'eglot-rename)
    (message "LSP 未启用")))

(defun custom/code-goto-definition ()
  "跳转到定义。"
  (interactive)
  (call-interactively #'xref-find-definitions))

(defun custom/code-goto-references ()
  "查找所有引用。"
  (interactive)
  (call-interactively #'xref-find-references))

(defun custom/code-show-hover ()
  "显示光标下的符号信息（悬停提示）。"
  (interactive)
  (if (fboundp 'custom/eldoc-box-help-at-point)
      (custom/eldoc-box-help-at-point)
    (if (fboundp 'eglot-help-at-point)
        (eglot-help-at-point)
      (if (fboundp 'eldoc-doc-buffer)
          (eldoc-doc-buffer)
        (describe-thing-at-point)))))

(defun custom/code-quick-fix ()
  "快速修复当前问题。"
  (interactive)
  (if (fboundp 'eglot-code-action-quickfix)
      (eglot-code-action-quickfix)
    (custom/code-action)))

;; ───────────── 多光标/多选 ─────────────

(defun custom/code-mc-mark-next ()
  "选中下一个相同单词（类似 VSCode Ctrl+D）。"
  (interactive)
  (if (fboundp 'mc/mark-next-like-this)
      (mc/mark-next-like-this 1)
    (message "请先安装 multiple-cursors 包")))

(defun custom/code-mc-mark-previous ()
  "选中上一个相同单词。"
  (interactive)
  (if (fboundp 'mc/mark-previous-like-this)
      (mc/mark-previous-like-this 1)
    (message "请先安装 multiple-cursors 包")))

(defun custom/code-mc-mark-all ()
  "选中所有相同单词。"
  (interactive)
  (if (fboundp 'mc/mark-all-like-this)
      (mc/mark-all-like-this)
    (message "请先安装 multiple-cursors 包")))

(defun custom/code-mc-skip-next ()
  "跳过当前匹配，选中下一个。"
  (interactive)
  (if (fboundp 'mc/skip-to-next-like-this)
      (mc/skip-to-next-like-this)
    (message "请先安装 multiple-cursors 包")))

(defun custom/code-mc-skip-previous ()
  "跳过当前匹配，选中上一个。"
  (interactive)
  (if (fboundp 'mc/skip-to-previous-like-this)
      (mc/skip-to-previous-like-this)
    (message "请先安装 multiple-cursors 包")))

(defun custom/code-expand-selection ()
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

(defun custom/code-select-line ()
  "选中当前行。"
  (interactive)
  (end-of-line)
  (set-mark (line-beginning-position)))

(defun custom/code-select-block ()
  "选中当前代码块。"
  (interactive)
  (mark-defun))

(defvar custom/select-prefix-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'custom/code-mc-mark-next)
    (define-key map (kbd "p") #'custom/code-mc-mark-previous)
    (define-key map (kbd "a") #'custom/code-mc-mark-all)
    (define-key map (kbd "s") #'custom/code-mc-skip-next)
    (define-key map (kbd "S") #'custom/code-mc-skip-previous)
    (define-key map (kbd "l") #'custom/code-select-line)
    (define-key map (kbd "f") #'custom/code-select-block)
    (define-key map (kbd "e") #'custom/code-expand-selection)
    (define-key map (kbd "E") #'er/contract-region)
    map)
  "选择、多光标与选区扩展共用前缀键图。")

;; ───────────── 跳转与书签 ─────────────

(defun custom/code-jump-back ()
  "跳回之前的位置（后退）。"
  (interactive)
  (if (fboundp 'xref-go-back)
      (xref-go-back)
    (pop-mark)))

(defun custom/code-jump-forward ()
  "跳到下一个位置（前进）。"
  (interactive)
  (if (fboundp 'xref-go-forward)
      (xref-go-forward)
    (message "前进功能不可用")))

(defun custom/code-toggle-bookmark ()
  "切换当前行的书签。"
  (interactive)
  (if (fboundp 'bookmark-set)
      (call-interactively #'bookmark-set)
    (message "书签功能不可用")))

(defun custom/code-list-bookmarks ()
  "列出所有书签。"
  (interactive)
  (if (fboundp 'bookmark-bmenu-list)
      (bookmark-bmenu-list)
    (message "书签功能不可用")))

;; ───────────── 空行与清理 ─────────────

(defun custom/code-insert-empty-line-below ()
  "在当前行下方插入空行。"
  (interactive)
  (end-of-line)
  (newline))

(defun custom/code-insert-empty-line-above ()
  "在当前行上方插入空行。"
  (interactive)
  (beginning-of-line)
  (newline)
  (forward-line -1))

;; ───────────── 智能提示与补全 ─────────────

(defun custom/code-complete ()
  "触发代码补全。"
  (interactive)
  (if (fboundp 'completion-at-point)
      (completion-at-point)
    (if (fboundp 'company-complete)
        (company-complete)
      (hippie-expand nil))))

(defun custom/code-show-signature ()
  "显示函数签名。"
  (interactive)
  (eldoc-print-current-symbol-info))

(defun custom/toggle-minimap ()
  "切换代码小地图（仅 GUI）。"
  (interactive)
  (cond
   ((not (display-graphic-p))
    (message "代码小地图仅在 GUI 模式可用"))
   ((fboundp 'minimap-mode)
    (minimap-mode 'toggle))
   (t
    (message "未安装 minimap 包"))))

(defun custom/tabs-select-visible-tab (index)
  "跳转到当前可见标签中的 INDEX。"
  (interactive "n标签序号: ")
  (custom/tabs-select-index index))

(defun custom/tabs-close-current ()
  "关闭当前标签对应缓冲区。"
  (interactive)
  (custom/tabs-close-buffer))

;; ═════════════════════════════════════════════════════════════════════════════
;; Emacs 原生前缀扩展
;; ═════════════════════════════════════════════════════════════════════════════

;; C-x：文件、缓冲区、标签
(keymap-global-set "C-x C-r" #'consult-recent-file)
(keymap-global-set "C-x P" #'custom/pdf-open)
(keymap-global-set "C-x b" #'consult-buffer)
(keymap-global-set "C-x B" #'ibuffer)
(keymap-global-set "C-x k" #'kill-current-buffer)
(keymap-global-set "C-x K" #'kill-buffer)
(keymap-global-set "C-x t n" #'custom/tabs-next)
(keymap-global-set "C-x t p" #'custom/tabs-previous)
(keymap-global-set "C-x t g" #'custom/tabs-refresh-context)
(keymap-global-set "C-x t k" #'custom/tabs-close-current)
(keymap-global-set "C-x t 1" (lambda () (interactive) (custom/tabs-select-visible-tab 1)))
(keymap-global-set "C-x t 2" (lambda () (interactive) (custom/tabs-select-visible-tab 2)))
(keymap-global-set "C-x t 3" (lambda () (interactive) (custom/tabs-select-visible-tab 3)))
(keymap-global-set "C-x t 4" (lambda () (interactive) (custom/tabs-select-visible-tab 4)))
(keymap-global-set "C-x t 5" (lambda () (interactive) (custom/tabs-select-visible-tab 5)))

;; C-x p：项目
(keymap-global-set "C-x p p" #'custom/switch-project)
(keymap-global-set "C-x p f" #'project-find-file)
(keymap-global-set "C-x p s" #'consult-ripgrep)
(keymap-global-set "C-x p o" #'custom/open-project-folder)
(keymap-global-set "C-x p O" #'custom/open-directory)
(keymap-global-set "C-x p k" #'projectile-kill-buffers)

;; M-s：搜索
(keymap-global-set "M-s l" #'consult-line)
(keymap-global-set "M-s p" #'consult-ripgrep)
(keymap-global-set "M-s b" #'consult-buffer)
(keymap-global-set "M-s r" #'custom/code-replace-project)

;; M-g：跳转、错误
(keymap-global-set "M-g n" #'custom/flycheck-next-error)
(keymap-global-set "M-g p" #'custom/flycheck-previous-error)
(keymap-global-set "M-g l" #'custom/flycheck-list-errors-dwim)
(keymap-global-set "M-g r" #'custom/code-goto-references)
(keymap-global-set "M-g h" #'custom/code-show-hover)
(keymap-global-set "M-g b" #'custom/code-jump-back)
(keymap-global-set "M-g f" #'custom/code-jump-forward)
(keymap-global-set "M-," #'custom/code-jump-back)

;; C-c l：代码 / LSP
(keymap-global-set "C-c l d" #'custom/code-goto-definition)
(keymap-global-set "C-c l r" #'custom/code-goto-references)
(keymap-global-set "C-c l h" #'custom/code-show-hover)
(keymap-global-set "C-c l a" #'custom/code-action)
(keymap-global-set "C-c l q" #'custom/code-quick-fix)
(keymap-global-set "C-c l n" #'custom/code-rename)
(keymap-global-set "C-c l c" #'custom/code-complete)
(keymap-global-set "C-c l s" #'custom/code-show-signature)
(keymap-global-set "C-c l e" #'custom/flycheck-list-errors-dwim)
(keymap-global-set "C-c l t" #'custom/flycheck-toggle)
(keymap-global-set "C-c l g p" #'gdscript-godot-open-project-in-editor)
(keymap-global-set "C-c l g r" #'gdscript-godot-run-project)
(keymap-global-set "C-c l g R" #'gdscript-godot-run-project-debug)
(keymap-global-set "C-c l g s" #'gdscript-godot-run-current-scene)
(keymap-global-set "C-c l g S" #'gdscript-godot-run-current-scene-debug)
(keymap-global-set "C-c l g e" #'gdscript-godot-edit-current-scene)
(keymap-global-set "C-c l g x" #'gdscript-godot-run-current-script)
(keymap-global-set "C-c l g b" #'gdscript-docs-browse-symbol-at-point)

;; C-c l x：LSP 协议扩展（eglot-x）
;; 提供标准 LSP 之外的额外引用方法，对 Java（jdtls）尤其有用：
;; - declaration：跳转到声明（接口→声明，与"跳转到定义"互补）
;; - implementation：跳转到实现（接口→实现类）
;; - typeDefinition：跳转到类型定义（变量→类型声明）
;; 需要 eglot-x 包（emacs.scm），非 LSP buffer 调用时会安全报错。
(keymap-global-set "C-c l x d" #'eglot-find-declaration)
(keymap-global-set "C-c l x i" #'eglot-find-implementation)
(keymap-global-set "C-c l x t" #'eglot-find-typeDefinition)

;; C-c f：格式化
(keymap-global-set "C-c f f" #'custom/code-format-dwim)
(keymap-global-set "C-c f b" #'custom/code-format-buffer)
(keymap-global-set "C-c f r" #'custom/code-format-region)
(keymap-global-set "C-c f i" #'custom/code-indent-rigidly-right)
(keymap-global-set "C-c f I" #'custom/code-indent-rigidly-left)

;; C-c e：编辑变换
(keymap-global-set "C-c e l d" #'custom/code-duplicate-line)
(keymap-global-set "C-c e l a" #'custom/code-duplicate-line-above)
(keymap-global-set "C-c e l j" #'custom/code-join-line)
(keymap-global-set "C-c e l n" #'custom/code-move-line-down)
(keymap-global-set "C-c e l p" #'custom/code-move-line-up)
(keymap-global-set "C-c e l b" #'delete-blank-lines)
(keymap-global-set "C-c e l i" #'custom/code-insert-empty-line-below)
(keymap-global-set "C-c e l I" #'custom/code-insert-empty-line-above)
(keymap-global-set "C-c e c l" #'custom/code-comment-line)
(keymap-global-set "C-c e c d" #'custom/code-comment-dwim)
(keymap-global-set "C-c e c b" #'custom/code-comment-block)
(keymap-global-set "C-c e c c" #'comment-line)
(keymap-global-set "C-c e t u" #'upcase-word)
(keymap-global-set "C-c e t l" #'downcase-word)
(keymap-global-set "C-c e t c" #'capitalize-word)
(keymap-global-set "C-c e t t" #'transpose-chars)
(keymap-global-set "C-c e t w" #'transpose-words)
(keymap-global-set "C-c e t L" #'transpose-lines)
(keymap-global-set "C-c e s s" #'custom/code-surround-with)
(keymap-global-set "C-c e s (" #'custom/code-wrap-parens)
(keymap-global-set "C-c e s [" #'custom/code-wrap-brackets)
(keymap-global-set "C-c e s {" #'custom/code-wrap-braces)
(keymap-global-set "C-c e s \"" #'custom/code-wrap-quotes)
(keymap-global-set "C-c e s '" #'custom/code-wrap-single-quotes)
(keymap-global-set "C-c e s r" #'custom/code-unwrap)
(keymap-global-set "C-c e b t" #'custom/code-toggle-bookmark)
(keymap-global-set "C-c e b l" #'custom/code-list-bookmarks)

;; C-x s：选择、多光标与选区扩展
(global-set-key (kbd "C-x s") custom/select-prefix-map)

;; C-c z：折叠
(keymap-global-set "C-c z a" #'custom/code-fold-toggle)
(keymap-global-set "C-c z c" #'custom/code-fold-close)
(keymap-global-set "C-c z o" #'custom/code-fold-open)
(keymap-global-set "C-c z m" #'custom/code-fold-all)
(keymap-global-set "C-c z r" #'custom/code-unfold-all)

;; C-c g：Git
(keymap-global-set "C-c g s" #'custom/git-status-dwim)
(keymap-global-set "C-c g b" #'custom/git-blame-current-file)
(keymap-global-set "C-c g l" #'custom/git-log-current-file)
(keymap-global-set "C-c g d" #'custom/git-diff-current-file)
(keymap-global-set "C-c g t" #'custom/git-timemachine-toggle)
(keymap-global-set "C-c g S" #'custom/git-stage-current-file)
(keymap-global-set "C-c g D" #'custom/git-discard-current-file)
(keymap-global-set "C-c g P" #'custom/git-push-current-repo)
(keymap-global-set "C-c g F" #'custom/git-pull-current-repo)
(keymap-global-set "C-c g #" #'custom/git-stash-push)
(keymap-global-set "C-c g @" #'custom/git-stash-pop)

;; C-c t：切换、工作区与工具面板
(keymap-global-set "C-c t t" #'treemacs)
(keymap-global-set "C-c t r" #'custom/treemacs-reveal-current-file)
(keymap-global-set "C-c t d" #'custom/open-directory)
(keymap-global-set "C-c t v" #'custom/open-terminal)
(keymap-global-set "C-c t l" #'custom/toggle-workspace-layout)
(keymap-global-set "C-c t p" #'custom/pdf-toggle-themed-view)
(keymap-global-set "C-c t P" #'custom/pdf-fit-width)
(keymap-global-set "C-c t F" #'custom/format-on-save-toggle)
(keymap-global-set "C-c t c" #'custom/color-scheme-sync)
(keymap-global-set "C-c t h" #'custom/eldoc-box-toggle)
(keymap-global-set "C-c t m" #'custom/toggle-minimap)

;; C-c a：应用
(keymap-global-set "C-c a g t" #'tetris)
(keymap-global-set "C-c a g s" #'snake)
(keymap-global-set "C-c a g m" #'gomoku)
(keymap-global-set "C-c a g p" #'pong)
(keymap-global-set "C-c a g b" #'bubbles)
(keymap-global-set "C-c a g 2" #'2048-game)
(keymap-global-set "C-c a c" #'cfw:open-org-calendar)
(keymap-global-set "C-c a m" #'notmuch)

;; C-c o：Org 扩展
(keymap-global-set "C-c o a" #'org-agenda)
(keymap-global-set "C-c o b e" #'custom/org-babel-execute-current-block)
(keymap-global-set "C-c o b E" #'custom/org-babel-execute-all)
(keymap-global-set "C-c o b n" #'org-babel-next-src-block)
(keymap-global-set "C-c o b p" #'org-babel-previous-src-block)
(keymap-global-set "C-c o b t" #'custom/org-babel-tangle-current-block)
(keymap-global-set "C-c o b T" #'custom/org-babel-tangle-file)
(keymap-global-set "C-c o b g" #'custom/org-babel-goto-block)
(keymap-global-set "C-c o b d" #'custom/org-babel-demarcate-block)
(keymap-global-set "C-c o b '" #'custom/org-babel-edit-src-code)
(keymap-global-set "C-c o i" #'custom/org-insert-src-block)
(keymap-global-set "C-c o I" #'custom/org-insert-src-block-inline)
(keymap-global-set "C-c o r t" #'custom/org-todo-todo)
(keymap-global-set "C-c o r d" #'custom/org-todo-done)
(keymap-global-set "C-c o r a" #'custom/org-archive-subtree)
(keymap-global-set "C-c o r n" #'custom/org-narrow-to-subtree)
(keymap-global-set "C-c o r w" #'custom/org-widen)
(keymap-global-set "C-c o r h" #'custom/org-insert-heading-after)
(keymap-global-set "C-c o r H" #'custom/org-insert-todo-heading)
(keymap-global-set "C-c o n f" #'org-roam-node-find)
(keymap-global-set "C-c o n i" #'org-roam-node-insert)
(keymap-global-set "C-c o n l" #'org-roam-buffer-toggle)
;; C-c o k：知识库
(keymap-global-set "C-c o k c" #'custom/knowledge-capture)
(keymap-global-set "C-c o k s" #'custom/knowledge-search)
(keymap-global-set "C-c o k t" #'custom/knowledge-search-by-tag)
(keymap-global-set "C-c o k i" #'custom/knowledge-insert-relevant)
(keymap-global-set "C-c o k p" #'custom/knowledge-open-patterns)
(keymap-global-set "C-c o k I" #'custom/knowledge-open-index)

;; C-c h：帮助（因为 C-h 已保留给左移）
(keymap-global-set "C-c h f" #'helpful-callable)
(keymap-global-set "C-c h v" #'helpful-variable)
(keymap-global-set "C-c h k" #'helpful-key)
(keymap-global-set "C-c h m" #'describe-mode)
(keymap-global-set "C-c h ?" #'custom/show-help)

;; 额外别名
(keymap-global-set "C-c ] e" #'custom/flycheck-next-error)
(keymap-global-set "C-c [ e" #'custom/flycheck-previous-error)

;; Markdown 模式局部前缀
(with-eval-after-load 'markdown-mode
  (keymap-set markdown-mode-map "C-c p" #'markdown-preview))

(provide 'prefix-keymaps)
;;; prefix-keymaps.el ends here
