;;; keybindings.el --- 非模态全局键位与编辑习惯 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 提供不依赖 Evil 的全局快捷键层，目标是配合 Emacs 风格前缀键工作流：
;; - 结构化命令入口集中在 `prefix-keymaps.el` 定义的多前缀体系中
;; - 文本输入保持非模态，编辑区直接使用 Emacs buffer
;; - 光标移动补充 `C-h/j/k/l`，方向键继续保留
;; - 高频操作保留 IDE 风格直达键，减少模式切换成本
;;
;; 设计原则：
;; - `C-h/j/k/l` 只负责光标移动，不再依赖状态机
;; - 复制/剪切/粘贴、注释、重命名等行为统一走 DWIM 函数
;; - `cua-mode` 继续负责区域复制/粘贴语义，但不启用“选中即替换”
;; - which-key 底部菜单使用中文等宽网格布局，默认三列展示
;;
;; 高频直达键：
;; - `C-h/j/k/l`      左/下/上/右移动
;; - `C-s`            保存
;; - `C-f`            当前缓冲区搜索
;; - `C-p`            项目内找文件
;; - `C-S-f`          项目全文搜索
;; - `C-S-b`          切换缓冲区
;; - `C-z` / `C-S-z`  撤销 / 重做
;; - `C-a`            全选
;; - `C-/`            注释/取消注释
;; - `C-S-c`          智能复制
;; - `C-v`            粘贴
;; - `M-方向键`       切换窗口
;;
;; 常规 IDE 直达键：
;; - `C-S-x`          智能剪切（行/选区）
;; - `C-S-w`          关闭当前缓冲区
;; - `C-S-t`          重新打开最近文件
;; - `C-S-d`          复制当前行
;; - `C-S-<up>`       上移当前行
;; - `C-S-<down>`     下移当前行
;; - `C-<f12>`        跳转到定义
;; - `C-S-<f12>`      查找引用
;; - `C-S-i`          智能格式化
;; - `C-`` `          打开终端
;; - `C-S-/`          块注释
;; - `C-S-s`          另存为
;; - `C-S-a`          项目文件搜索

;;; Code:

;; 启用 CUA 模式
(cua-mode 1)

;; 禁用选中即替换行为
(setq cua-delete-selection nil)

;; which-key 中文菜单默认采用三列网格。
;; 宽屏可以升到 4，窄窗口则更适合降到 2。
(defconst custom:which-key-grid-columns 3
  "Which-key 中文菜单默认使用的固定网格列数。")

;; Which-key 默认按 `length' 计算描述补齐宽度，中文会导致列错位。
;; 这里统一改成基于 `string-width' 计算，并在底部多列布局下固定为等宽分栏。
(defun custom/which-key--fixed-grid-layout-p ()
  "判断当前是否启用固定多列 which-key 网格布局。"
  (and (boundp 'which-key-max-display-columns)
       (integerp which-key-max-display-columns)
       (> which-key-max-display-columns 1)
       (boundp 'which-key-popup-type)
       (eq which-key-popup-type 'side-window)
       (boundp 'which-key-side-window-location)
       (eq which-key-side-window-location 'bottom)))

(defun custom/which-key--target-grid-column-width (available-width)
  "根据 AVAILABLE-WIDTH 计算固定网格布局下每列的目标宽度。"
  (if (custom/which-key--fixed-grid-layout-p)
      (let* ((columns which-key-max-display-columns)
             (gaps (max 0 (1- columns))))
        (/ (max 1 (- available-width gaps)) columns))
    available-width))

(defun custom/which-key--pad-column-fixed-width (col-keys available-width)
  "为 COL-KEYS 生成更适合中文的 which-key 列布局。
AVAILABLE-WIDTH 为当前 which-key 可用宽度。"
  (let* ((grid-layout-p (custom/which-key--fixed-grid-layout-p))
         (col-key-width (+ which-key-add-column-padding
                           (which-key--max-len col-keys 0)))
         (col-sep-width (which-key--max-len col-keys 1))
         (target-col-width (custom/which-key--target-grid-column-width available-width))
         (desc-space (max 1 (- target-col-width col-key-width col-sep-width)))
         (col-desc-width (if grid-layout-p
                             desc-space
                           (max which-key-min-column-description-width desc-space)))
         (col-width (+ col-key-width col-sep-width col-desc-width))
         (col-format (concat "%" (int-to-string col-key-width) "s%s%s")))
    (cons col-width
          (mapcar
           (pcase-lambda (`(,key ,sep ,desc ,_doc))
             (let* ((display-desc (truncate-string-to-width
                                   desc col-desc-width 0 nil which-key-ellipsis))
                    (padding (max 0 (- col-desc-width (string-width display-desc)))))
               (concat
                (format col-format key sep display-desc)
                (make-string padding ?\s))))
           col-keys))))

;; Which-key（键位提示）
(use-package which-key
  :defer 0.3
  :config
  (which-key-mode 1)
  (setq which-key-idle-delay 0.3
        which-key-prefix-prefix ""
        which-key-allow-multiple-replacements t
        which-key-max-description-length 28
        ;; 中文条目在终端里更适合稳定的等宽分栏布局。
        ;; 默认三列；超宽屏可升到四列，窄窗口可降回两列。
        which-key-max-display-columns custom:which-key-grid-columns
        which-key-min-column-description-width 16
        which-key-add-column-padding 1
        which-key-min-display-lines 10
        which-key-side-window-max-height 0.38
        which-key-sort-order #'which-key-prefix-then-key-order
        which-key-C-h-map-prompt
        " \\<which-key-C-h-map>\\[which-key-show-next-page-cycle]/\\[which-key-show-previous-page-cycle] 翻页，\\[which-key-show-standard-help] 帮助，\\[which-key-abort] 退出")
  (advice-add 'which-key--pad-column :override #'custom/which-key--pad-column-fixed-width))

;; Helpful（更好的帮助系统）
(use-package helpful
  :defer t
  :bind (([remap describe-function] . helpful-callable)
         ([remap describe-command]  . helpful-command)
         ([remap describe-variable] . helpful-variable)
         ([remap describe-key]      . helpful-key)))

(defun custom/copy-dwim ()
  "智能复制。
有选区时复制选区，否则复制当前行。"
  (interactive)
  (cond
   ((use-region-p)
    (kill-ring-save (region-beginning) (region-end))
    (deactivate-mark)
    (message "已复制选区"))
   (t
    (kill-ring-save (line-beginning-position) (line-beginning-position 2))
    (message "已复制当前行"))))

(defun custom/paste-dwim (arg)
  "类似 VS Code 的粘贴。
若当前存在选区，则先用剪贴板覆盖选区。"
  (interactive "*P")
  (when (use-region-p)
    (delete-region (region-beginning) (region-end)))
  (cua-paste arg))

(defun custom/cut-dwim ()
  "智能剪切。
有选区时剪切选区，否则剪切当前行。"
  (interactive)
  (cond
   ((use-region-p)
    (kill-region (region-beginning) (region-end)))
   (t
    (kill-whole-line))))

(defun custom/select-all-dwim ()
  "全选当前缓冲区内容。"
  (interactive)
  (goto-char (point-min))
  (push-mark (point-max) nil t)
  (activate-mark))

(defun custom/comment-dwim-stable ()
  "稳定执行注释/取消注释。
优先处理 region，否则处理当前行。"
  (interactive)
  (if (use-region-p)
      (progn
        (comment-or-uncomment-region (region-beginning) (region-end))
        (deactivate-mark))
    (comment-line 1)))

(defun custom/rename-dwim ()
  "重命名符号或当前文件。"
  (interactive)
  (cond
   ((and (fboundp 'eglot-managed-p)
         (eglot-managed-p)
         (fboundp 'eglot-rename))
    (call-interactively #'eglot-rename))
   ((and buffer-file-name
         (fboundp 'rename-visited-file))
    (call-interactively #'rename-visited-file))
   (t
    (user-error "当前缓冲区不支持重命名"))))

(defun custom/reset-text-scale ()
  "重置当前缓冲区缩放级别。"
  (interactive)
  (text-scale-set 0))

;; 类 Vim 的光标移动，但保留 Emacs 非模态编辑体验
(global-set-key (kbd "C-h") #'backward-char)
(global-set-key (kbd "C-j") #'next-line)
(global-set-key (kbd "C-k") #'previous-line)
(global-set-key (kbd "C-l") #'forward-char)

;; 类 VS Code / IDE 快捷键
(global-set-key (kbd "C-z") #'undo)
(global-set-key (kbd "C-S-z") #'undo-redo)
(global-set-key (kbd "C-p") #'project-find-file)
(global-set-key (kbd "C-S-f") #'consult-ripgrep)
(global-set-key (kbd "C-S-b") #'consult-buffer)
(global-set-key (kbd "<C-tab>") #'custom/tabs-next)
(global-set-key (kbd "<C-iso-lefttab>") #'custom/tabs-previous)
(global-set-key (kbd "<C-S-tab>") #'custom/tabs-previous)
(global-set-key (kbd "<C-next>") #'custom/tabs-next)
(global-set-key (kbd "<C-prior>") #'custom/tabs-previous)

(global-set-key (kbd "C-a") #'custom/select-all-dwim)
(global-set-key (kbd "C-/") #'custom/comment-dwim-stable)
(global-set-key (kbd "C-_") #'custom/comment-dwim-stable)
(global-set-key (kbd "C-S-c") #'custom/copy-dwim)
(global-set-key (kbd "C-v") #'custom/paste-dwim)
(global-set-key (kbd "C-S-v") #'custom/paste-dwim)
(global-set-key (kbd "C-S-p") #'execute-extended-command)
(global-set-key (kbd "<f2>") #'custom/rename-dwim)
(global-set-key (kbd "C-=") #'text-scale-increase)
(global-set-key (kbd "C--") #'text-scale-decrease)
(global-set-key (kbd "C-0") #'custom/reset-text-scale)

;; 常规 IDE 直达键
(global-set-key (kbd "C-S-x") #'custom/cut-dwim)              ; 智能剪切（行/选区）
(global-set-key (kbd "C-S-w") #'kill-current-buffer)           ; 关闭当前缓冲区
(global-set-key (kbd "C-S-t") #'consult-recent-file)           ; 重新打开最近文件
(global-set-key (kbd "C-S-d") #'custom/code-duplicate-line)    ; 复制当前行
(global-set-key (kbd "C-S-<up>") #'custom/code-move-line-up)   ; 上移当前行
(global-set-key (kbd "C-S-<down>") #'custom/code-move-line-down) ; 下移当前行
(global-set-key (kbd "C-<f12>") #'custom/code-goto-definition)   ; 跳转到定义
(global-set-key (kbd "C-S-<f12>") #'custom/code-goto-references) ; 查找引用
(global-set-key (kbd "C-S-i") #'custom/code-format-dwim)       ; 智能格式化
(global-set-key (kbd "C-`") #'custom/open-terminal)             ; 打开终端
(global-set-key (kbd "C-S-/") #'custom/code-comment-block)     ; 块注释
(global-set-key (kbd "C-S-s") #'write-file)                    ; 另存为
(global-set-key (kbd "C-S-a") #'projectile-find-file)          ; 项目文件搜索

;; 覆盖 Emacs 默认快捷键
;; `C-s` 原本是 isearch-forward，这里改为保存；
;; 当前缓冲区搜索改由 `C-f` 触发。
(global-set-key (kbd "C-s") #'save-buffer)
(global-set-key (kbd "C-f") #'consult-line)

;; Alt + 方向键切换窗口（覆盖可能的其他绑定）
(windmove-default-keybindings 'meta)

(defun custom/workspace-windmove-left ()
  "在工作区中向左切换窗口，忽略 no-other-window 保护。"
  (interactive)
  (if-let ((win (window-in-direction 'left nil t)))
      (select-window win)
    (user-error "左侧没有可切换的窗口")))

(defun custom/workspace-windmove-right ()
  "在工作区中向右切换窗口，忽略 no-other-window 保护。"
  (interactive)
  (if-let ((win (window-in-direction 'right nil t)))
      (select-window win)
    (user-error "右侧没有可切换的窗口")))

(defun custom/workspace-windmove-up ()
  "在工作区中向上切换窗口，忽略 no-other-window 保护。"
  (interactive)
  (if-let ((win (window-in-direction 'up nil t)))
      (select-window win)
    (user-error "上方没有可切换的窗口")))

(defun custom/workspace-windmove-down ()
  "在工作区中向下切换窗口，忽略 no-other-window 保护。"
  (interactive)
  (if-let ((win (window-in-direction 'down nil t)))
      (select-window win)
    (user-error "下方没有可切换的窗口")))

(global-set-key (kbd "M-<left>") #'custom/workspace-windmove-left)
(global-set-key (kbd "M-<right>") #'custom/workspace-windmove-right)
(global-set-key (kbd "M-<up>") #'custom/workspace-windmove-up)
(global-set-key (kbd "M-<down>") #'custom/workspace-windmove-down)

(provide 'keybindings)
;;; keybindings.el ends here
