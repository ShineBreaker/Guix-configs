# Emacs 键位 / leader-key / which-key / UI / workspaces 范式研究

> 研究范围: `/home/brokenshine/Projects/Emacs/{doomemacs,spacemacs}` 两个 starter kit
> 截止代码: doomemacs (HEAD), spacemacs (HEAD, 2025)
> 关注点: 键位/leader-key/which-key/UI/workspaces 五位一体的统一与可扩展范式

---

## 0. 阅读地图

| 章节                        | 主要代码引用                                                                                                      |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| 1. leader-key 设计哲学      | `doom-keybinds.el:11-29` · `core-keybindings.el:67-86` · `core-keybindings.el:88-126`                             |
| 2. `map!` 宏范式            | `doom-keybinds.el:300-484` · `doom-keybinds.el:333-340` · `+emacs-bindings.el:22-99`                              |
| 3. which-key 集成与可发现性 | `doom-keybinds.el:235-256` · `doom-keybinds.el:169-185`                                                           |
| 4. workspaces 范式          | `workspaces/config.el:1-256` · `workspaces/autoload/workspaces.el:1-200` · `spacemacs-layouts/packages.el:36-115` |
| 5. popup / childframe       | `popup/config.el:9-184` · `popup/autoload/settings.el:41-180` · `popup/autoload/popup.el:380-554`                 |
| 6. modeline                 | `modeline/config.el:1-55` · `modeline/+light.el:115-260` · `spacemacs-modeline/packages.el:24-50`                 |
| 7. 主题切换                 | `doom-ui.el:202-281` · `lib/themes.el:1-77` · `core-themes-support.el:271-321`                                    |
| 8. 高频操作可发现性         | `doom-keybinds.el:169-185` · `spacemacs-navigation/packages.el:9-105` · `spacemacs-layouts/packages.el:36-115`    |
| 9. 键位冲突诊断             | `doom-keybinds.el:137-140` · `doom-keybinds.el:144-185`                                                           |

---

## 1. leader-key 设计哲学

### 1.1 五种主流 leader-key 风格对比

| #   | 风格                        | 代表                                                                                              | 优点                                                         | 缺点                                                                                               | 适用场景                                    |
| --- | --------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| 1   | **SPC 全局 + `SPC m` 局部** | Doom Emacs (`doom-keybinds.el:11-22`)                                                             | 双层嵌套稳定，物理键位置零冲突；evil 用户 muscle memory 友好 | SPC 与 `C-/`, `C-x`, 临时键冲突需用 `doom-init-input-decode-map-h` 修复 (`doom-keybinds.el:64-86`) | 大型配置、evil 用户、模块化项目             |
| 2   | **M-m 全局 + `M-m m` 局部** | Spacemacs (`core-keybindings.el:67-79`)                                                           | 物理键位置更舒适（home row），不会被 TUI/系统快捷键截走      | 小拇指负担；emacs state 下要按 `C-c C-c` 触发；新用户难发现 `M-m`                                  | 偏爱 `M-` 前缀、不开 evil-collection 的用户 |
| 3   | **C-c / C-x 经典**          | Vanilla Emacs · Doom 非 evil 模式 (`+emacs-bindings.el:22` 中 `(setq doom-leader-alt-key "C-c")`) | 100% 兼容 vanilla，预测性强                                  | `C-c <letter>` 已被 `mode-specific-map` 占用 → 只能绑定组合键                                      | 非 evil 用户、追求最大兼容性                |
| 4   | **F1 / F2 / F5 等功能键**   | 旧 IDE 用户迁移                                                                                   | 完全不与文本输入冲突                                         | 离 home row 远；与系统/终端快捷键冲突                                                              | 笔记本、tty、hyprland 等可能拦截 SPC 的环境 |
| 5   | **逗号 / 分号**             | Spacemacs dotfile 选项 `dotspacemacs-leader-key ","`                                              | 离 home row 最近                                             | 与原生 `M-,` (tags-loop-continue) 等命令冲突                                                       | 个人偏好 + 没有 `:editor evil` 限制         |

### 1.2 Doom 的双层 leader 体系（详细）

`doom-keybinds.el:11-29` 定义四个关键变量：

```elisp
(defvar doom-leader-key "SPC"              ; evil 用户的 leader
(defvar doom-leader-alt-key "M-SPC"        ; insert/emacs 状态的 leader
(defvar doom-leader-key-states '(normal visual motion)
(defvar doom-leader-alt-key-states '(emacs insert)
(defvar doom-localleader-key "SPC m"       ; 模式专属 leader，evil
(defvar doom-localleader-alt-key "M-SPC m" ; 模式专属 leader，非 evil
```

`doom-keybinds.el:188-202` 中通过 `doom-after-init-hook` 延迟绑定：

```elisp
(add-hook! 'doom-after-init-hook
  (defun doom-init-leader-keys-h ()
    (let ((map general-override-mode-map))
      (if (not (featurep 'evil))
          (progn
            (cond ((equal doom-leader-alt-key "C-c")
                   (set-keymap-parent doom-leader-map mode-specific-map))
                  ((equal doom-leader-alt-key "C-x")
                   (set-keymap-parent doom-leader-map ctl-x-map)))
            (define-key map (kbd doom-leader-alt-key) 'doom/leader))
        (evil-define-key* doom-leader-key-states map (kbd doom-leader-key) 'doom/leader)
        (evil-define-key* doom-leader-alt-key-states map (kbd doom-leader-alt-key) 'doom/leader))
      (general-override-mode +1))))
```

**关键设计点**:

- **延迟到 `doom-after-init-hook`**：允许用户配置文件覆盖 `doom-leader-key` 变量
- **两种状态分离**：normal/visual/motion 用 SPC，insert/emacs 用 M-SPC → evil 用户写 org 时不会被拦截
- **prefix command 模式替代 `general` 的 `:prefix` 属性**：`doom-keybinds.el:185-186` 注释说明 `:prefix/:non-normal-prefix` 组合让 `general.el` 启动慢一倍 → 改用 `define-prefix-command`
- **`general-override-mode`**：让 `doom/leader` 优先级最高，覆盖 minor mode

### 1.3 Spacemacs 的双层 leader 体系（详细）

`core-keybindings.el:67-79`：

```elisp
(defun spacemacs/declare-prefix (prefix name &rest more)
  "Declare a prefix PREFIX. PREFIX is a string describing a key
sequence. NAME is a string used as the prefix command."
  (apply #'which-key-add-keymap-based-replacements spacemacs-default-map
    prefix name more))
```

**关键差异**:

- `spacemacs-default-map` 单一 keymap；同时被 evil-leader 和 emacs-leader 共享（通过 `dotspacemacs-leader-key` 和 `dotspacemacs-emacs-leader-key`）
- 使用 `bind-map` 包实现 prefix isolation（`core-keybindings.el:88-126`）
- 模式专属 leader 通过 `(spacemacs//init-leader-mode-map mode smap is-minor-mode-prefix)` 自动创建 keymap

### 1.4 选型决策树

```
你是 evil 用户吗？
├── 是
│   ├── 桌面 / 笔记本，SPC 不被系统拦截 → 风格 1（Doom 风格）
│   ├── 在终端 / hyprland / tty 经常用 → 风格 4（F1/F2）或风格 1 + 修 `:os tty` 模块
│   └── 想最大化物理键效率 → 风格 2（Spacemacs 风格）
└── 不是
    ├── 想保留 vanilla 兼容 → 风格 3（C-c）
    └── 想要全功能键位生态 → 风格 1 + `M-SPC` 退路（Doom `M-SPC`）
```

**反模式**:

- 同时把 `SPC` 和 `C-c` 当 leader（doom 用了 `C-c` 就放弃 `SPC`，见 `+emacs-bindings.el:22`）
- 选功能键但用 SPC 风格菜单（`SPC` 风格的"层级"假设物理位置在拇指能扫到的地方）
- 在 evil 模式却把 leader 放在 `C-c <letter>` 单字母（与 `mode-specific-map` 冲突）

---

## 2. `map!` 宏的范式创新

### 2.1 `map!` 设计哲学

`doom-keybinds.el:464-484`（docstring）：

> A convenience macro for defining keybinds, powered by `general`. If evil isn't loaded, evil-specific bindings are ignored.

**核心目标**: 在不写两次（evil vs emacs）的前提下，写一次"逻辑意图" → 编译期分发到正确 keymap。

**对应源码段**（`doom-keybinds.el:300-484`）由以下子过程组成：

- `doom--map-process` (`:300-340`)：顶层 dispatcher，扫描 keyword → 分发到 `doom--map-def` / `doom--map-nested` / `doom--map-set`
- `doom--map-keyword-to-states` (`:289-296`)：把 `:nvi` → `(normal visual insert)`
- `doom--map-def` (`:373-394`)：把 `(KEY DEF STATES DESC)` 编译成 `general-define-key` 调用
- `doom--map-set` (`:367-371`)：commit 已 batched forms 到 macroexp output
- `doom-evil-state-alist` (`:283-287`)：单字母 → evil state symbol

### 2.2 10 个最常用模式

#### 模式 1: 基础 leader 绑定 + 描述

`+emacs-bindings.el:22-28`：

```elisp
(map! :leader
      :desc "Evaluate line/region"        "e"   #'+eval/line-or-region
      ...)
```

**关键点**:

- `:desc` 出现在 `:leader` 之后但在 key 之前 → doom 的 parser 用 `desc` 变量贯穿后续 `doom--map-def` 调用 (`doom-keybinds.el:319-322`)
- `:desc` 字符串进 which-key 替代默认 symbol-name

#### 模式 2: 嵌套 prefix-map（最有特色的范式）

`+emacs-bindings.el:30-100`：

```elisp
(:prefix-map ("c" . "code")            ; 创建新 prefix "c"（标 "code"）
 :desc "Compile"        "c"   #'compile
 :desc "Recompile"      "C"   #'recompile
 ...
 (:when (modulep! :tools lsp -eglot)   ; 嵌套条件
  :desc "LSP Code actions" "a" #'lsp-execute-code-action
  ...))
```

**实现机制**（`doom-keybinds.el:329-337`）：

```elisp
(:prefix-map
 (cl-destructuring-bind (prefix . desc)
     (let ((arg (pop rest)))
       (if (consp arg) arg (list arg)))
   (let ((keymap (intern (format "doom-leader-%s-map" desc))))
     (setq rest
           (append (list :desc desc prefix keymap
                         :prefix prefix)
                   rest))
     (push `(defvar ,keymap (make-sparse-keymap))
           doom--map-forms))))
```

**关键点**:

- `(:prefix-map ("c" . "code") ...)` 自动生成 `doom-leader-code-map` 变量（在 output 前面）
- 内层所有键位自动获得 `:prefix "c"`，实现 `<leader> c ...` 嵌套
- `:desc "code"` 同时进 which-key，**比手工写 `(define-prefix-command ...)` 少 3-4 倍代码**

**注意**：`+emacs-bindings.el:30` 的 docstring 警告 `DO NOT USE THIS IN YOUR PRIVATE CONFIG`（指运行时定义会污染 autoload 顺序）→ 用户配置用普通 `:prefix` 即可

#### 模式 3: 单 prefix + 描述

`+emacs-bindings.el:31`：

```elisp
(:prefix ("l" . "<localleader>") ; bound locally
```

区别于 `:prefix-map`：不创建独立 keymap，直接在 `doom-leader-map` 下加 prefix。`doom-keybinds.el:340-348` 实现。

#### 模式 4: 条件化绑定（`:when` / `:unless`）

`+emacs-bindings.el:50-70`：

```elisp
(:when (modulep! :tools lsp -eglot)
 :desc "LSP Code actions"           "a"   #'lsp-execute-code-action
 ...)
```

`doom-keybinds.el:327-328`：

```elisp
((or :when :unless)
 (doom--map-nested (list (intern (doom-keyword-name key)) (pop rest)) rest)
 (setq rest nil))
```

**注意**：`:when` 必须用**列表**包裹（用 `(:when cond body...)`），不能用 keyword 形式 `:when cond` —— 这是 macro 实现里 `(pop rest)` 的限制。

#### 模式 5: 模式专属 (`:mode` → 自动生成 `-map` symbol)

`+emacs-bindings.el` 风格 + `doom-keybinds.el:323-326`：

```elisp
(:mode magit-mode
 :n "q" #'magit-mode-bury-buffer)
```

编译为 `(:map (magit-mode-map) :n "q" ...)`，自动添加 `-map` 后缀。

#### 模式 6: 显式 keymap

`completion/helm/config.el:110-112`：

```elisp
(map! :map helm-rg-map "C-S-s" #'something)
(map! :map (helm-rg-map helm-rg--bounce-mode-map) ...)`)
```

支持单个 keymap 或 keymap 列表。`doom-keybinds.el:322`：

```elisp
(:map
 (doom--map-set :keymaps `(backquote ,(ensure-list (pop rest)))))
```

#### 模式 7: 状态限定（evil state 单字符）

`evil/config.el:484`：

```elisp
(map! :v  "@"     #'+evil:apply-macro
      :m  [C-i]   #'evil-jump-forward)
```

字母对照（`doom-keybinds.el:283-287`）：

- `:n` normal · `:v` visual · `:i` insert · `:e` emacs · `:o` operator · `:m` motion · `:r` replace · `:g` global

**注意**：`:g` 含义是 "无 evil `current-global-map`" —— 用于 vim 风格全局动作。`:n` 缺省 = 写 normal/visual/motion/emacs 四态。`doom-keybinds.el:374-376` 处理：`global` 状态自动加 `nil` 状态进 batch。

**重要顺序**（`+emacs-bindings.el:340-348` docstring）：

> Do: `(map! :leader :desc "..." :n "C-c" #'dosomething)`
> Don't: `(map! :n :leader :desc "..." "C-c" #'dosomething)` —— 状态必须在 key 前

#### 模式 8: 延迟到 feature 加载后绑定

`config/default/config.el:228-229`：

```elisp
(map! :map markdown-mode-map :ig "*" fn)
(map! :after markdown-ts-mode :map markdown-ts-mode-map :ig "*" fn)
```

`doom-keybinds.el:317-319`：

```elisp
(:after
 (doom--map-nested (list 'after! (pop rest)) rest)
 (setq rest nil))
```

编译为 `(after! markdown-ts-mode (map! ...))`。

#### 模式 9: text object（vim style）

`doom-keybinds.el:337-343`：

```elisp
(:textobj
 (let* ((key (pop rest))
        (inner (pop rest))
        (outer (pop rest)))
   (push `(map! (:map evil-inner-text-objects-map ,key ,inner)
                (:map evil-outer-text-objects-map ,key ,outer))
         doom--map-forms)))
```

用法：

```elisp
(map! :textobj "|" #'evil-inner-thing #'evil-outer-thing)
```

#### 模式 10: `:prefix-map` 内的"空 prefix"（group-only）

`+emacs-bindings.el:32-33`：

```elisp
(:prefix ("l" . "<localleader>")) ; bound locally
(:prefix ("!" . "checkers"))      ; bound by flycheck
```

纯描述 prefix，下面没具体键位（供其他代码如 `flycheck` 自行填入子命令）。

### 2.3 性能优化：为什么不用 general 的 `:prefix` 直接属性

`doom-keybinds.el:185-187` 注释：

```
;; PERF: We use a prefix commands instead of general's
;;   :prefix/:non-normal-prefix properties because general is incredibly slow
;;   binding keys en mass with them in conjunction with :states -- an effective
;;   doubling of Doom's startup time!
```

**经验**: 启动期 macroexpansion 时，`general.el` 的 `:prefix` 会展开成 N 个键位 × M 个 state 的嵌套函数调用 → 爆炸式增长。doom 的解决方案是先生成一个 `doom-leader-code-map` 变量 → 用 `define-key` 直接挂在 prefix command 上。

### 2.4 Spacemacs 对应范式

`spacemacs/core/core-keybindings.el:81-99`（`spacemacs/set-leader-keys`）：

```elisp
(defun spacemacs/set-leader-keys (key def &rest bindings)
  (while key
    (define-key spacemacs-default-map (kbd key) def)
    (setq key (pop bindings) def (pop bindings))))
```

**对比 doom**:
| 维度 | Doom `map!` | Spacemacs `set-leader-keys` |
|---|---|---|
| 状态分发 | 内置 `:nvi` 等 | 需手工调用 `define-key!` |
| 描述 | `:desc "..."` 自动进 which-key | `spacemacs/declare-prefix` 单独调用 |
| 嵌套 | `:prefix-map` 宏 | 需 `bind-map` 包 + `spacemacs/declare-prefix-for-mode` 手工连线 |
| 模块化 | `(:when (modulep! :tools lsp))` 内联 | 需 `if` 包裹整个 `use-package :config` 块 |
| 学习曲线 | 陡（macro 实现复杂） | 平（普通 defun 风格） |

---

## 3. which-key 集成

### 3.1 Doom 的 which-key 配置（逐行分析）

`doom-keybinds.el:235-256`：

```elisp
(use-package! which-key
  :hook (doom-first-input . which-key-mode)               ; (1)
  :init
  (setq which-key-sort-order #'which-key-key-order-alpha ; (2)
        which-key-sort-uppercase-first nil               ; (3)
        which-key-add-column-padding 1                   ; (4)
        which-key-max-display-columns nil                ; (5)
        which-key-min-display-lines 6                     ; (6)
        which-key-side-window-slot -10)                  ; (7)
  :config
  (put 'which-key-replacement-alist 'initial-value which-key-replacement-alist)
  (add-hook! 'doom-before-reload-hook
    (defun doom-reset-which-key-replacements-h ()       ; (8)
      (setq which-key-replacement-alist (get 'which-key-replacement-alist 'initial-value))))
  ;; general improvements to which-key readability
  (which-key-setup-side-window-bottom)                    ; (9)
  (setq-hook! 'which-key-init-buffer-hook line-spacing 3) ; (10)

  (which-key-add-key-based-replacements doom-leader-key "<leader>")         ; (11)
  (which-key-add-key-based-replacements doom-localleader-key "<localleader>"))
```

**逐项解释**:

1. **`(doom-first-input . which-key-mode)`**：不在 `:init`/`:config` 启用，等用户第一次按键（避免启动时多耗 ~30ms）。`doom-first-input` 是 doom 自定义 hook（`doom-ui.el` 中定义）
2. **字母排序**：默认按 key 字母顺序，doom 选 alpha 模式让 `<leader> f` (file) 和 `<leader> p` (project) 邻位显示
3. **小写优先**：避免 `C-x` 排在 `c-x` 前
4. **列间距 1**：不要过度 padding
5. **不限列数**：超过屏幕宽自动换行
6. **最少 6 行**：少于 6 行不显示（避免误触发）
7. **bottom slot -10**：放最底（避免覆盖 mode-line）
8. **reload 钩子**：私有 config 中调用 `which-key-replace-key-replacement-alist` 后，`doom/reload` 不会污染原表
9. **bottom side window**：doom 偏好底部（其他 config 多用 right）
10. **line-spacing 3**：宽松行高，提升可读性
11. **leader/localleader 替换**：which-key 弹窗中 `SPC` 显示成 `<leader>`，`SPC m` 显示成 `<localleader>`

### 3.2 `:desc` 参数如何让 which-key 更友好

**对照**:

```elisp
;; (a) 无 :desc
(map! :leader "ff" #'find-file)
;; which-key 显示: ff  find-file

;; (b) 有 :desc
(map! :leader :desc "Find file" "ff" #'find-file)
;; which-key 显示: ff  Find file
```

**机制**（`doom-keybinds.el:316-319`）：

```elisp
(:desc
 (setq desc (pop rest)))
```

`doom--map-def` (`:373-394`) 把 desc 注入到 def 的 `:which-key` 属性：

```elisp
(when desc
  (cond ((and (listp def) (keywordp (car-safe (setq unquoted (doom-unquote def)))))
         (setq def (list 'quote (plist-put unquoted :which-key desc))))
        ((setq def (cons 'list
                         (plist-put (general--normalize-extended-def def)
                                    :which-key desc))))))
```

which-key 读 `:which-key` 属性覆盖默认描述。

### 3.3 which-key 优化清单（10 条具体可执行项）

1. **延迟启用**（`doom-keybinds.el:237`）：`(doom-first-input . which-key-mode)` 避免启动期开销
2. **替换 leader 显示**（`doom-keybinds.el:253-254`）：`(which-key-add-key-based-replacements doom-leader-key "<leader>")`
3. **bottom side window**（`doom-keybinds.el:251`）：`(which-key-setup-side-window-bottom)` —— right 容易盖住 vertico/company
4. **行距 3**（`doom-keybinds.el:252`）：`(setq-hook! 'which-key-init-buffer-hook line-spacing 3)` —— 长菜单可读
5. **描述简短（≤20 字符）**：长描述截断，`:desc "Search project for symbol at point"` 不好用，改 `:desc "Search project symbol"`
6. **`:prefix-map` 必须带描述**：`(:prefix-map ("s" . "search") ...)` —— 不写 description 就只是 key letter
7. **分组前缀复用**：相同子树的 `:desc` 提到 `:prefix-map` 上，避免每行重写（doom `+emacs-bindings.el:30-99` 全文都用此模式）
8. **`show-transient` 不要开**：`which-key-show-transient-buttons` 会让 popup 变得混乱（doom 默认 `nil`）
9. **替换过期映射**：`which-key-replacement-alist` 私有定制后，必须配 `doom-reset-which-key-replacements-h` (`doom-keybinds.el:248-250`) 防止 reload 累积
10. **不用 `which-key-persistent-popup`**（doom 不用）：长期挂着的 popup 妨碍操作；doom 让 popup 出现 → 短延迟 → 自动消失

### 3.4 何时 which-key 会变混乱（>100 键位）

**根因**：

- 每个 `:prefix-map` 创建独立 keymap，which-key 树深度由嵌套层数决定
- doom `+emacs-bindings.el` 全文有约 200+ leader 绑定，分布在大约 25 个 prefix-map 中

**应对**:

- **强制分类**：所有 `:leader` 键位必须在某个 `:prefix-map` 下；doom 维护者 `@hlissner` 严格要求"3+ 字符前缀都要有自己的 prefix-map"
- **动态禁用**：`spacemacs-navigation/packages.el:99-105` 用 `(spacemacs|add-toggle automatic-symbol-highlight :evil-leader "tha")` 把 `toggle` 类命令放 `SPC t` 二级菜单，不挤 `<leader>` 一级
- **evil 局部 leader**：evil normal state `m` 系列（如 `mf`/`mr`/`my`）是文本对象触发器，**不**进 which-key；doom 通过 `doom-localleader-key "SPC m"` 显式分离 (`doom-keybinds.el:23`)
- **side-window 位置**：多列显示（`which-key-max-display-columns 3`）让 50+ 键位也能一屏看完

### 3.5 Spacemacs 的 which-key 集成

`core-keybindings.el:67-79`：

```elisp
(defun spacemacs/declare-prefix (prefix name &rest more)
  (apply #'which-key-add-keymap-based-replacements spacemacs-default-map
    prefix name more))
```

**对比 doom**:
| 维度 | Doom | Spacemacs |
|---|---|---|
| API 名称 | `:desc` 内联在 `map!` | `spacemacs/declare-prefix` 单独调用 |
| 描述粒度 | 每个 key 可有 | 整个 prefix 子树一个 |
| 模式 leader | `:localleader` 内置 | `spacemacs/declare-prefix-for-mode` |
| 注入方式 | 进 def 的 `:which-key` 属性 | 直接 `which-key-add-keymap-based-replacements` |

**反模式**：spacemacs 用户经常忘记在 `packages.el` 中调用 `spacemacs/declare-prefix` → which-key 显示纯 `function-name`，无业务描述。

---

## 4. workspaces 范式

### 4.1 三个候选方案对比

| 维度                 | Doom `persp-mode` (`:ui workspaces`)                                           | Spacemacs `persp-mode` (eyebrowse 配合)                                           | `tab-bar-mode` (Emacs 27+ 内建) |
| -------------------- | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------- | ------------------------------- |
| **核心抽象**         | buffer 集合 + 窗口配置                                                         | 同左（+ eyebrowse 维护窗口布局）                                                  | 顶层 window configuration       |
| **buffer 隔离**      | ✅ `+workspace-buffer-list` (`workspaces/config.el:115`) → `persp-buffer-list` | ✅ `spacemacs-layouts-restricted-functions` (`spacemacs-layouts/config.el:38-70`) | ❌ buffer 仍全局共享            |
| **winner-mode 集成** | ✅ per-persp `winner-ring` (`workspaces/config.el:85-101`)                     | 部分（eyebrowse 自管）                                                            | ❌ 全局 winner-ring             |
| **持久化**           | 文件级（`persp-save-dir`）                                                     | 文件级 + `spacemacs/quickload-session`                                            | session + desktop               |
| **持久化粒度**       | 单 workspace 文件 (`_workspaces`) 或 autosave                                  | 整体 session + 单个 layout                                                        | 整个 session                    |
| **多 frame 关联**    | ✅ `persp-set-last-persp-for-new-frames` (`workspaces/config.el:43`)           | ✅ + eyebrowse-frame-to-window-config                                             | ❌ tab 与 frame 1:1             |
| **tab-bar 集成**     | ✅ `+workspaces-set-up-tab-bar-integration-h` (`workspaces/config.el:240-256`) | ❌ 弃用                                                                           | N/A（自身就是 tab-bar）         |
| **性能**             | 中（hash-table 存储，切换瞬时）                                                | 中+（eyebrowse 额外维护）                                                         | 快（native）                    |
| **复杂度**           | 高（**256 行 config + 645 行 autoload**）                                      | 中                                                                                | 低                              |

### 4.2 Doom `workspaces` 模块范式（`workspaces/config.el` 全文）

**核心代码段**（`workspaces/config.el:13-256`）：

```elisp
(use-package! persp-mode
  :unless noninteractive
  :hook (doom-init-ui . persp-mode)               ; (1) UI 初始化后启用
  :config
  (setq persp-autokill-buffer-on-remove 'kill-weak ; (2) 切换时清理孤立 buffer
        persp-reset-windows-on-nil-window-conf nil
        persp-nil-hidden t
        persp-auto-save-fname "autosave"
        persp-save-dir (file-name-concat doom-profile-data-dir "workspaces/")
        persp-set-last-persp-for-new-frames t
        persp-switch-to-added-buffer nil
        persp-kill-foreign-buffer-behaviour 'kill
        persp-remove-buffers-from-nil-persp-behaviour nil
        persp-auto-resume-time -1                   ; (3) 不要自动恢复
        persp-auto-save-opt 1)                     ; (4) 退出时自动保存

  (add-hook! 'persp-mode-hook
    (defun +workspaces-ensure-no-nil-workspaces-h () ; (5) 屏蔽 persp 自带 nil workspace
      ...))

  (add-hook! 'persp-mode-hook
    (defun +workspaces-init-first-workspace-h ()    ; (6) 强制 "main" workspace 存在
      ...))

  ;; (7) Per-workspace winner-mode 历史
  (add-to-list 'window-persistent-parameters '(winner-ring . t))
  (add-hook! 'persp-before-deactivate-functions
    (defun +workspaces-save-winner-data-h ...))
  (add-hook! 'persp-activated-functions
    (defun +workspaces-load-winner-data-h ...))

  ;; (8) 自动注册 buffer 到当前 workspace
  (add-hook! 'doom-switch-buffer-hook
    (defun +workspaces-add-current-buffer-h ...))

  ;; (9) 删空 workspace 时自动关 frame
  (define-key! persp-mode-map
    [remap delete-window] #'+workspace/close-window-or-workspace
    [remap evil-window-delete] #'+workspace/close-window-or-workspace)

  ;; (10) Per-frame workspace 关联
  (setq persp-init-frame-behaviour t
        persp-init-new-frame-behaviour-override nil
        persp-interactive-init-frame-behaviour-override #'+workspaces-associate-frame-fn)
  (add-hook 'delete-frame-functions #'+workspaces-delete-associated-workspace-h)
  (add-hook 'server-done-hook #'+workspaces-delete-associated-workspace-h)

  ;; (11) Projectile 集成：新 project 自动开 workspace
  (setq projectile-switch-project-action #'+workspaces-switch-to-project-h)
  ...)
```

**11 个范式亮点**：

1. **`:hook (doom-init-ui . persp-mode)`**：UI 初始化后启用，避免启动期连锁触发
2. **`'kill-weak`**：删除 workspace 时清理弱关联 buffer（不删有意义的）
3. **`persp-auto-resume-time -1`**：不自动恢复（让用户主动 `+workspace/restore-last-session`）
4. **`persp-auto-save-opt 1`**：退出时自动保存到 `autosave` 文件
5. **屏蔽 nil workspace**：doom 不喜欢 persp 的隐藏 nil workspace → 强制替换为 `+workspaces-main "main"` 字符串名
6. **强制 main 存在**：首次启动自动添加 "main"
7. **per-workspace winner-mode**：每个 workspace 独立的窗口撤销历史（关键 UX 提升）
8. **buffer 自动注册**：`doom-switch-buffer-hook` 触发 → 把当前 buffer 加入当前 perspective
9. **关窗触发关 workspace**：用户按 `C-w` 关掉最后窗口 → 自动关 workspace（`+workspace/close-window-or-workspace` in autoload）
10. **per-frame workspace**：新建 frame 自动关联到独立 workspace（不污染主 workspace）
11. **Projectile 联动**：`+workspaces-on-switch-project-behavior 'non-empty`（`workspaces/config.el:13-22`）—— 当前 workspace 非空时开新 workspace

### 4.3 Spacemacs 的 workspaces 范式

`spacemacs-layouts/packages.el:36-115`：

```elisp
(defun spacemacs-layouts/init-eyebrowse ()
  (use-package eyebrowse
    :init
    (setq eyebrowse-wrap-around t)
    (eyebrowse-mode)
    (spacemacs|transient-state-format-hint workspaces ...)
    (spacemacs|define-transient-state workspaces
      :title "Workspaces Transient State"
      :bindings
      ("0" spacemacs/eyebrowse-switch-to-window-config-0 :exit t)
      ("1" ... :exit t)
      ...)))

(defun spacemacs-layouts/init-persp-mode ()
  (use-package persp-mode
    :init
    (setq persp-add-buffer-on-after-change-major-mode 'free
          persp-auto-resume-time (if dotspacemacs-auto-resume-layouts 1 -1)
          persp-is-ibc-as-f-supported nil
          persp-nil-name dotspacemacs-default-layout-name
          ...)))
```

**双层范式**:

- **Layouts** (`SPC l`) = `persp-mode`（buffer 集合）
- **Workspaces** (`SPC w`) = `eyebrowse`（窗口配置）
- 两者通过 `spacemacs/update-eyebrowse-for-perspective` 钩子联动（`spacemacs-defaults/funcs.el` 中）

**vs Doom 单一抽象**:

- Spacemacs 把"窗口布局"和"buffer 集合"作为两个独立维度
- Doom 全部塞进 `persp-mode`（persp-mode 内部就有 window-conf）

### 4.4 选型决策

| 场景                       | 推荐                          | 原因                              |
| -------------------------- | ----------------------------- | --------------------------------- |
| 单项目、需要 buffer 强隔离 | Doom `persp-mode`             | 自动跟随 `persp-contain-buffer-p` |
| 多项目、buffer 共享为常态  | Spacemacs eyebrowse + layouts | workspace 概念轻量                |
| 想用 Emacs 27+ native UI   | `tab-bar-mode`                | 内建，无第三方依赖                |
| 团队/配置版本化            | Doom（持久化文件可分享）      | 持久化更精细                      |
| 远程服务器 / 多 frame      | Doom（per-frame 关联更稳）    | 多 frame 测试更好                 |

### 4.5 持久化与切换性能

| 维度         | persp-mode (Doom)                            | eyebrowse (Spacemacs)            | tab-bar-mode             |
| ------------ | -------------------------------------------- | -------------------------------- | ------------------------ |
| 启动恢复时间 | 中（`+workspace/restore-last-session`）      | 快（eyebrowse-load-last-config） | 几乎无（native session） |
| 关闭自动保存 | `persp-auto-save-opt 1`                      | 需 `spacemacs/quickload-session` | `desktop-save-mode`      |
| 启动期性能   | 弱（Doom 把它放在 `doom-init-ui`，略晚启动） | 强（独立 minor-mode）            | 强                       |

---

## 5. popup / childframe 范式

### 5.1 Doom popup 系统

#### 5.1.1 核心概念

`popup/config.el:6-22`：

```elisp
(defconst +popup-window-parameters '(ttl quit select modeline popup)
  "A list of custom parameters to be added to `window-persistent-parameters'.")

(defvar +popup-default-display-buffer-actions
  '(+popup-display-buffer-stacked-side-window-fn)         ; 自定义 stacked side window
(defvar +popup-default-alist
  '((window-height . 0.16) (reusable-frames . visible)))
(defvar +popup-default-parameters
  '((transient . t) (quit . t) (select . ignore) (no-other-window . t)))
```

#### 5.1.2 `set-popup-rule!` 完整 API（`popup/autoload/settings.el:41-170`）

`set-popup-rule!` 是用户最常调用的"声明式规则"API：

```elisp
(set-popup-rule! "^\\*Help\\*"
  :side 'bottom        ; 哪边
  :size 0.4            ; 高度（比例/行数/函数）
  :slot 2              ; 横向位置
  :vslot -3            ; 纵向位置（控制堆叠）
  :ttl 0               ; time-to-live: 0=立即杀, nil=永存, t=默认
  :quit t              ; ESC/C-g 行为：t/'other/'current/nil/函数
  :select t            ; 打开后是否聚焦
  :modeline t          ; 模型线：t/nil/函数
  :autosave t          ; 关闭时是否自动保存
  :parameters '(...)   ; 自定义 window-parameters
  :actions '((display-buffer-in-side-window)))  ; 打开方式
```

**完整例子**（`modules/checkers/syntax/config.el:46-50`）：

```elisp
(set-popup-rules!
  '(("^\\*Flycheck error messages\\*" :select nil)
    ("^\\*Flycheck errors\\*" :size 0.25)))
```

**复杂例子**（`modules/lang/clojure/config.el:130-135`）：

```elisp
(set-popup-rules!
  '(("^\\*cider-error*" :ignore t)            ; 不让 popup 管，自行处理
    ("^\\*cider-repl" :quit nil :ttl nil)      ; REPL 不杀、不关
    ("^\\*cider-repl-history" :vslot 2 :ttl nil)))
```

#### 5.1.3 `:ignore t` 的作用

`popup/autoload/settings.el:42-45`：

```elisp
(defun +popup-make-rule (predicate plist)
  (if (plist-get plist :ignore)
      (list predicate nil)                    ; 关键！返回 (PREDICATE . nil)
    ...))
```

`display-buffer-alist` 中 `nil` action = **不干预**，让原始 `display-buffer` 处理。
用于 magit、helm、treemacs 等自己管 window 的包。

#### 5.1.4 `:vslot` 的 stacking 范式

`popup/autoload/popup.el:380-554` 的 `+popup-display-buffer-stacked-side-window-fn`：

> Allows for stacking popups with the `vslot' alist entry.

**用法**：

```elisp
(setq popup-rules
  '(;; vslot 0（最远）：minibuffer 临时提示
    ("^\\*Messages\\*" :vslot 0 :size 0.2 :ttl 3)
    ;; vslot -1：compilation
    ("^\\*compilation\\*" :vslot -1 :size 0.3)
    ;; vslot -2：vterm/eshell（最深）
    ("^\\*vterm\\*" :vslot -2 :size 0.4 :modeline nil)))
```

多个 popup 共享 `:side bottom` + 不同 `:vslot` → 沿底边从外到内堆叠。

#### 5.1.5 `+popup-buffer` 与 `+popup/raise` API

`popup/autoload/popup.el:182-191`：

```elisp
(defun +popup-buffer (buffer &optional alist)
  "Open BUFFER in a popup window. ALIST describes its features."
  (let* ((origin (selected-window))
         (window-min-height 3)
         (alist (+popup--normalize-alist alist))
         (actions (or (cdr (assq 'actions alist))
                      +popup-default-display-buffer-actions)))
    ...))
```

**用户级命令**（`popup/autoload/popup.el:267-340`）：

- `+popup/buffer` —— 把当前 buffer 转入 popup
- `+popup/close` —— 关单个
- `+popup/close-all` —— 全关
- `+popup/toggle` —— 有 popup 则关，否则显示 `*Messages*`
- `+popup/restore` —— 恢复刚关的（用 `+popup--last` 记忆）
- `+popup/raise` —— 提升 popup 到 regular window（关键：把 popup buffer 永久化）
- `+popup/other` —— popup 之间循环
- `+popup/diagnose` —— 显示当前 buffer 命中的 rule（调试用）

**doom 绑定**（`+evil-bindings.el:282-283, 346`）：

```elisp
"C-`"   #'+popup/toggle
"C-~"   #'+popup/raise
```

### 5.2 childframe vs side-window 决策

| 场景                            | childframe (posframe)         | side-window |
| ------------------------------- | ----------------------------- | ----------- |
| **小提示**（company/lsp hover） | ✅ 不抢焦点，光标可继续输入   | ❌ 抢焦点   |
| **代码补全菜单**                | ✅ 默认                       | 备选        |
| **terminal/vterm**              | ❌ childframe 渲染复杂        | ✅          |
| **REPL/eshell**                 | ❌                            | ✅          |
| **messages/log**                | ✅（如 flycheck 浮动）        | ✅          |
| **multi-window 同屏阅读**       | ❌                            | ✅          |
| **per-buffer 持久显示**         | ❌（frame 经常被 Emacs 销毁） | ✅          |

**Doom 的选择**：默认用 `+popup-display-buffer-stacked-side-window-fn`（side-window 派），不主动用 childframe。childframe 只在 `+popup-shrink-to-fit` 等内部用于 floating hints。

**为什么 Doom 不用 childframe 默认**：

- side-window 是 Emacs 内建 API，跨 Emacs 版本稳定
- childframe 在 daemon / tty 表现差
- side-window 跟 `winner-mode` 天然兼容

### 5.3 Spacemacs popup 范式

**简短对比**：spacemacs 没有自己的 popup 系统，直接用 `popwin`（`popwin-mode`）：

```elisp
(push '("*Help*" :dedicated t :position bottom :width 0.4 :height 0.4 :noselect nil)
      popwin:special-display-config)
```

**vs Doom**：
| 维度 | Doom `set-popup-rule!` | Spacemacs `popwin:special-display-config` |
|---|---|---|
| 规则匹配 | regex string / function | regex |
| ttl 自动关 | ✅ 内建 | ❌ |
| ESC 关闭 | ✅ `:quit` | 需手工 |
| 堆叠 | ✅ `:vslot` | ❌ |
| 子树 | ✅ `:ignore` | ❌ |

**结论**：Doom popup 体系是两者中更完备、更可编程的。

---

## 6. modeline 范式

### 6.1 Doom modeline 范式

#### 6.1.1 整体架构

`modeline/config.el:1-55`：

```elisp
(when (modulep! +light)
  (load! "+light"))                          ; (1) +light = 自研轻量

(use-package! doom-modeline                  ; (2) 默认 = doom-modeline
  :unless (modulep! +light)
  :hook (doom-after-init . doom-modeline-mode)
  :hook (doom-modeline-mode . size-indication-mode)
  :hook (doom-modeline-mode . column-number-mode)
  :init
  (setq doom-modeline-bar-width 3            ; (3) 3 像素的色条
        doom-modeline-github nil             ; (4) 显式关闭不需要的 segment
        doom-modeline-mu4e nil
        doom-modeline-persp-name nil         ; (5) workspace 名不在 modeline（用 tab line）
        doom-modeline-minor-modes nil        ; (6) 不用 minor-modes 列表
        doom-modeline-major-mode-icon nil    ; (7) 不用 major-mode 图标（性能）
        doom-modeline-check 'simple
        doom-modeline-buffer-file-name-style 'relative-from-project
        doom-modeline-buffer-encoding 'nondefault
        doom-modeline-default-eol-type (if (featurep :system 'windows) 1 0))
  ...)
```

**6 条范式亮点**：

1. **`+light` flag 切换实现**：开关模块化 → 同一 config.el 加载 `doom-modeline` 或自研 `+light.el`
2. **`doom-after-init`**：不在 `:init` 启动（避免 startup 期重绘）
3. **`bar-width 3`**：3px 色条标识 active/inactive window（XPM bitmap 绘制，不重排字符）
4. **关闭 github/mu4e 等可能没装的包**：避免错误
5. **`persp-name nil`**：workspace 名走 `+workspace/display`（minibuffer 短期显示），不放常驻 modeline
6. **`minor-modes nil`**：minor-modes 列表读 mode-line-format 时慢
7. **`major-mode-icon nil`**：图标涉及 `nerd-icons` lookup，慢

#### 6.1.2 `+light.el` 范式（自研）

`modeline/+light.el:115-145`：

```elisp
(def-modeline-var! +modeline-format-left nil
  "The left-hand side of the modeline."
  :local t)

(def-modeline-var! +modeline-format-right nil
  "The right-hand side of the modeline."
  :local t)

(defmacro def-modeline! (name lhs rhs)
  `(setf (alist-get name +modeline-format-alist) (cons lhs rhs))
  ...)

(def-modeline! :main
  '("" +modeline-matches " " +modeline-buffer-identification +modeline-position)
  `("" mode-line-misc-info +modeline-modes
    (vc-mode ("  " ,(nerd-icons-octicon "nf-oct-git_branch" :v-adjust 0.0) ...))))
```

**范式**：

- **每个 segment 是一个 `defconst`**：`(def-modeline-var! +modeline-buffer-identification "...")` 而不是 `setq`，避免运行时被覆盖
- **`:local t` 标记**：让 segment 变 buffer-local
- **`def-modeline!` 注册**：name → (lhs . rhs) alist，可用 `(set-modeline! :main)` 切换

### 6.2 Spacemacs modeline 范式

`spacemacs-modeline/packages.el:24-50`：

```elisp
(setq spacemacs-modeline-packages
      '(
        (doom-modeline :toggle (eq (spacemacs/get-mode-line-theme-name) 'doom))
        ...
        (spaceline :toggle (spacemacs//enable-spaceline-p))
        (spaceline-all-the-icons :toggle ...)
        (powerline :toggle (eq (spacemacs/get-mode-line-theme-name) 'vim-powerline))))

(defun spacemacs-modeline/init-doom-modeline ()
  (use-package doom-modeline
    :defer t
    :init (doom-modeline-mode)))
```

**范式**：

- **theme-style 选择**：`dotspacemacs-mode-line-theme` 可选 `doom` / `all-the-icons` / `spaceline` / `vim-powerline` / `vanilla`
- **包级别开关**：用 `:toggle` 条件选择包，避免全部加载

### 6.3 modeline 范式对比

| 维度                | Doom `doom-modeline` / `+light`                 | Spacemacs 多种可选               |
| ------------------- | ----------------------------------------------- | -------------------------------- |
| **性能**            | 极快（XPM bitmap + segment 缓存）               | 取决于选择；`vim-powerline` 最慢 |
| **可定制性**        | 高级（自研 `def-modeline!` 宏）                 | 中（每种包有自己配置）           |
| **segments**        | 已实现 20+（buffer-info、vcs、anzu、anzu 等）   | 取决于包                         |
| **theme 协调**      | 强（自动跟 `doom-theme`）                       | 中                               |
| **workspaces 显示** | 默认关闭（minibuffer 显示），符合"减少 clutter" | 多种包支持                       |

### 6.4 主题切换时 modeline 重绘

`modeline/config.el:39-41`：

```elisp
(add-hook 'after-setting-font-hook #'+modeline-resize-for-font-h)
(add-hook 'doom-load-theme-hook #'doom-modeline-refresh-bars)   ; (1) 关键
```

**机制**：换主题时，bar XPM 颜色 = `face-background 'doom-modeline-bar nil t` → 必须重画，否则色条还是旧色。

`+light.el:166-189` 的 `+modeline-refresh-bars-h`：

```elisp
(add-hook! '(doom-init-ui-hook doom-load-theme-hook) :append
  (defun +modeline-refresh-bars-h ()
    (let ((width (or +modeline-bar-width 1))
          (height (max +modeline-height 0))
          (active-bg (face-background 'doom-modeline-bar nil t))
          (inactive-bg (face-background 'doom-modeline-bar-inactive nil t)))
      ...
      (setq +modeline-active-bar
            (+modeline--make-xpm (and +modeline-bar-width active-bg) width height)
            +modeline-inactive-bar
            (+modeline--make-xpm (and +modeline-bar-width inactive-bg) width height)))))
```

---

## 7. 主题切换范式

### 7.1 Doom 主题范式（`doom-ui.el:202-281` + `lib/themes.el`）

#### 7.1.1 加载机制

`doom-ui.el:386-396`：

```elisp
(let ((hook (if (daemonp)
                'server-after-make-frame-hook
              'after-init-hook)))
  (add-hook hook #'doom-init-fonts-h -100)
  (add-hook hook #'doom-init-theme-h -90))
```

`doom-ui.el:228-247`：

```elisp
(defun doom-init-theme-h (&rest _)
  "Load the theme specified by `doom-theme' in FRAME."
  (dolist (th (ensure-list doom-theme))
    (unless (custom-theme-enabled-p th)
      (if (custom-theme-p th)
          (enable-theme th)
        (load-theme th t)))))
```

**关键点**：

- **`-100` / `-90` 优先级**：在 `doom-init-ui` 之前；保证 modeline/UI 拿到正确主题色
- **`(daemonp)` 时用 `server-after-make-frame`**：daemon 启动时还没有 frame
- **`doom-theme` 可以是 list**：`doom-theme '(doom-one doom-dracula)` 会加载多个

#### 7.1.2 主题识别（`doom-ui.el:249-281`）

```elisp
(defadvice! doom--detect-colorscheme-a (theme)
  "Add :kind \\='color-scheme to THEME if it doesn't already have one."
  :after #'provide-theme
  (or (plist-get (get theme 'theme-properties) :kind)
      (cl-callf plist-put (get theme 'theme-properties) :kind
                'color-scheme)))
```

**目的**：统一所有主题为 `color-scheme` 类型，简化下游 hook。

#### 7.1.3 `doom-load-theme-hook` 触发

`doom-ui.el:272-281`：

```elisp
(add-hook! 'enable-theme-functions :depth -90
  (defun doom-enable-theme-h (theme)
    "Record themes and trigger `doom-load-theme-hook'."
    (when (doom--theme-is-colorscheme-p theme)
      (ring-insert (with-memoization (get 'doom-theme 'history) (make-ring 8))
                   (copy-sequence custom-enabled-themes))
      ...
      (doom-run-hooks 'doom-load-theme-hook))))
```

**关键点**：

- **`:depth -90`**：在主题自己 hook 之后 → 用户定制不会被覆盖
- **`doom-load-theme-hook`**：用户配置挂这里调整 face（避免污染 `custom-file`）

#### 7.1.4 Face 定制宏（`lib/themes.el:20-77`）

```elisp
(defmacro custom-theme-set-faces! (theme &rest specs)
  "Apply a list of face SPECS as user customizations for THEME."
  (declare (indent defun))
  (let ((fn (gensym "doom--customize-themes-h-")))
    `(progn
       (defun ,fn ()
         (dolist (theme (ensure-list (or ,theme 'user)))
           (apply #'custom-theme-set-faces theme
                  (mapcan #'doom--normalize-face-spec
                          (list ,@specs))))))
       ...)))
```

**用法**（用户私有 config）：

```elisp
(custom-set-faces!
  '(font-lock-comment-face :foreground "#888")
  '(doom-modeline-bar :background "blue"))
```

**机制**：

1. 把 specs 注册到 `doom-customize-theme-hook`
2. 每次主题变化自动重新应用
3. 进 `with-temp-buffer` 避免 buffer-local face remap 污染（`doom-ui.el:277-279`）

#### 7.1.5 主题重载

`lib/themes.el:54-72`：

```elisp
(defun doom/reload-theme ()
  "Reload all currently active themes."
  (interactive)
  (let* ((themes (copy-sequence custom-enabled-themes))
         (real-themes (cl-remove-if-not #'doom--theme-is-colorscheme-p themes)))
    (mapc #'disable-theme themes)
    (dolist (th (reverse themes))
      (if (locate-file (concat (symbol-name th) "-theme.el")
                       (custom-theme--load-path)
                       '("" "c"))
          (load-theme th t)
        (enable-theme th)))
    (doom/reload-font)
    (message "%s" ...)))
```

### 7.2 Spacemacs 主题范式（`core-themes-support.el:271-321`）

```elisp
(defun spacemacs/load-default-theme ()
  "Load default theme. ... If loading fails, set
`spacemacs--delayed-user-theme' to postpone the action and try
again layer configuration."
  ...)

(defun spacemacs/cycle-spacemacs-theme (&optional backward)
  "Cycle through themes defined in `dotspacemacs-themes'."
  ...)
```

**关键差异**：

- **fallback 机制**：`spacemacs//guess-fallback-theme`（`core-themes-support.el:215-228`）→ 如果用户主题加载失败，按名字猜 fallback（"light" → `spacemacs-light`）
- **延迟加载**：`spacemacs--delayed-user-theme` → 如果主题依赖未初始化的包（`package-quickstart` 模式下），延后到 layer config 后再试
- **theme-package 映射表**：`spacemacs-theme-name-to-package`（`core-themes-support.el:42-260`）手写 300+ 主题到包名映射（因为很多 theme 包名不遵循 `<theme>-theme` 约定）
- **cycle through**：用 `dotspacemacs-themes` 列表，循环切换（doom 没有此功能）

### 7.3 主题 vs modeline 协调

**关键**：`doom-load-theme-hook` 中触发 `doom-modeline-refresh-bars`（见 6.4）。

**反模式**：用户在私有 config 用 `enable-theme` 直接切换 → 不会触发 doom 主题 hook → modeline bar 颜色不更新；正确做法是 `load-theme` 或 `doom/reload-theme`。

---

## 8. 高频操作的可发现性陷阱

### 8.1 leader-key 树超过 50 分支时的问题

**根因**：

- which-key 一行最多显示 ~20 项（视窗口宽度）
- 嵌套 4 层（`<leader> f p c`）后用户需要按 4 次前缀才到达命令
- 用户认知负担：`SPC f p` 是 find project → "create" 还是 "copy"？需要查 which-key

### 8.2 7 个可保留可发现性 + 支持高频的范式

#### 范式 1: `:prefix-map` 内部分组（doom 主范式）

doom `+emacs-bindings.el:30-100` 全文 200+ 键位都分组到 25+ `:prefix-map`，**没有任何 leader 一级键位孤立**。

```elisp
(map! :leader
  (:prefix-map ("c" . "code") ...)   ; ~30 个 code 命令
  (:prefix-map ("f" . "file") ...)   ; ~20 个 file 命令
  (:prefix-map ("s" . "search") ...) ; ~20 个 search 命令
  ...)
```

#### 范式 2: evil 局部 leader（`SPC m`）

`doom-keybinds.el:23-26`：

```elisp
(defvar doom-localleader-key "SPC m"      ; 模式专属
(defvar doom-localleader-alt-key "M-SPC m"
```

**用法**（`+evil-bindings.el` 中任意 major-mode 段）：

```elisp
(map! :localleader
      :desc "Compile" "c" #'compile
      :desc "Reformat" "f" #'reformat-buffer)
```

效果：`emacs-lisp-mode` buffer 中按 `SPC m` → 看到当前 mode 的 4-6 个常用命令 → 不用 `SPC` 主菜单污染。

#### 范式 3: `:desc` 短而动词化

doom `+emacs-bindings.el:34-44`：

```elisp
:desc "Compile"          "c" #'compile    ; 动词
:desc "Recompile"        "C" #'recompile
:desc "Jump to def"      "d" #'+lookup/definition
:desc "Find impls"       "i" #'+lookup/implementations   ; 缩写 impls
:desc "Jump to docs"     "k" #'+lookup/documentation
```

**规则**：≤3 个词、避免介词（"to"）、命令符号化（"def" 代替 "definition"）。

#### 范式 4: hydra / transient transient-state（Spacemacs 范式）

`spacemacs-navigation/packages.el:38-75`：

```elisp
(setq spacemacs--symbol-highlight-transient-state-doc "
 %s
 [_n_] next   [_N_/_p_] prev  [_d_/_D_] next/prev def  [_r_] range  [_R_] reset  [_z_] recenter
 [_e_] iedit")

(spacemacs|define-transient-state symbol-highlight
  :title "Symbol Highlight Transient State"
  :hint-is-doc t
  :dynamic-hint (spacemacs//symbol-highlight-ts-doc)
  :on-exit (spacemacs//ahs-ts-on-exit)
  :bindings
  ("d" ahs-forward-definition)
  ("D" ahs-backward-definition)
  ("e" spacemacs/ahs-to-iedit :exit t)
  ("n" spacemacs/quick-ahs-forward)
  ("N" spacemacs/quick-ahs-backward)
  ("p" spacemacs/quick-ahs-backward)
  ("R" ahs-back-to-start)
  ("r" ahs-change-range)
  ("z" recenter-top-bottom)
  ("q" nil :exit t))
```

**范式特点**：

- 进入后所有相关动作收拢到一个临时键位集合
- 提示文档（hint）**动态**显示当前 buffer 的 symbol 等信息
- 按 `q`/`RET`/`<tab>` 退出
- 适合"上下文内反复操作"（跳定义、循环看文档、改 range 等）

**对应 doom**：

- doom 不内建 hydra，但 `doom-ui.el:264-269` 用 `:hook (doom-first-input . winner-mode)` 等"全局 hook"代替
- 用户可手动装 `hydra` 包，`map!` 中直接 `define-key` 进入 hydra

#### 范式 5: `:repeat-mode` + 简单键位

Emacs 30+ 的 `repeat-mode` + `repeat-complex-command`：

```elisp
(repeat-mode 1)

(map! :leader
  (:prefix-map ("g" . "goto")
   :desc "Go to line"   "g" #'goto-line
   :desc "Go to def"    "d" #'+lookup/definition
   :desc "Go to file"   "f" #'+default/find-file-under-here)
  (:prefix-map ("s" . "search")
   :desc "Search buffer" "b" #'+default/search-buffer
   :desc "Search project" "p" #'+default/search-project))
```

效果：在 `<leader> s p` 后再按 `<leader> s p` → 自动重复 project search（无需完整重打）

#### 范式 6: Spacemacs cycling via TAB

`spacemacs-navigation/config.el:11-15`：

```elisp
(defvar spacemacs-default-cycle-forwards-key [tab]
  "Key to cycle forwards after commands determined
by `dotspacemacs-enable-cycling'.")
```

- `spacemacs-navigation/packages.el:248-291` 中的 `spacemacs-navigation/init-transient-cycles`：

```elisp
(transient-cycles-define-commands
  (window prev-buffers)
  (([remap spacemacs/alternate-buffer] ()
     ...))
  ...
  :cycle-backwards-key (or spacemacs-alternate-buffer-cycle-backwards-key
                           spacemacs-default-cycle-backwards-key)
  :cycle-forwards-key (or spacemacs-alternate-buffer-cycle-forwards-key
                          spacemacs-default-cycle-forwards-key))
```

**范式**：执行命令后，按 `TAB` 循环"下一个候选"（buffer/window/layout），无需 which-key。

#### 范式 7: `+workspace/display` 一次性显示

`workspaces/autoload/workspaces.el:380-395`：

```elisp
;;;###autoload
(defun +workspace/display ()
  "Display a list of workspaces (like tabs) in the echo area."
  (interactive)
  (let (message-log-max)
    (message "%s" (+workspace--tabline))))
```

**机制**：按 `SPC TAB TAB` 临时在 minibuffer 显示所有 workspace 名 → 用户瞄一眼 → 决定下一步。

**类比**：`SPC b b` 显示 buffer 列表（doom 的 `+default/buffer-list`）。

### 8.3 反模式（不要做）

1. **用 `bind-key` 绑定到单字母 C-x 或 C-c**：被 `mode-specific-map` 拦截（emacs-users 期望 C-x 是 prefix command）
2. **leader 一级菜单超过 15 个键位**：which-key 必换行
3. **`:desc` 用名词**：`"file"` 不如 `"Find file"`
4. **嵌套 depth 超过 3 层**：用户迷失
5. **重复定义同一键在不同 prefix**：which-key 显示但按错就出问题

---

## 9. 键位冲突诊断

### 9.1 doom 自带工具

#### 工具 1: `general-auto-unbind-keys` (`doom-keybinds.el:140`)

```elisp
(add-hook 'doom-after-modules-init-hook #'general-auto-unbind-keys)
```

**机制**：`general.el` 跟踪所有 `general-define-key` 调用；启动结束后，发现某 key 被多个 general 调用绑定过 → 自动 unbind 旧定义。

**用户场景**：doom 模块 A 绑了 `SPC x` 给 `command-A`，用户在私有 config 又绑了 `SPC x` 给 `command-B` → 启动后 doom 发出 warning，保留后绑定。

#### 工具 2: `define-key!` / `undefine-key!` 别名

`doom-keybinds.el:137-138`：

```elisp
(defalias 'define-key! #'general-def)
(defalias 'undefine-key! #'general-unbind)
```

**用法**：

```elisp
(undefine-key! doom-leader-map "SPC x")   ; 移除单个
(define-key! doom-leader-map "SPC x" #'my-cmd)  ; 重绑
```

#### 工具 3: `doom/escape` 的多级诊断

`doom-keybinds.el:113-130`：

```elisp
(defun doom/escape (&optional interactive)
  "Run `doom-escape-hook'."
  (interactive (list 'interactive))
  (let ((inhibit-quit t))
    (cond ((minibuffer-window-active-p (minibuffer-window))
           (when interactive (setq this-command 'abort-recursive-edit))
           (abort-recursive-edit))
          ((run-hook-with-args-until-success 'doom-escape-hook))
          ((or defining-kbd-macro executing-kbd-macro) nil)
          ((unwind-protect (keyboard-quit)
             (when interactive (setq this-command 'keyboard-quit)))))))
```

**5 段处理顺序**（这是用户"按 ESC/C-g 怎么没反应"的诊断清单）：

1. 退出 minibuffer
2. 跑 `doom-escape-hook`（popup close、highlight 清除、iedit 退出等）
3. recording macro 时不动
4. 回退到 `keyboard-quit`

如果第 4 步才生效 → 你的 `doom-escape-hook` 没正确添加。

### 9.2 标准 Emacs 工具

| 命令                               | 用途                                               |
| ---------------------------------- | -------------------------------------------------- |
| `M-x describe-key` (`C-h k`)       | 输入一个键 → 显示该键当前调用哪个命令              |
| `M-x describe-bindings` (`C-h b`)  | 列出当前 buffer 所有绑定                           |
| `M-x which-key-show-top-level`     | 弹 which-key 一级菜单（等价于 `SPC` 后等 1 秒）    |
| `M-x general-describe-keybindings` | `general` 包自带，按 `general-define-key` 顺序显示 |
| `M-x where-is <command>`           | 查某命令绑在哪些键上                               |
| `M-x debug-on-entry`               | 进入某命令时进 debugger                            |

### 9.3 which-key 自检

```elisp
(which-key-show-keymap 'doom-leader-map)            ; 只看 leader
(which-key-show-keymap (current-local-map))         ; 当前 major-mode
(which-key-show-keymap (current-global-map))        ; 全局
```

### 9.4 启动期 warning 模式

`doom-keybinds.el:139-140`：

```elisp
;; Prevent "X starts with non-prefix key Y" errors except at startup.
(add-hook 'doom-after-modules-init-hook #'general-auto-unbind-keys)
```

**关键**：warning 在 startup 才显示，运行时不响。`general.el` 默认每次 `general-define-key` 都警告 → doom 显式抑制运行期警告。

**用户应对**：启动时注意 `*Warnings*` buffer，看 `"key X already bound by Y"` 类警告。

### 9.5 doomscript-style 一致性检查

doom 没有内建的"全键位 audit" 工具，但用户可写：

```elisp
(defun my/audit-leader ()
  (interactive)
  (let ((entries (cdr doom-leader-map)))
    (with-output-to-temp-buffer "*leader-audit*"
      (princ "Leader bindings (sorted by key):\n\n")
      (dolist (binding (sort (copy-sequence entries)
                             (lambda (a b) (string< (format "%S" (car a))
                                                   (format "%S" (car b))))))
        (princ (format "%-20s -> %s\n" (car binding) (cdr binding)))))))
```

---

## 10. 范式对比总表

### 10.1 Doom vs Spacemacs 范式速览

| 维度                | Doom Emacs                                        | Spacemacs                                                         |
| ------------------- | ------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------- |
| **键位宏**          | `map!` (one macro to rule them all)               | `spacemacs/set-leader-keys` + `spacemacs/declare-prefix` (多函数) |
| **leader 描述**     | 内联 `:desc` (within `map!`)                      | 单独 `spacemacs/declare-prefix`                                   |
| **嵌套 prefix**     | `(:prefix-map ("x" . "name"))`                    | 手工 `bind-map` + `declare-prefix-for-mode`                       |
| **which-key 配置**  | 在 `doom-keybinds.el:235-256` 集中管理            | 在 layer 各自 `packages.el` 散落                                  |
| **workspace 抽象**  | 单一 `persp-mode`                                 | 双层 `persp-mode` (layouts) + `eyebrowse` (workspaces)            |
| **popup 系统**      | 自研 `+popup-...` + `set-popup-rule!`             | `popwin` 包                                                       |
| **dashboard**       | 自研 `+dashboard-mode`（含 banner/footer/loaded） | `dashboard` 包 (spacemacs-buffer)                                 |
| **themes**          | `doom-theme` 变量 + `doom-load-theme-hook`        | `dotspacemacs-themes` 列表 + cycle 命令                           |
| **transient state** | 无内建（用 hydra 包）                             | `spacemacs                                                        | define-transient-state` 一等公民 |
| **tab line**        | `:ui tabs` (centaur-tabs，可选)                   | `spaceline-all-the-icons` 段                                      |
| **module 粒度**     | `doom!` 块 + flag (`+lsp`)                        | `dotspacemacs-configuration-layers` 列表                          |

### 10.2 leader-key 5 种风格对比（汇总）

见 §1.1 表。

### 10.3 which-key 12 条优化清单（汇总）

见 §3.3（10 条）+ 补充：

11. **延迟启用**（已在 §3.3）
12. **描述统一用动词+宾语**：`"Open file"` 而非 `"file-open"` 或 `"openfile"`

---

## 11. 实施检查清单

### 11.1 新配置基础必须做

- [ ] 选定 leader 风格（§1.4 决策树）
- [ ] 配置 which-key 延迟启用 + 替换 display + side-window bottom
- [ ] 选定 workspace 方案（persp-mode / tab-bar / eyebrowse）
- [ ] 选定 modeline（doom-modeline / spaceline / 自研）
- [ ] 选定 popup 体系（doom set-popup-rule / popwin / 裸 display-buffer）

### 11.2 第一次跑通

- [ ] 启动后 `*Warnings*` buffer 无错误
- [ ] `<leader>` 触发 which-key popup 正常显示
- [ ] `<leader>` 嵌套菜单 3 层内能到达所有常用命令
- [ ] `<localleader>` 在 major-mode 中显示该 mode 专属菜单
- [ ] 切换 theme 后 modeline bar 颜色正确更新
- [ ] 创建/删除 workspace 后不残留 buffer

### 11.3 高频操作收拢

- [ ] 高频命令（5+ 次/天）放在 `SPC` 一级或 `:localleader` 一级
- [ ] 中频命令（1-5 次/天）在 `:prefix-map` 内
- [ ] 低频命令（<1 次/天）放 3 层嵌套之后
- [ ] 模式专属命令进 `:localleader`
- [ ] 用 `which-key-show-top-level` 验证一级菜单 ≤15 项

### 11.4 进阶范式（可选）

- [ ] hydra / transient-state 用在 "上下文内反复操作"
- [ ] per-workspace winner-mode 历史
- [ ] popup `:ttl` 配置（vterm/eshell 不杀，_Messages_ 自动杀）
- [ ] per-frame workspace 关联（多 frame 工作流）
- [ ] session 自动保存 + 启动时手动 `+workspace/restore-last-session`

### 11.5 反模式（绝对不要）

- [ ] ❌ 选 `C-c` 单字母当 leader（被 `mode-specific-map` 占）
- [ ] ❌ 用 `customize` 界面配置（doom 禁用，`doom-ui.el:511-517`）
- [ ] ❌ 在 `:config` 中调 `map!` 频繁 re-define（用 `:after` 宏）
- [ ] ❌ `which-key-persistent-popup`（doom 默认关）
- [ ] ❌ `:prefix-map` 不写 desc（用户看不到业务名）
- [ ] ❌ `:desc` 用名词或介词开头（"to"、"for"）
- [ ] ❌ 一个 key 绑两次（`general-auto-unbind-keys` 报警）
- [ ] ❌ 在 evil mode 用 `C-c <letter>` 占用 mode-specific-map
- [ ] ❌ 切换主题后不重画 modeline（必须 `doom/reload-theme`）
- [ ] ❌ 在 popup 启用 `:ignore t` 但又用 `display-buffer`（直接返回 nil，不做事）

---

## 12. 关键代码引用清单（按文件分组）

### `doomemacs/lisp/doom-keybinds.el`

- `:11-29` — 4 个 leader/localleader 变量 + state 列表
- `:64-86` — `doom-init-input-decode-map-h`（mac/win 键位修复）
- `:111-130` — `doom/escape` 多级诊断
- `:137-140` — `define-key!`/`undefine-key!` 别名 + `general-auto-unbind-keys`
- `:144-185` — `doom--define-leader-key` / `define-leader-key!` / `define-localleader-key!` 宏
- `:188-202` — `doom-init-leader-keys-h` 延迟绑定
- `:235-256` — which-key 集成
- `:283-287` — `doom-evil-state-alist`（状态字符 → symbol）
- `:300-340` — `doom--map-process` 顶层 dispatcher
- `:464-484` — `map!` 宏 docstring

### `doomemacs/lisp/doom-ui.el`

- `:202-281` — 主题加载/检测/enable-theme 钩子
- `:386-396` — 主题/字体初始化优先级

### `doomemacs/lisp/lib/themes.el`

- `:1-77` — `custom-theme-set-faces!` / `doom/reload-theme`

### `doomemacs/lisp/lib/ui.el`

- `:50-90` — `doom-quit-p` / `doom/toggle-line-numbers`
- `:125-145` — `doom/window-maximize-buffer` / `enlargen`
- `:147-185` — `doom/set-frame-opacity`

### `doomemacs/lisp/lib/buffers.el`

- `:1-100` — real/unreal buffer 概念 + `doom-real-buffer-p`
- `:120-180` — `doom-kill-buffer-fixup-windows` / `doom-kill-all-buffers`

### `doomemacs/modules/ui/workspaces/config.el`

- `:1-256` — 完整 persp-mode 集成

### `doomemacs/modules/ui/workspaces/autoload/workspaces.el`

- `:1-200` — `+workspace-*` 函数库
- `:200-400` — 命令（new/switch/kill/clone）
- `:400-600` — `+workspace/close-window-or-workspace` + tabs message
- `:600-684` — frame 关联 + project switch 集成

### `doomemacs/modules/ui/popup/config.el`

- `:1-100` — `+popup-mode` / `+popup-buffer-mode` 局部模式
- `:100-184` — 默认 popup rules

### `doomemacs/modules/ui/popup/autoload/popup.el`

- `:1-200` — 内部 hook（delete window / save load / ttl）
- `:200-340` — `+popup/buffer` / `+popup/close` / `+popup/raise` 用户命令
- `:380-554` — `+popup-display-buffer-stacked-side-window-fn` 核心

### `doomemacs/modules/ui/popup/autoload/settings.el`

- `:41-170` — `set-popup-rule!` 完整 docstring
- `:172-186` — `set-popup-rules!` 批量版

### `doomemacs/modules/ui/dashboard/config.el`

- `:1-200` — `+dashboard-mode` 定义、菜单 sections、widgets
- `:200-340` — `+dashboard-reload` / `+dashboard-reposition-point-h`
- `:340-450` — `+dashboard-insert` / banner drawing
- `:450-572` — 各 widget 实现

### `doomemacs/modules/ui/modeline/config.el`

- `:1-55` — doom-modeline 配置 + 关闭多余 segment

### `doomemacs/modules/ui/modeline/+light.el`

- `:115-145` — `def-modeline!` / `def-modeline-var!` 宏
- `:166-260` — `+modeline-refresh-bars-h` + segments

### `doomemacs/modules/ui/tabs/config.el`

- `:1-40` — centaur-tabs 配置

### `doomemacs/modules/ui/zen/config.el`

- `:1-95` — writeroom + mixed-pitch + focus 范式

### `doomemacs/modules/config/default/+emacs-bindings.el`

- `:22-100` — `map!` + `:prefix-map` + `:when` 完整用法范本
- `:100-200` — `SPC s` 搜索、`SPC i` 插入
- `:200-350` — `SPC n` notes、`SPC w` windows

### `doomemacs/modules/config/default/+evil-bindings.el`

- `:7-50` — evil-specific 绑定 (smart tab 等)
- `:280-350` — `C-` / `SPC` 一级 + `SPC TAB` workspace

### `spacemacs/core/core-keybindings.el`

- `:1-200` — `spacemacs/declare-prefix` / `spacemacs/set-leader-keys` / `spacemacs//init-leader-mode-map`

### `spacemacs/core/core-display-init.el`

- `:1-50` — `spacemacs|do-after-display-system-init` 宏

### `spacemacs/core/core-themes-support.el`

- `:42-260` — 300+ 主题到包名映射
- `:271-321` — `spacemacs/load-theme` / `spacemacs/cycle-spacemacs-theme`

### `spacemacs/layers/+spacemacs/spacemacs-navigation/packages.el`

- `:38-105` — `symbol-highlight-transient-state`（hydra 范例）
- `:248-291` — `transient-cycles` 循环

### `spacemacs/layers/+spacemacs/spacemacs-layouts/packages.el`

- `:36-115` — `eyebrowse` 集成 + `workspaces-transient-state`
- `:115-280` — `persp-mode` 集成 + `layouts-transient-state`

### `spacemacs/layers/+spacemacs/spacemacs-layouts/config.el`

- `:38-70` — `spacemacs-layouts-restricted-functions`（buffer 隔离 hook）
- `:80-113` — `spacemacs-generic-layout-names`（自动命名）

### `spacemacs/layers/+spacemacs/spacemacs-modeline/packages.el`

- `:24-50` — 多种 modeline 包的 condition 加载

---

## 13. 结语：doom 范式 vs spacemacs 范式

**doom 范式的核心**（5 个字）：

> **统一 + 集中**

- 一个 `map!` 宏承担所有
- 一个 `set-popup-rule!` 承担所有 popup
- 一个 `+workspaces` 模块承担所有 workspace
- `which-key` 配置集中在一处 (`doom-keybinds.el:235-256`)

**spacemacs 范式的核心**（5 个字）：

> **分层 + 解耦**

- leader 描述和绑定解耦（`declare-prefix` vs `set-leader-keys`）
- workspace 拆为 layouts（persp）+ workspaces（eyebrowse）
- transient-state 是独立抽象
- 每个 layer 自治

**选择建议**:

- **写小型配置（< 200 行）** → doom 范式（学习成本低，命名统一）
- **写大型配置（> 1000 行）** → spacemacs 范式（概念清晰，组件可替换）
- **混合** → 拿 `map!` 宏 + doom popup 体系 + spacemacs transient-state

---

_本文档为研究草稿,基于 2026-06-08 时点的 doomemacs 和 spacemacs HEAD 代码。所有行号引用应视为"近似位置",代码可能因 commit 而漂移。_
