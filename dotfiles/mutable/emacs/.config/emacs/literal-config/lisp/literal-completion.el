;;; literal-completion.el --- 补全与搜索框架 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 配置 Vertico、Consult、Corfu 等现代补全框架，接管 minibuffer 与 in-region 补全，
;; 使 Emacs 不再回退到内置 *Completions* buffer（completion-list-mode）。
;;
;; 补全系统架构：
;; - Vertico: 垂直补全界面（替代 Ivy/Helm）
;; - Marginalia: 为补全项添加注释信息
;; - Orderless: 无序模糊匹配
;; - Consult: 增强的搜索和导航命令
;; - Embark: 上下文操作菜单
;; - Corfu: 代码补全弹窗（替代 Company）
;; - Cape: 为 CAPF 体系补充路径补全等额外来源
;; - corfu-popupinfo / corfu-doc: 补全弹窗中显示候选文档
;; - consult-eglot: 通过 Consult 搜索 Eglot 符号
;; - consult-flycheck: 通过 Consult 浏览 Flycheck 错误
;; - consult-dir: 在 minibuffer 中快速切换到项目/历史目录
;; - wgrep: 将 grep 结果导出后直接批量编辑并写回文件
;;
;; 自包含设计（遵循 lisp/AGENTS.md 插件化规范）：
;; 本模块不 require 任何 literal-* 模块。以下符号通过 defvar 注入点由 init.el
;; 提供真实实现；未注入时模块仍可加载，仅对应功能降级：
;;
;; 注入点 1（路径常量，AGENTS.md 机制 1，defvar 不覆盖已 bound 值）：
;;   - `literal:executable-aspell'   ← literal-bootstrap.el 的 defconst 自动生效
;;   - `literal:executable-hunspell' ← literal-bootstrap.el 的 defconst 自动生效
;;   未注入（nil）时：ispell 后端检测跳过，cape 补全不受影响。
;;
;; 注入点 2（frame 生命周期 hook）：
;;   - `literal/add-frame-hook' ← 直接 require 'literal-frame（见 ADR-0002），
;;     per-frame 的 GUI/终端 childframe 适配由 literal-frame 提供实现。
;;
;; 快捷键约定（与 literal-config 全局键位一致）：
;; - `C-s` 保留为保存，更贴近 Windows / IDE 常见习惯
;; - `C-f` 用于当前缓冲区搜索
;; - `M-s` 保留给搜索分组前缀
;; - `C-c m` 前缀分组挂补全相关命令（在 emacs.org 前缀键体系块注册）

;;; Code:

(require 'seq)
(require 'ispell)
(require 'literal-frame)

;; ═════════════════════════════════════════════════════════════════════════════
;; 注入点
;; ═════════════════════════════════════════════════════════════════════════════

(defvar literal:executable-aspell nil
  "aspell 可执行文件路径。由 literal-bootstrap.el 的 defconst 自动生效。
nil 时 ispell 后端检测跳过。")

(defvar literal:executable-hunspell nil
  "hunspell 可执行文件路径。由 literal-bootstrap.el 的 defconst 自动生效。
nil 时 ispell 后端检测跳过。")

;; frame hook 由 literal-frame.el 提供（顶部已 require），见 ADR-0002

;; ═════════════════════════════════════════════════════════════════════════════
;; savehist - 持久化 minibuffer 历史和 vertico 最后查询
;; ═════════════════════════════════════════════════════════════════════════════

(savehist-mode 1)

;; ═════════════════════════════════════════════════════════════════════════════
;; Vertico - 垂直补全界面
;; ═════════════════════════════════════════════════════════════════════════════

;; Vertico 提供简洁高效的垂直补全界面，接管 minibuffer 的 completing-read。
;; 启用后 Emacs 不再回退到内置 *Completions* buffer（completion-list-mode）。
(use-package vertico
  :custom
  ;; 显示更多候选 + 循环
  (vertico-count 12)
  (vertico-cycle t)
  :config
  (vertico-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Vertico Multiform - 按命令/补全类别切换 Vertico 形态
;; ═════════════════════════════════════════════════════════════════════════════
;;
;; vertico-multiform-mode 允许按 completing-read 命令或 completion category
;; 切换 Vertico 显示形态（vertical / buffer / flat / grid / unobtrusive 等），
;; 还能附带 keymap、sort function、buffer-local 设置。形态切换见
;; `vertico-multiform-map'：M-B buffer、M-F flat、M-G grid、M-U unobtrusive、
;; M-V vertical。
;;
;; 配置策略（参考 vertico README "Configuration per command"）：
;; - 大纲类（imenu / outline / bookmark）：indexed —— 候选前加 [1] [2] 数字
;;   索引，用 M-<数字> 快速跳转，比 minibuffer 一行行扫强得多
;; - M-x（execute-extended-command）：unobtrusive —— 不喧宾夺主
;; - file category：grid —— 文件名横排成多列，路径补全同时挂 directory-map
;;   的 RET/L 并行补全能力
;; - consult-grep category：indexed —— 搜索结果加数字索引便于跳转
;;
;; FIXME(Emacs 31 兼容性): vertico-buffer 形态在 Emacs 31 master +
;; Guix Emacs 30 编译的 vertico elc 下报
;;   `vertico-buffer--setup: Wrong type argument: symbolp'
;; 因为 Emacs 31 重构了 setq-local（基于新 set-local 函数，bug#80812），
;; 而 vertico-buffer 内部用的 buffer-local-set-state 宏在 30 编译的 elc
;; 里展开不兼容。上游追踪：minad/vertico#670。修复前所有原本想用 buffer
;; 的形态临时降级为 indexed。vertico 上游修复或 Guix 用 Emacs 31 重编译后
;; 可恢复 buffer 形态。

(use-package vertico-multiform
  :after vertico
  :config
  ;; 按命令定制形态
  (setq vertico-multiform-commands
        '((consult-imenu indexed)
          (consult-outline indexed)
          (consult-bookmark indexed)
          (consult-theme indexed)
          (execute-extended-command unobtrusive)))

  ;; 按补全类别定制形态
  (setq vertico-multiform-categories
        '((file grid (:keymap . vertico-directory-map))
          (consult-grep indexed)
          (imenu indexed)
          (bookmark indexed)
          (symbol (vertico-sort-function . vertico-sort-alpha))
          (library (vertico-sort-function . vertico-sort-alpha))))

  (vertico-multiform-mode 1))

;; ── Vertico Directory — minibuffer 内目录导航 ──
;; 在 file 补全中：RET 进入子目录、C-l 返回上级、DEL 删字符、M-DEL 删词。
;; vertico-multiform 已将 vertico-directory-map 挂到 grid file 形态，
;; 此处绑定到 vertico-map 覆盖所有文件补全场景。
(use-package vertico-directory
  :after vertico
  :bind (:map vertico-map
              ("RET" . vertico-directory-enter)
              ("DEL" . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word)
              ("C-l" . vertico-directory-up))
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

;; ── Vertico Quick — 单键跳转候选 ──
;; M-j 给每个候选分配单字母快捷鍵，一键跳转。
(use-package vertico-quick
  :after vertico
  :bind (:map vertico-map
              ("M-j" . vertico-quick-jump)
              ("M-J" . vertico-quick-exit)))

;; ── Vertico Repeat — 恢复上次补全会话 ──
;; M-R 恢复上次 minibuffer 会话状态。
(use-package vertico-repeat
  :after vertico
  :bind (:map vertico-map
              ("M-R" . vertico-repeat)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Prescient - 基于频率/最近使用的候选排序
;; ═════════════════════════════════════════════════════════════════════════════
;;
;; Prescient 维护一份本地候选历史，按使用频率 + 最近使用排序补全候选。
;; `vertico-prescient' / `corfu-prescient' 分别接入 Vertico minibuffer 与
;; Corfu in-region 补全。`prescient-persist-mode' 把状态存到
;; `prescient-save-file'，跨 session 保留排序记忆。

(use-package prescient
  :config
  (prescient-persist-mode 1))

(use-package vertico-prescient
  :after (vertico prescient)
  :config
  ;; vertico-sort-override-function 由 prescient 接管
  (vertico-prescient-mode 1))

(use-package corfu-prescient
  :after (corfu prescient)
  :config
  (corfu-prescient-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Marginalia - 补全注释
;; ═════════════════════════════════════════════════════════════════════════════

;; 为补全候选项添加有用的注释信息
;; 例如：命令显示快捷键，文件显示大小和修改时间
(use-package marginalia
  :config
  (marginalia-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Orderless - 无序补全
;; ═════════════════════════════════════════════════════════════════════════════

;; 支持空格分隔的无序模糊匹配
;; 例如：输入 "buf swi" 可以匹配 "switch-to-buffer"
(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Consult - 搜索与导航增强
;; ═════════════════════════════════════════════════════════════════════════════

;; Consult 提供增强的搜索、导航和预览功能。
;; 全局快捷键（consult-line / consult-buffer / consult-ripgrep 等）在
;; emacs.org 全局直达键 / 前缀键体系块注册，本块仅配置 use-package 本体。
(use-package consult
  :defer t
  :custom
  (xref-show-xrefs-function #'consult-xref)
  (xref-show-definitions-function #'consult-xref))

;; ═════════════════════════════════════════════════════════════════════════════
;; Embark - 上下文操作
;; ═════════════════════════════════════════════════════════════════════════════

;; Embark 提供类似右键菜单的上下文操作。
;; 全局键位（C-. embark-act / C-; embark-dwim）在 emacs.org 前缀键体系块注册。
(use-package embark
  :defer t
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

;; Embark 与 Consult 集成
(use-package embark-consult
  :after (embark consult)
  :defer t)

;; ═════════════════════════════════════════════════════════════════════════════
;; Consult-dir - Minibuffer 内目录切换
;; ═════════════════════════════════════════════════════════════════════════════

;; 在 find-file、write-file 等 minibuffer 场景中用 Consult 选择最近目录、
;; 项目目录或书签目录，减少手动输入路径。
;; 与 vertico 集成，:map vertico-map 挂 minibuffer 内目录跳转。
(use-package consult-dir
  :after consult
  :defer t
  :commands (consult-dir consult-dir-jump-file)
  :bind (("C-x C-d" . consult-dir)
         :map vertico-map
         ("C-x C-d" . consult-dir)
         ("C-x C-j" . consult-dir-jump-file)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Wgrep - 可编辑搜索结果
;; ═════════════════════════════════════════════════════════════════════════════

;; Consult + Embark 导出的 grep buffer 可以进入 wgrep，像编辑普通 buffer 一样
;; 批量修改搜索结果，再统一写回文件。
(use-package wgrep
  :defer t
  :commands (wgrep-change-to-wgrep-mode wgrep-finish-edit
             wgrep-abort-changes wgrep-save-all-buffers)
  :custom
  (wgrep-auto-save-buffer t)
  (wgrep-change-readonly-file t))

(with-eval-after-load 'grep
  (require 'wgrep)
  (keymap-set grep-mode-map "e" #'wgrep-change-to-wgrep-mode)
  (keymap-set grep-mode-map "C-c C-e" #'wgrep-change-to-wgrep-mode)
  ;; grep 输出按文件分节（Emacs 30+，与 rg --heading 风格一致）
  (when (boundp 'grep-use-headings)
    (setq grep-use-headings t)))

;; ═════════════════════════════════════════════════════════════════════════════
;; Corfu - 代码补全弹窗
;; ═════════════════════════════════════════════════════════════════════════════

;; ── ispell 词表发现（aspell/hunspell 走注入点）──
(defconst literal/completion:ispell-word-list-candidates
  (delq nil
        (list (and (getenv "GUIX_PROFILE")
                   (expand-file-name "share/dict/words" (getenv "GUIX_PROFILE")))
              (expand-file-name "~/.guix-home/profile/share/dict/words")
              (expand-file-name "~/.guix-profile/share/dict/words")
              "/run/current-system/profile/share/dict/words"
              "/usr/share/dict/words"
              "/usr/share/dict/web2"))
  "候选 plain word list 路径。`miscfiles' 通常提供 share/dict/words。")

(defvar literal/completion--ispell-word-list nil
  "已发现的 plain word list 文件。nil 表示尚未找到。")

(defun literal/completion-ispell-find-word-list ()
  "返回可用于 `ispell-alternate-dictionary' 的 plain word list 文件。"
  (or literal/completion--ispell-word-list
      (setq literal/completion--ispell-word-list
            (seq-find #'file-readable-p literal/completion:ispell-word-list-candidates))))

(defun literal/completion-setup-ispell-program ()
  "配置可用的 ispell 后端命令。
aspell / hunspell 路径走 `literal:executable-aspell' / `literal:executable-hunspell'
注入点（由 literal-bootstrap.el defconst 自动生效）。两者均 nil 时为 no-op。"
  (when-let* ((program (or literal:executable-aspell
                           literal:executable-hunspell)))
    (setq ispell-program-name program)
    (when literal:executable-aspell
      (setq ispell-extra-args '("--sug-mode=ultra")))))

(defun literal/completion-remove-ispell-completion-at-point ()
  "从当前 buffer 的 CAPF 列表移除 `ispell-completion-at-point'。"
  (setq-local completion-at-point-functions
              (remove 'ispell-completion-at-point
                      (remove #'ispell-completion-at-point
                              completion-at-point-functions))))

(defun literal/completion-setup-ispell-word-list ()
  "为当前 buffer 配置单词补全词表。

若找不到 plain word list，则移除当前 buffer 的
`ispell-completion-at-point'，避免 Corfu 自动补全触发缺词表错误。"
  (let ((word-list (literal/completion-ispell-find-word-list)))
    (if word-list
        (setq-local ispell-alternate-dictionary word-list)
      (literal/completion-remove-ispell-completion-at-point))))

(literal/completion-setup-ispell-program)

(add-hook 'text-mode-hook #'literal/completion-setup-ispell-word-list)
(add-hook 'org-mode-hook #'literal/completion-setup-ispell-word-list)
(add-hook 'git-commit-setup-hook #'literal/completion-setup-ispell-word-list)

;; ── Corfu 本体 ──
;; Corfu 提供轻量级的代码补全界面，接管 in-region 补全（替代 *Completions* 回退）。
;; 延迟 0.2 秒加载以加速启动
;;
;; 配置说明：
;; - corfu-auto: 自动弹出补全
;; - corfu-auto-prefix: 输入几个字符后触发补全
;; - corfu-quit-no-match: 无匹配时的行为
;; - corfu-cycle: 循环选择候选项
(use-package corfu
  :defer 0.2
  :bind (:map corfu-map
              ("TAB" . corfu-insert)
              ("<tab>" . corfu-insert))
  :custom
  (corfu-auto t)                      ; 自动补全
  (corfu-auto-prefix 2)               ; 输入 2 个字符后触发
  (corfu-quit-no-match 'separator)    ; 无匹配时保留输入
  (corfu-cycle t)                     ; 循环选择
  :config
  (global-corfu-mode 1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Cape - 为 CAPF 增强路径补全
;; ═════════════════════════════════════════════════════════════════════════════

;; Cape 提供 Completion-At-Point 扩展后端（CAPF），与 Corfu 的 in-region 补全
;; 完全兼容。各 capf 通过 buffer-local 追加到 `completion-at-point-functions'，
;; 排在已有 major-mode / LSP capf 之后兜底。
;;
;; 可用 capf 清单（cape 2.7）：
;; - cape-dabbrev: 当前 buffer 内动态缩写展开（覆盖旧 cape-symbol 功能）
;; - cape-file:    字符串内路径补全
;; - cape-history: 当前 minibuffer/region 历史回填
;; - cape-keyword: 编程语言关键字补全（仅 prog-mode 有意义）
;; - cape-line:    当前 buffer 内整行近似补全（性能略重，单独控制）
;; - cape-tex:     LaTeX 数学符号补全（按需）
;;
;; 按模式分组配置 capf，避免 LSP 管理的 prog-mode 被无关 capf 干扰。

(use-package cape
  :defer t
  :commands (cape-dabbrev cape-file cape-history cape-keyword cape-line))

(defun literal/completion-cape-add-capfs (capfs)
  "把 CAPFS（符号列表）追加到当前 buffer 的 `completion-at-point-functions'。
每个 capf 仅在已 fboundp 时追加，避免 cape 版本差异导致报错。"
  (dolist (capf capfs)
    (when (fboundp capf)
      (add-hook 'completion-at-point-functions capf t t))))

(defun literal/completion-setup-cape-org ()
  "Org mode 的 cape capf 组合：只保留 file（路径补全）。
由于 org-mode 是 text-mode 的衍生模式，`text-mode-hook' 会先运行并插入
cape-dabbrev / cape-line；因此本函数先移除这两个 capf，再追加 cape-file，
避免普通写作中弹出大量无关缩写和整行候选。org 自身关键字 / 链接 / roam
补全仍保留。

同时关闭 Org buffer 的 corfu-auto（手动 M-Tab 仍可用），减少写作干扰。"
  (setq-local completion-at-point-functions
              (remove #'cape-line
                      (remove 'cape-line
                              (remove #'cape-dabbrev
                                      (remove 'cape-dabbrev
                                              completion-at-point-functions)))))
  (literal/completion-cape-add-capfs '(cape-file))
  (when (boundp 'corfu-auto)
    (setq-local corfu-auto nil)))

(defun literal/completion-setup-cape-text ()
  "文本类 buffer（text/conf）的 cape capf 组合：
dabbrev（缩写展开）+ file（路径）+ line（行近似）。
ispell 拼写补全由 `literal/completion-setup-ispell-word-list' 单独管理
（在找到 word list 时保留 Emacs 自带的 `ispell-completion-at-point'）。"
  (literal/completion-cape-add-capfs '(cape-dabbrev cape-file cape-line)))

(defun literal/completion-setup-cape-prog ()
  "编程类 buffer 的 cape capf 组合：
dabbrev + keyword（关键字）+ file（路径）。
不挂 cape-line，避免大 buffer 拖慢 LSP 补全响应。"
  (literal/completion-cape-add-capfs '(cape-dabbrev cape-keyword cape-file)))

(add-hook 'prog-mode-hook #'literal/completion-setup-cape-prog)
(add-hook 'conf-mode-hook #'literal/completion-setup-cape-prog)
(add-hook 'text-mode-hook #'literal/completion-setup-cape-text)
(add-hook 'org-mode-hook #'literal/completion-setup-cape-org)

(with-eval-after-load 'eglot
  (add-hook 'eglot-managed-mode-hook #'literal/completion-setup-cape-prog))

;; ═════════════════════════════════════════════════════════════════════════════
;; Corfu 文档预览 - 在补全弹窗旁边显示候选文档
;; ═════════════════════════════════════════════════════════════════════════════

;; corfu-popupinfo 在补全弹窗旁显示文档详细信息
;; 默认不自动显示文档；仅通过显式动作（如 M-d）打开
(use-package corfu-popupinfo
  :after corfu
  :bind (:map corfu-map
              ("M-d" . corfu-popupinfo-toggle))
  :custom
  (corfu-popupinfo-delay 0.5)
  :config
  ;; JetBrains 风格：默认仅显示候选列表，文档按需手动打开
  (corfu-popupinfo-mode -1))

;; ═════════════════════════════════════════════════════════════════════════════
;; Kind-icon - 补全图标
;; ═════════════════════════════════════════════════════════════════════════════

;; 为补全候选项添加图标（仅 GUI 模式）
;; 图标可以直观显示候选项类型（函数、变量、类等）
(use-package kind-icon
  :commands (kind-icon-margin-formatter)
  :init
  (setq kind-icon-default-face 'corfu-default))

;; 终端模式下使用 Nerd Font 文字图标作为补全类型标记
;; 定义部分（无 display 依赖，可安全放在顶层）
(defvar literal/completion--corfu-terminal-kind-icons
  '((file . "󰈔") (folder . "󰉋") (function . "󰊕") (variable . "󰀫")
    (module . "󰏗") (interface . "󰡧") (keyword . "󰌋") (method . "󰊕")
    (property . "󰜢") (unit . "󰑘") (value . "󰎠") (enum . "󰕘")
    (operator . "󰆕") (class . "󰌗") (struct . "󰌗") (type-parameter . "󰊄")
    (snippet . "󰘍") (color . "󰏘") (reference . "󰈇") (text . "󰉿")
    (event . "󰉁") (constant . "󰏿") (enum-member . "󰀬")
    (t . "󰀫"))
  "补全类型到 Nerd Font 图标的映射表。")

(defun literal/completion--corfu-terminal-margin-formatter (metadata)
  "终端模式下使用 Nerd Font 图标格式化 Corfu 边距。"
  (let* ((kind (or (completion-metadata-get metadata 'company-kind)
                   (completion-metadata-get metadata 'kind)))
         (icons literal/completion--corfu-terminal-kind-icons))
    (lambda (candidate)
      (let* ((kind-sym (and kind (funcall kind candidate)))
             (kind-item (or kind-sym t))
             (icon (or (cdr (assq kind-item icons)) (cdr (assq t icons)))))
        (propertize (concat " " icon " ") 'face 'corfu-default)))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Corfu-doc - 补全文档弹窗
;; ═════════════════════════════════════════════════════════════════════════════

;; 在 Corfu 补全弹窗旁显示当前候选的文档字符串
;; GUI 模式使用 corfu-doc childframe，终端使用 corfu-doc-terminal
(use-package corfu-doc
  :after corfu
  :defer t
  :commands (corfu-doc-mode corfu-doc-toggle)
  :bind (:map corfu-map
              ("M-d" . corfu-doc-toggle)
              ("C-M-n" . corfu-doc-scroll-up)
              ("C-M-p" . corfu-doc-scroll-down))
  :custom
  (corfu-doc-max-width 70)
  (corfu-doc-max-height 20)
  :config
  ;; 默认关闭，按 M-d 手动切换（JetBrains 风格）
  (corfu-doc-mode -1))

;; 终端下 corfu-doc 的适配层
(use-package corfu-doc-terminal
  :after corfu-doc
  :defer t)

;; ═════════════════════════════════════════════════════════════════════════════
;; Consult-eglot - Eglot 符号搜索
;; ═════════════════════════════════════════════════════════════════════════════

;; 通过 Consult 界面搜索 Eglot/LSP 管理的项目符号
(use-package consult-eglot
  :defer t
  :commands (consult-eglot-symbols))

;; ═════════════════════════════════════════════════════════════════════════════
;; Consult-flycheck - Flycheck 错误浏览
;; ═════════════════════════════════════════════════════════════════════════════

;; 通过 Consult 界面浏览和跳转 Flycheck 诊断
(use-package consult-flycheck
  :defer t
  :commands (consult-flycheck))

;; ═════════════════════════════════════════════════════════════════════════════
;; Per-frame 补全显示设置（daemon 安全，走 frame-hook 注入点）
;; ═════════════════════════════════════════════════════════════════════════════

(defun literal/completion-setup-display (&optional frame)
  "根据 FRAME 的 display 类型设置补全框架的显示相关配置。
GUI 模式：应用 PGTK childframe 修复 + kind-icon 图标。
终端模式：启用 corfu-terminal 和 Nerd Font 图标。

frame hook 由 literal-frame.el 提供（顶部已 require）。"
  (with-selected-frame (or frame (selected-frame))
    (with-eval-after-load 'corfu
      (if (display-graphic-p)
          (progn
            ;; GUI: PGTK/Wayland 修复——childframe 位置偏移
            (when (boundp 'x-gtk-resize-child-frames)
              (setq x-gtk-resize-child-frames 'resize-mode))
            (when (bound-and-true-p corfu-terminal-mode)
              (corfu-terminal-mode -1))
            (require 'kind-icon)
            (setq corfu-margin-formatters '(kind-icon-margin-formatter)))
        ;; 终端: corfu-terminal + Nerd Font 图标
        (require 'corfu-terminal)
        (corfu-terminal-mode 1)
        (setq corfu-margin-formatters
              '(literal/completion--corfu-terminal-margin-formatter))))))

;; 注册到 frame 生命周期（literal-frame.el 提供 add-frame-hook）
(literal/add-frame-hook #'literal/completion-setup-display)

(provide 'literal-completion)
;;; literal-completion.el ends here
