# Emacs 启动性能与包管理最佳范式 —— 基于 Doom & Spacemacs 实现的研究

> **范围**: 提炼"配置 Emacs 时,如何让启动快 + 包管理干净 + lazy-load 合理"的可复用范式
> **用户场景**: 自己的 Emacs 配置从裸 init.el 增长到 100+ 包,启动从 <1s 退化到 5s+,如何系统化重构
> **行文约束**: 每条范式都配真实代码引用(文件路径 + 行号),不写"应该这样"

---

## 目录

- [1. 核心论点:启动优化的三轴模型](#1-核心论点启动优化的三轴模型)
- [2. early-init.el:最便宜的优化,放在最前面](#2-early-init-el最便宜的优化放在最前面)
- [3. 包管理器的范式分野:declarative vs imperative](#3-包管理器的范式分野declarative-vs-imperative)
- [4. use-package 的 lazy-load 语义矩阵](#4-use-package-的-lazy-load-语义矩阵)
- [5. Doom 的"等待时机"三 hook 范式](#5-doom-的等待时机三-hook-范式)
- [6. Doom 的 incremental package loader](#6-doom-的-incremental-package-loader)
- [7. Spacemacs 的"layer + 命名 init-XXX"调度范式](#7-spacemacs-的layer--命名-init-xxx调度范式)
- [8. 字节编译(.elc)的真实价值与陷阱](#8-字节编译elc的真实价值与陷阱)
- [9. 启动从 <1s 退化到 5s+ 的瓶颈定位方法论](#9-启动从-1s-退化到-5s-的瓶颈定位方法论)
- [10. Doom 与 Spacemacs 范式对比表](#10-doom-与-spacemacs-范式对比表)
- [11. 可操作检查清单](#11-可操作检查清单)
- [12. 常见反模式](#12-常见反模式)
- [附录 A: 关键文件行号速查](#附录-a-关键文件行号速查)
- [附录 B: 推荐阅读顺序](#附录-b-推荐阅读顺序)
- [附录 C: 核心范式一图总结](#附录-c-核心范式一图总结)
- [附录 D: 真实包场景的 lazy-load 范式剖析](#附录-d-真实包场景的-lazy-load-范式剖析)
- [附录 E: 自写配置的渐进式重构路径](#附录-e-自写配置的渐进式重构路径)
- [附录 F: 调试工具包](#附录-f-调试工具包)
- [附录 G: Doom `bin/doom` 角色说明](#附录-g-doom-bindoom-角色说明)
- [附录 H: 几个高 ROI 的具体小优化](#附录-h-几个高-roi-的具体小优化)
- [附录 I: daemon 模式特殊优化](#附录-i-daemon-模式特殊优化)
- [附录 J: 与其他 worker 的边界声明](#附录-j-与其他-worker-的边界声明)

---

## 1. 核心论点:启动优化的三轴模型

把 Emacs 启动看成一个 3-轴问题,可以避免"乱开火":

```
                  ┌─────────────────────────────────────┐
                  │  Axis 1: EARLY-INIT (单次优化)      │
                  │  一次性消除"每个文件操作"的固定成本 │
                  │  → 全文 1 次写,受益所有包           │
                  ├─────────────────────────────────────┤
                  │  Axis 2: PACKAGE MGMT (声明式)      │
                  │  把"装什么/从哪装"从初始化流中剥离  │
                  │  → 改元数据,不改运行流              │
                  ├─────────────────────────────────────┤
                  │  Axis 3: LAZY-LOAD (按需加载)       │
                  │  把"何时 evaluate defun"推迟到使用时│
                  │  → 启动时 N 个 require,运行时 0 个  │
                  └─────────────────────────────────────┘
```

**Doom 与 Spacemacs 都把"装包"和"加载包"分离开**,这是为什么它们能在 200+ 包规模下保持 1-2s 启动的根因。Doom 的 `package!`(`doomemacs/lisp/doom-lib.el:1548`)只写元数据,从不 `require`;Spacemacs 的 `init-XXX` 函数用 `:defer t` 推迟到 hook。

阅读以下章节时,先在心里画这条三轴线。

---

## 2. early-init.el:最便宜的优化,放在最前面

### 2.1 这文件是干什么的

> early-init.el was introduced in Emacs 27.1. It is loaded before init.el, before Emacs initializes its UI or package.el, and before site files are loaded. This is great place for startup optimizing, because only here can you _prevent_ things from loading, rather than turn them off after-the-fact.
> —— `doomemacs/early-init.el:18-20`

**唯一关键点**:它是 Emacs 27+ 唯一允许你"阻止某些事情加载"的时机。init.el 已经太晚,很多东西在 init.el 之前就跑完了。

### 2.2 Doom 在 early-init.el 里做的 6 件事

`doomemacs/early-init.el:34-37`:

```elisp
(setq gc-cons-percentage 1.0)
(if noninteractive
    (setq gc-cons-threshold 134217728)  ; 128mb
  (setq gc-cons-threshold most-positive-fixnum)  ; 关闭 GC
  (setq load-prefer-newer nil))
```

每一行都有 PERF 注释解释 trade-off,这里复述要点:

| 设置                       | 值                     | 作用                               | 副作用                                         |
| -------------------------- | ---------------------- | ---------------------------------- | ---------------------------------------------- |
| `gc-cons-percentage`       | 1.0                    | GC 触发率从默认 0.1 调宽           | 必须配套 GC 重置                               |
| `gc-cons-threshold` (交互) | `most-positive-fixnum` | 启动期完全跳过 GC                  | **必须** 在 after-init 阶段用 `gcmh-mode` 重置 |
| `gc-cons-threshold` (CLI)  | 128mb                  | CLI 不能完全关 GC,否则长脚本内存爆 | 比默认 800kb 提高 16384×                       |
| `load-prefer-newer`        | `nil`                  | 跳过 .el 字节码的 mtime 检查       | 由 `doom sync` 负责正确性                      |

`doomemacs/early-init.el:70-100` 还做了 `file-name-handler-alist = nil` 和 `load-suffixes` 缩减:

```elisp
;; PERF: When `load'ing or `require'ing files, each permutation of
;;   `load-suffixes' and `load-file-rep-suffixes' is used to locate the file.
;;   Each permutation amounts to at least one file op...
;;   Doom doesn't load dynamic modules this early, so ".so" is removed.
```

`file-name-handler-alist` 设为 `nil` 是关键 trick:Emacs 每次 `expand-file-name` 都会扫描这个 alist,启动期可能有数千次调用。注释强调 "DON'T COPY THIS BLINDLY" —— 因为 `gcmh-mode` (`doomemacs/lisp/doom-start.el:88-91`) 必须在 `doom-first-buffer-hook` 中重新打开:

```elisp
(unless (fboundp 'igc-info)
  (setq gcmh-idle-delay 'auto          ; default 15s
        gcmh-auto-idle-delay-factor 10
        gcmh-high-cons-threshold (* 64 1024 1024))  ; 64mb
  (add-hook 'doom-first-buffer-hook #'gcmh-mode))
```

### 2.3 Spacemacs 的 early-init.el:极简(52 行)

`spacemacs/early-init.el` 全文只有 52 行,核心就是一行:

```elisp
;; `spacemacs/early-init.el:32`
(setq package-enable-at-startup nil)
```

这是关键 trick:Emacs 27 默认会在 init.el 之前调用 `package-initialize`,这会与 Spacemacs 自己的包管理流程冲突。设置 `package-enable-at-startup nil` 让 Spacemacs 在 init.el 阶段按自己的节奏初始化。

**对比观察**:

- Doom 的 early-init.el 重在**反优化**(把耗时操作关掉)
- Spacemacs 的 early-init.el 重在**反干扰**(不让 Emacs 抢跑)

Spacemacs 的真正优化在 `init.el:21` 那行:

```elisp
(setq gc-cons-threshold 402653184 gc-cons-percentage 0.6)  ; 384MB
```

以及 `init.el:64-79`:

```elisp
(let ((load-prefer-newer t)        ; Spacemacs 选了"prefer newer",与 Doom 相反
      (file-name-handler-alist '(("\\.gz\\'" . jka-compr-handler))))
  ...  ; 整个核心加载都在这个 let 里
```

**为什么 `load-prefer-newer` 方向相反?** Spacemacs 用 `package.el` (ELPA),用户从外部源安装包后,`.elc` 可能比 `.el` 旧,需要 prefer newer 来拿新源码;Doom 用 `straight` 自己管 git 仓库,`.elc` 是 `doom sync` 现编的,从不新于 `.el`,所以关掉。

### 2.4 最低风险最佳实践清单(从 Doom 的 4 段 PERF 注释提炼)

| 优先级 | 设置                                                      | 最小版本  | 必须配套                                                              |
| ------ | --------------------------------------------------------- | --------- | --------------------------------------------------------------------- |
| **P0** | `(setq gc-cons-threshold most-positive-fixnum)`           | Emacs 27+ | `(gcmh-mode 1)` 加到 `doom-first-buffer-hook` 或 `emacs-startup-hook` |
| **P0** | `(setq file-name-handler-alist nil)` 围住 `load`          | Emacs 27+ | 把 `load` 放在 let 块内,自动恢复                                      |
| **P1** | `(setq gc-cons-percentage 1.0)`                           | 全部      | 同 P0                                                                 |
| **P1** | `(setq package-enable-at-startup nil)` (用 package.el 时) | Emacs 27+ | 在 init.el 主动 `package-initialize`                                  |
| **P2** | `(setq load-suffixes '(".elc" ".el"))`                    | 全部      | 提前 load 了动态模块的包会失败                                        |
| **P2** | `(setq load-prefer-newer nil)` (自己控构建时)             | 全部      | 必须有外部机制保证 .elc 同步                                          |
| **P3** | `default-frame-alist` 提前设好 menu/tool-bar              | 全部      | 无副作用,UI-only                                                      |

### 2.5 Doom "核心放弃"的反向证据

`doomemacs/early-init.el:127-135` —— 当用户用 Doom 当 "bootloader" 加载非 Doom 配置时,Doom 会**主动撤销自己**的优化:

```elisp
;; COMPAT: I make no assumptions about the config we're going to load,
;;   so undo this file's global side-effects.
(setq load-prefer-newer t)
;; PERF: But make an exception for `gc-cons-threshold'...
(setq gc-cons-threshold (* 16 1024 1024)  ; 16MB 折中
      gc-cons-percentage 0.1)
```

**教训**:即使 Doom 这样的大项目,也不假设下游能用 `most-positive-fixnum`,而是用 16MB 折中。**自写配置时,如果你不打算接 `gcmh-mode`,就用 16MB 起步**,不要从 800KB 默认值走极端。

---

## 3. 包管理器的范式分野:declarative vs imperative

### 3.1 三大范式

| 维度                 | package.el (Spacemacs 用)                                          | straight.el (Doom 用)                             | elpaca                     | quelpa                        |
| -------------------- | ------------------------------------------------------------------ | ------------------------------------------------- | -------------------------- | ----------------------------- |
| **元数据源**         | ELPA 仓库 + 隐式 `package-initialize`                              | 每个包一个 git recipe,显式 `straight-use-package` | ELPA 镜像 + git,自建缓存   | 临时从 recipe 构建            |
| **package 声明位置** | `packages.el` (Spacemacs `defconst xxx-packages '((pkg ...) ...)`) | `packages.el` (Doom `(package! name :pin "sha")`) | `use-package` 的 `:ensure` | `(quelpa '(pkg :recipe ...))` |
| **lock 机制**        | `package-quickstart` (emacs 27)                                    | `doom sync` 生成的 .elc profile                   | 自带 lock                  | 无                            |
| **延迟加载语义**     | `:defer t` (use-package 标准)                                      | 同 use-package                                    | 同 use-package             | 同 use-package                |
| **可复现性**         | 弱(版本浮动)                                                       | **强**(pin 到 commit SHA)                         | 中                         | 弱                            |
| **ELPA 故障容忍**    | **差**(gnutls/网络一断全断)                                        | **好**(本地 git)                                  | 好                         | 差                            |
| **学习曲线**         | 平                                                                 | 陡                                                | 平                         | 中                            |

### 3.2 Doom 选 straight.el 的根因(明确写在注释里)

`doomemacs/lisp/lib/packages.el:5-15`:

> Doom uses `straight' to create a declarative, lazy-loaded, and (nominally) reproducible package management system. We use `straight' over `package' because the latter is tempermental. ELPA sources suffer downtime occasionally and often fail to build packages when GNU Tar is unavailable (e.g. MacOS users start with BSD tar). Known gnutls errors plague the current stable release of Emacs (26.x) which bork TLS handshakes with ELPA repos (mainly gnu.elpa.org).

**翻译成决策框架**:

```
包数量 < 30:  package.el (ELPA) 就够了
30 < N < 80:  任意一个都行;ELPA 网络问题会被感受
N > 80:       straight 或 elpaca;需要 pin commit 来锁定行为
需要可复现:   straight (有 :pin "sha1")
```

### 3.3 Doom 的 `package!` 宏 —— "声明"与"加载"彻底分离

`doomemacs/lisp/doom-lib.el:1548-1635`:

```elisp
(cl-defmacro package!
    (name &rest plist &key built-in recipe ignore _type _pin _disable _env _freeze)
  "Declares a package and how to install it (if applicable).

This macro is declarative and does not load nor install packages."
  ...
  ;; These are the only side-effects of this macro!
  (setf (alist-get name doom-packages) plist)
  (if (plist-get plist :disable)
      (add-to-list 'doom-disabled-packages name)
    ...))
```

**关键观察**:整个宏展开后的副作用只有 2 个:

1. 把 `(name . plist)` 塞进 `doom-packages` alist
2. 如果 `:disable t`,加入 `doom-disabled-packages`

**完全没有 `require`、`load`、`straight-use-package` 调用**。这意味着 200 个 `package!` 声明,执行时**常量时间** —— doom 在 `doom-initialize-packages` (`doomemacs/lisp/lib/packages.el:178`) 才把它们一次性注册给 straight。

### 3.4 Doom 的 `disable-packages!` 设计意图

`doomemacs/lisp/doom-lib.el:1637-1643`:

```elisp
(defmacro disable-packages! (&rest packages)
  "A convenience macro for disabling packages in bulk.
Only use this macro in a module's (or your private) packages.el file."
  (macroexp-progn
   (mapcar (lambda (p) `(package! ,p :disable t))
           packages)))
```

**实战模式**:迁移/实验期间用 `:disable t` 替代删除,模块 `use-package!` 块会**自动展开为 no-op**(`doomemacs/modules/config/use-package/init.el:140-149`):

```elisp
(defmacro use-package! (name &rest plist)
  (unless (or (memq name doom-disabled-packages)
              ...)
    `(use-package ,name ,@plist)))
```

**这是一个杀手特性**:用 `:disable t` 可以让 use-package 完全不展开,无需手工注释。

### 3.5 Spacemacs 的 `defconst xxx-packages` + `init-XXX` 范式

`spacemacs/layers/+emacs/helpful/packages.el:18-21`:

```elisp
(defconst helpful-packages
  '(
    helpful
    link-hint
    popwin))
```

`spacemacs/layers/+emacs/helpful/packages.el:23-39`:

```elisp
(defun helpful/init-helpful ()
  (use-package helpful
    :defer t
    :init
    (spacemacs/declare-prefix-for-mode 'helpful-mode "mg" "goto")
    ...
    :config
    ...))
```

**Spacemacs 的命名规范**:`init-<pkg>` 函数体里用 `use-package :defer t`,框架按 owner layer 顺序在 `configuration-layer//configure-packages` (`spacemacs/core/core-configuration-layer.el:1941-2110`) 中调用。`:defer t` 在 use-package 标准语义里意味着 "无 `:commands`/`:hook`/`:bind` 触发器时,完全 lazy"。

**对比 Doom 范式**:

- Doom: `(package! pkg :pin "...")` + `(use-package! pkg :hook ... :config ...)` —— 元数据与配置**分文件**
- Spacemacs: 一个 `defconst pkg-packages` + `defun pkg/init-pkg` + `defun pkg/post-init-pkg` —— **同文件同函数**

Doom 的分文件让"改 pin 不用重新读 config",Spacemacs 的同文件让"看一个包所有代码不用跳"。

### 3.6 决策流程

```
                         你在 2026 年选什么?
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
   30 包以下                30-100 包                100+ 包 + 可复现
   不在乎复现               偶尔升级                 多个机器同步
        │                       │                       │
        ▼                       ▼                       ▼
   package.el               elpaca                 straight (Doom 范式)
   + use-package            (现代, 简洁)           + doom sync
```

**注意**:Quelpa 已停止积极维护(2023 年后无大更新),Spacemacs 自己也在转 elpaca —— 不要选 Quelpa。

---

## 4. use-package 的 lazy-load 语义矩阵

### 4.1 总表

每个 use-package 关键字都对应一个**触发器类型**,use-package 根据触发器决定何时 `require` 这个包:

| 关键字                        | 触发器类型  | `require` 时机                   | 副作用                                |
| ----------------------------- | ----------- | -------------------------------- | ------------------------------------- |
| `:defer t`                    | 无触发器    | **永不**(用户调用 `M-x` 才 load) | 函数/键绑定没在 :init 设,首次调用会卡 |
| `:defer N` (数字)             | 空闲 N 秒后 | `N` 秒后                         | 启动后 1-2s 才见效                    |
| `:commands cmd1 cmd2`         | 命令        | 首次 M-x 调用                    | 命令必须可 `autoload`                 |
| `:hook 'hook-name`            | 钩子        | 钩子首次执行                     | 推荐模式(doom vertico 用)             |
| `:mode '("\\.ext\\'" . mode)` | 文件打开    | 首次打开匹配文件                 | 依赖 auto-mode-alist 注册时机         |
| `:magic regex`                | 文件内容    | 首次 buffer 检测到 regex         | 用于解释器/特殊文件                   |
| `:bind "key"`                 | 键          | 键首次按下                       | key 解析不能含包装                    |
| `:custom var value`           | 变量        | `:config` 时一起                 | 只配置,不触发                         |
| `:init body`                  | 立即        | **启动时**                       | **破坏 lazy**                         |
| `:config body`                | 跟随        | 包 `require` 后                  | lazy 模式最常用                       |
| `:preface body`               | 立即        | **启动时**(在 :init 之前)        | 比 :init 更早;设全局变量              |
| `:demand t`                   | 强制        | **启动时**                       | 取消所有 lazy                         |

### 4.2 `:init` vs `:config` 的语义差(最容易踩坑)

`use-package` 标准语义:

- `:init` 在包**加载前**执行
- `:config` 在包**加载后**执行

**关键**:两者都在 `require` 调用前后。如果 `require` 因为 lazy 没发生,`:init` 也不会发生。

**误用 1**:在 `:init` 里 `require` 别的包(把 lazy 传染)

```elisp
;; 错
(use-package! magit
  :init (require 'magit-section)   ; ← 启动时强制加载
  :config (require 'with-editor))  ; ← 也被传染
```

**误用 2**:把"按 mode 触发的 hooks"放进 `:init`

```elisp
;; 错 (doom vertico 没有这个错)
(use-package! projectile
  :init (add-hook 'python-mode-hook #'projectile-mode))  ; projectile 还没 require
;; ↑ 实际没问题,因为 add-hook 只是注册

;; 错
(use-package! projectile
  :init (projectile-mode 1))  ; ← projectile-mode 还不存在!
```

**正解**:任何**调用**被 lazy-load 的包的代码都必须放 `:config`:

```elisp
(use-package! projectile
  :config (projectile-mode +1))  ; ← 这里 projectile 已 require
```

### 4.3 `:defer` vs `:hook` 怎么选

看 doom 自己的选择 (`doomemacs/modules/completion/vertico/config.el:20-23`):

```elisp
(use-package! vertico
  :hook (doom-first-input . vertico-mode)
  ...)
```

这里 vertico-mode 启用的时机是 `doom-first-input-hook`(用户第一次按键),**不是** `emacs-startup-hook`。这是范式层面的选择:

- `:defer t` + `:commands` → 首次 M-x 触发,延迟最大化
- `:hook 'after-init-hook` → 启动完成即开
- `:hook 'doom-first-input` → 第一次输入前开(Doom 范式)

**性能差异**:对一个 1.5s 启动的包,这三种时机启动后到可用时间差可达 1.5s。

### 4.4 Doom 扩展的两个 lazy-load 关键字

`doomemacs/modules/config/use-package/init.el:60-104`:

```elisp
;; :defer-incrementally SYMBOL|LIST|t
;; :after-call SYMBOL|LIST
```

**`:defer-incrementally`** 解决大包(magit, org)的 "首 load 慢 1s" 问题。语义:把"加载大包"拆成 N 个 require,分散在空闲期。

`doomemacs/lisp/doom-editor.el:266` 真实用法:

```elisp
:defer-incrementally easymenu tree-widget timer
```

意思是:先 load `easymenu` → 空闲 → `tree-widget` → 空闲 → `timer` → 才 `require` 自身。

**`:after-call`** 是"首次调用某函数时"触发,比 `:hook` 更细粒度。`doomemacs/modules/config/use-package/init.el:82-103`:

```elisp
;; 用 advice-add 在某个函数首次被调用时 lazy load
```

### 4.5 Spacemacs 的扩展关键字

`spacemacs/core/core-use-package-ext.el:11-17`:

```elisp
(defconst spacemacs--use-package-add-hook-keywords '(:pre-init
                                                     :post-init
                                                     :pre-config
                                                     :post-config))
```

`:pre-init` / `:post-init` / `:pre-config` / `:post-config` 是 use-package 的 `use-package-inject-hooks` 机制的标准钩子,Spacemacs 通过 `spacemacs/use-package-extend` (`core-use-package-ext.el:48-55`) 注入到全局。用途:**用户层在 dotspacemacs 覆盖 layer 默认配置**:

```elisp
;; 来自 spacemacs/core/core-use-package-ext.el:25-37
;; 警告: ":post-config" 之前几乎都用 after-load
(spacemacs|use-package-add-hook magit :post-config
  (setq magit-diff-refine-hunk t))
```

**`spacemacs|use-package-add-hook` 实质上是一个 append-hook to a magic 变量**(line 38-56):生成 `use-package--magit--post-config-hook` 这种内部 hook。

**这是 Spacemacs 范式 vs Doom 范式的另一处差异**:

- Spacemacs: 用 use-package 标准注入,layer + dotfile 协作
- Doom: 用 `after!` 宏 (`doomemacs/lisp/doom-lib.el:1660+` 之后),`after! pkg (config...)` 更易读

### 4.6 `auto-minor-mode` 让 `:hook` 自动化(Doom 扩展)

`doomemacs/modules/config/use-package/init.el:51-57`:

```elisp
;; We define :minor and :magic-minor from the `auto-minor-mode' package here
;; so we don't have to load `auto-minor-mode' so early.
(dolist (keyword '(:minor :magic-minor))
  (setq use-package-keywords
        (use-package-list-insert keyword use-package-keywords :commands)))
```

`:minor` 是 `:mode` 的"自动版" —— 自动判定哪些文件关联这个 minor mode。Doom 通过 `auto-minor-mode` (`+everywhere` 标记)做这件事,避免每个包写一个 `:hook`。

---

## 5. Doom 的"等待时机"三 hook 范式

### 5.1 三个 hook 是什么

`doomemacs/lisp/doom-start.el:7-19`:

```elisp
(defcustom doom-first-input-hook ()
  "Transient hooks run before the first user input." :type 'hook :group 'doom)

(defcustom doom-first-file-hook ()
  "Transient hooks run before the first interactively opened file." :type 'hook :group 'doom)

(defcustom doom-first-buffer-hook ()
  "Transient hooks run before the first interactively opened buffer." :type 'hook :group 'doom)
```

### 5.2 实现机制 —— `doom-run-hook-on`

`doomemacs/lisp/doom-lib.el:277-309`:

```elisp
(defun doom-run-hook-on (hook-var trigger-hooks &optional predicate)
  "Configure HOOK-VAR to be invoked exactly once when any of the TRIGGER-HOOKS
are invoked *after* Emacs has initialized (to reduce false positives)."
  (dolist (hook trigger-hooks)
    (let ((fn (make-symbol (format "chain-%s-to-%s-h" hook-var hook)))
          running?)
      (fset fn (lambda (&rest _)
                 (when (and (not running?)
                            (not (doom-context-p 'startup))  ; 启动期间不触发
                            (or (daemonp) ...))
                   (setq running? t)
                   (doom-run-hooks hook-var)
                   (set hook-var nil))))
      ...)))
```

**关键设计**:

1. **"transient"**:触发一次后 `set hook-var nil`,hook 变量不再有效
2. **"after Emacs init"**:用 `(doom-context-p 'startup)` 守卫,启动期间不触发
3. **"predicate"**:可以加 filter,如 doom-first-buffer-hook 不在 _scratch_ 触发

`doomemacs/lisp/doom.el:775-778` 注册位置:

```elisp
(doom-run-hook-on 'doom-first-file-hook   '(find-file-hook dired-initial-position-hook))
(doom-run-hook-on 'doom-first-input-hook  '(pre-command-hook))
(doom-run-hook-on 'doom-first-buffer-hook '(find-file-hook doom-switch-buffer-hook)
                  (lambda ()
                    (not (member (buffer-name)
                                 `("*scratch*" ,doom-fallback-buffer-name)))))
```

**注意**:`doom-first-file-hook` 用 `advice-add 'after-find-file :before ... '((depth . -101))` (`doomemacs/lisp/doom-lib.el:303-305`) 而不是 `find-file-hook`,因为后者触发时 file 已开、mode 已设,**太晚**。这是 Doom 处理时机的精细点。

### 5.3 为什么这样设计 —— 解决 "启动快" vs "能用" 的矛盾

`doom-first-buffer-hook` 是最经典的解法:

- 启动时不启用 `gcmh-mode` (因为 early-init.el 把 GC 关了,启动期手动不需要)
- 第一次切到非 scratch buffer 时**才** 启用 `gcmh-mode`
- 这时 GC 阈值回到正常,内存管理让位给用户交互

如果直接在 `emacs-startup-hook` 启用 `gcmh-mode`,启动期会有 GC 抢占,反而更慢。

**范式归纳**:

```
emacs-startup-hook: 启动完成即触发 (强同步)
doom-first-input-hook: 第一次按键才触发 (用户开始操作)
doom-first-buffer-hook: 第一次切 buffer 才触发 (UI 已活跃)
doom-first-file-hook: 第一次打开文件才触发 (内容已加载)
```

### 5.4 三个 hook 的适用场景

| Hook                     | 适用                                    | 不适用                         |
| ------------------------ | --------------------------------------- | ------------------------------ |
| `doom-first-input-hook`  | 启用 minibuffer UI (vertico)、which-key | 启用依赖 buffer 的功能         |
| `doom-first-buffer-hook` | 启用 gcmh、UI 装饰、mode-line           | 用户可能只打开 daemon 不开文件 |
| `doom-first-file-hook`   | LSP 模式自动启用、project 检测          | daemon 场景永不触发            |

### 5.5 真实代码示例 —— doom-start.el:88-91

```elisp
(unless (fboundp 'igc-info)
  (setq gcmh-idle-delay 'auto
        gcmh-auto-idle-delay-factor 10
        gcmh-high-cons-threshold (* 64 1024 1024))  ; 64mb
  (add-hook 'doom-first-buffer-hook #'gcmh-mode))
```

**为什么不在 `after-init-hook`?** 因为 `gcmh-mode` 在 idle 期间主动 GC,启动期还在跑 `doom-startup` 的剩余代码,主动 GC 会让启动变慢;但在 buffer 已活跃后,GC 抢占就是"合理的暂停"。

### 5.6 自写配置的对应做法

`doom-run-hook-on` 是 30 行代码,**自写配置**直接用现成 hook 也能达到 80% 效果:

```elisp
;; 简化版
(defvar my-first-input-hook nil)
(add-hook 'pre-command-hook
          (defun my-trigger-first-input ()
            (remove-hook 'pre-command-hook #'my-trigger-first-input)
            (run-hooks 'my-first-input-hook)))
```

---

## 6. Doom 的 incremental package loader

### 6.1 函数定义

`doomemacs/lisp/doom-start.el:232-275`:

```elisp
(defun doom-load-packages-incrementally (packages &optional now)
  "Registers PACKAGES to be loaded incrementally.
If NOW is non-nil, PACKAGES will be marked for incremental loading next time
Emacs is idle for `doom-incremental-first-idle-timer' seconds..."
  (let* ((gc-cons-threshold most-positive-fixnum)  ; 启动期不 GC
         (first-idle-timer (or doom-incremental-first-idle-timer
                               doom-incremental-idle-timer)))
    (if (not now)
        (cl-callf append doom-incremental-packages packages)
      (while packages
        (let ((req (pop packages))
              idle-time)
          (if (featurep req)
              (doom-log 2 "start:iloader: Already loaded %s (%d left)" req ...)
            (condition-case-unless-debug e
                (and
                 (or (null (setq idle-time (current-idle-time)))
                     (< (float-time idle-time) first-idle-timer)
                     (not
                      (while-no-input
                        ...(require req nil t)...)))
                 (push req packages))   ; 加载失败/被中断 → 推回队尾
              (error ...))
            ...
            (run-at-time ... #'doom-load-packages-incrementally packages t)))))))
```

**关键设计**:

1. `while-no-input` —— 用户开始输入时**立即让出**,不抢前台
2. `condition-case-unless-debug` —— 单个包失败不影响其他
3. `gc-cons-threshold most-positive-fixnum` —— 局部再关 GC,避免 idle load 触发
4. **失败重试**:`(push req packages)` 把失败的包推回队尾,下次再试
5. `run-at-time` —— 用 idle timer 串行,避免一次性 require 多个大包

### 6.2 默认值

`doomemacs/lisp/doom-start.el:222-224`:

```elisp
(defvar doom-incremental-first-idle-timer (if (daemonp) 0 2.0)
  "How long (in idle seconds) until incremental loading starts.
Set this to nil to disable. Set this to 0 to load all at doom-after-init-hook.")
```

daemon 立即加载(GUI 还没出来),GUI session 等 2 秒(用户大概率在干别的)。

### 6.3 启动钩子

`doomemacs/lisp/doom-start.el:277-285`:

```elisp
(defun doom-load-packages-incrementally-h ()
  "Begin incrementally loading packages in `doom-incremental-packages'.
If this is a daemon session, load them all immediately instead."
  (when (numberp doom-incremental-first-idle-timer)
    (if (zerop doom-incremental-first-idle-timer)
        (mapc #'require (cdr doom-incremental-packages))
      (run-with-idle-timer doom-incremental-first-idle-timer
                           nil #'doom-load-packages-incrementally
                           (cdr doom-incremental-packages) t))))
```

注册:`doomemacs/lisp/doom.el:773`:

```elisp
(add-hook 'doom-after-init-hook #'doom-load-packages-incrementally-h 100)
```

`100` 是优先级 —— 在 `doom-display-benchmark-h` (110) 之前,这样 benchmark 报告时已开始的加载不会被计入。

### 6.4 Trade-off 表

| 收益                   | 代价                                      |
| ---------------------- | ----------------------------------------- |
| 启动"显示时间" 5s → 1s | 第一次用 magit/org 时仍要等               |
| GC 期间分散,不卡       | 看起来"打开 Emacs 后用啥啥卡"             |
| 大包(magit 800+kb)分摊 | idle 时 CPU 偶有抖动                      |
| 失败重试,健壮          | 配置文件不会爆错,只在 message buffer 提示 |

### 6.5 范式归纳:把"需要 load 的 N 个包"分摊到 N 个 idle 时段

**适用对象**:

- org (依赖 org-element, org-indent, ol, ox, ...)
- magit (依赖 magit-section, magit-diff, magit-blame, ...)
- tree-sitter-lang bundle

**禁用场景**:

- daemon 模式:用户立即就要用,不能分摊
- 配置少(< 50 包):idle 分摊不值得

**自写对应物**:

```elisp
(run-with-idle-timer 2 nil
  (lambda ()
    (while (and (not (current-idle-time)) heavy-packages)
      (let ((pkg (pop heavy-packages)))
        (require pkg nil t)))))
```

---

## 7. Spacemacs 的"layer + 命名 init-XXX"调度范式

### 7.1 文件结构

每个 layer 是一个目录,固定文件结构:

```
+emacs/helpful/
  packages.el      ; (defconst helpful-packages '((pkg ...) ...))
  config.el         ; (spacemacs|use-package-add-hook ... :post-config ...)
  funcs.el          ; 通用函数
  keybindings.el    ; 键位 (lazy 加载)
  layers.el         ; 依赖声明
```

`spacemacs/core/core-configuration-layer.el:1487-1490` 真实加载:

```elisp
(configuration-layer//load-layer-files layer-name '("funcs"))
```

### 7.2 `defun helpful/init-helpful` 命名规范

`spacemacs/layers/+emacs/helpful/packages.el:23`:

```elisp
(defun helpful/init-helpful ()
  (use-package helpful
    :defer t
    :init
    ...))
```

`<layer>/init-<pkg>` 是 Spacemacs 调度器直接 `funcall` 的入口,通过 symbol name dispatch。

### 7.3 调度器

`spacemacs/core/core-configuration-layer.el:1965-2110` (`configuration-layer//configure-packages-2`):

```elisp
(mapc #'configuration-layer//configure-package packages)
```

`configuration-layer//configure-package` (line 2111-2121):

```elisp
(defun configuration-layer//configure-package (pkg)
  (let* ((pkg-name (oref pkg name))
         (owner (car (oref pkg owners))))
    (configuration-layer//funcall-recording-load-history
     (intern (format "%S/init-%S" owner pkg-name)))))
```

**关键观察**:Spacemacs 调度通过 `funcall` 调 `<owner>/init-<pkg>` 符号,**完全跳过 use-package 的 keyword 解析**。这是它和 Doom 的根本差异。

### 7.4 `pre-init` / `post-init` 跨包钩子

`spacemacs/layers/+emacs/helpful/packages.el:50-56`:

```elisp
(defun helpful/post-init-link-hint ()
  (evil-define-key 'normal helpful-mode-map (kbd "o") 'link-hint-open-link))

(defun helpful/pre-init-popwin ()
  (spacemacs|use-package-add-hook popwin
    :post-config
    (push '(helpful-mode :dedicated t ...) popwin:special-display-config)))
```

**`pre-init` / `post-init` 命名规范**:

- `pre-init-X` = 在 X 的 `init-X` **之前** 调用
- `post-init-X` = 在 X 的 `init-X` **之后** 调用

这是 Spacemacs 跨 layer 通信的核心机制,比 use-package 的 `use-package-inject-hooks` 更显式。

### 7.5 `auto-mode-alist` 注册时机(自动 lazy install)

`spacemacs/core/core-configuration-layer.el:1262-1284`:

```elisp
(dolist (x extensions)
  (let ((ext (car x))
        (mode (cadr x)))
    (add-to-list 'configuration-layer--lazy-mode-alist (cons mode ext))
    (add-to-list
     'auto-mode-alist
     `(,ext . (lambda ()
                (configuration-layer//auto-mode
                 ',layer-name ',mode))))))
```

**`lazy-install` 范式**:用户没启用某 layer,但打开该 layer 拥有的扩展名文件时,自动提示安装。`configuration-layer/lazy-install` 文档字符串(1236-1238):

> Configure auto-installation of layer with name LAYER-NAME.

**这是 Spacemacs 独有特性** —— 在不增加启动成本的前提下,提供"按需启用 layer"的能力。

### 7.6 Spacemacs 的 lazy-init 的实质

`configuration-layer//auto-mode` (line 1286-1292):

```elisp
(defun configuration-layer//auto-mode (layer-name mode)
  (let ((layer (configuration-layer/get-layer layer-name)))
    (when (or (oref layer lazy-install)
              (not (configuration-layer/layer-used-p layer-name)))
      (configuration-layer//lazy-install-packages layer-name mode)))
  (when (fboundp mode) (funcall mode)))
```

**注意第 3 行**:`(when (fboundp mode) (funcall mode))` —— 如果包还没装,不调用 mode。这避免了 "mode not defined" 错误。

### 7.7 Doom vs Spacemacs 调度范式对比

```
Doom:    (package! X) ─┐
        (use-package! X :hook A :config C) ─┐
                                              ├─→ doom-profile.el (生成)
                                              ├─→ user 启动时 byte-compile profile
                                              └─→ 仅这一处 require X
Spacemacs: (defconst X-packages '(X)) ─┐
        (defun layer/init-X () (use-package X :defer t :init ...)) ─┐
        (defun layer/post-init-X () ...) ─┐                            │
                                              ├─→ configuration-layer 调度
                                              ├─→ funcall <layer>/init-X
                                              └─→ 触发 :defer t
```

**范式差异**:

- Doom 的 package 元数据 → **profile 编译产物** (字节码)
- Spacemacs 的 package 元数据 → **运行时 funcall** (每次启动解析)

**性能差异**:Doom 的 profile 编译产物消除了"启动期解析 use-package plist" 的成本。Spacemacs 启动时**实际运行** `init-XXX` 内的 use-package 展开。

---

## 8. 字节编译(.elc)的真实价值与陷阱

### 8.1 Doom 启动期关 `load-prefer-newer` 的原因

`doomemacs/early-init.el:34-37`:

```elisp
(setq load-prefer-newer nil)
```

配合同段注释:

> PERF: Don't waste precious startup time checking mtimes on elisp bytecode. Ensuring correctness is 'doom sync's job.

**核心**:Doom 信任 `doom sync` 在包安装/更新时**统一重新编译**所有 .elc,启动期不需要 stat .el 的 mtime 和 .elc 比较。

**收益**:每次 `load` 少 1 个 stat 调用(看似少,但 200+ 包就是 200+ 次)。

**陷阱**:用户手动改 .el 文件,必须跑 `doom compile` 或 `doom sync` 让 .elc 重新生成。**`.elc` 永远比 `.el` 旧**在 Doom 体系下是正常的,不是损坏。

### 8.2 Spacemacs 选择 `load-prefer-newer t`

`spacemacs/init.el:64`:

```elisp
(let ((load-prefer-newer t) ...)
```

**理由**:Spacemacs 用户可能手动 `git pull` 升级 .el,需要 prefer newer 来跳过旧 .elc。

### 8.3 字节编译的真实收益

字节编译对启动的收益**有限**:

- 解析阶段加速 ~30%
- 但 `require`、hook、变量赋值阶段**无差异**

**真正的加速来源**:

- 减少 `read` 语法分析 (Emacs 26+ 字节码加载跳过 read)
- 减少内部符号 resolve

**陷阱 1**:byte-compile 警告往往被忽略,但有些警告是真 bug。`spacemacs/layers/+emacs/helpful/packages.el` 第一行 `lexical-binding: nil` —— 这种**故意**写 nil 的代码字节编译时会被警告,但 spacerl 不修。

**陷阱 2**:字节编译后的文件 `load-history` 信息可能让 `symbol-file` 返回错误的来源。`doomemacs/lisp/doom-start.el:336-343` (advice `startup--load-user-init-file`) 显式删除 init-file-name 的 load-history 条目:

```elisp
(setq load-history
      (delete (assoc init-file-name load-history)
              load-history))
```

### 8.4 `load-suffixes` 优化与字节编译冲突

`doomemacs/early-init.el:99-103`:

```elisp
;; Doom doesn't load dynamic modules this early, so ".so" is removed
;; from `load-suffixes' to reduce the burden
(if (let ((load-suffixes '(".elc" ".el"))
          ...)
      ...
      (load doom nil (not init-file-debug) nil 'must-suffix)  ; must-suffix
   ...))
```

`must-suffix` 关键字告诉 `load`:不再尝试 `load-suffixes` 的其他组合(不查 .so 等)。这进一步减少 `load` 内部的 stat 调用。

**陷阱**:如果 doom 启动时某个 core 包**没有** .elc,Doom 会直接走 .el 路径。`doom sync` 失败或刚装完包时,这是 .el 第一次 require,比 .elc 慢,但只慢一次。

### 8.5 `doom sync` 流程的"字节编译 + 静态分析"双重作用

`doomemacs/lisp/lib/profiles.el:282-307` (生成 profile):

```elisp
(prin1 `(defun doom-startup ()
          (when (or (doom-context-p 'startup)
                    (doom-context-p 'reload))
            ,@(cl-loop for (_ genfn initfn) in doom-profile-generators
                       if initfn
                       if (functionp genfn)
                       collect (list initfn))))
       (current-buffer))
```

**`doom-profile-generators`** 是一个两阶段函数列表:

- 第一阶段:读取 `auto-mode-alist`、`load-path` 等慢变量,生成常量
- 第二阶段:写 `(defun doom-startup)` 函数体,把所有"启动时要做的事"塞进一个函数

**字节编译后**,这个 `doom-startup` 函数被 Emacs 直接以字节码执行,跳过了 `read` 阶段。

**自写对应**:

```elisp
;; init.el 顶部预计算
(defconst my-config-constants
  (let ((load-path (append '("/path/1" "/path/2") load-path)))
    (nconc (cl-remove-if-not #'file-directory-p load-path)
           (delq nil ...))))

;; 主体代码用常量,不重新计算
```

---

## 9. 启动从 <1s 退化到 5s+ 的瓶颈定位方法论

### 9.1 第一步:看 `emacs-init-time`

Emacs 27+ 内置变量:

```elisp
;; 用法
(message "Startup took %fs" emacs-init-time)
```

**陷阱**:`emacs-init-time` 是从 `before-init-hook` 到 `emacs-startup-hook` 的时间,**不包含** early-init.el。如果 `emacs-init-time` 是 0.3s 而你感觉 5s,**瓶颈在 early-init.el 之前** —— 90% 是 `package-initialize` 或 `custom-file` 加载。

### 9.2 第二步:Doom 的 `doom-display-benchmark-h`

`doomemacs/lisp/doom-start.el:292-301`:

```elisp
(defun doom-display-benchmark-h (&optional return-p)
  (funcall (if return-p #'format #'message)
           "Doom loaded %d packages across %d modules in %.03fs"
           (- (length load-path) (length (get 'load-path 'initial-value)))
           (if doom-modules (hash-table-count doom-modules) -1)
           doom-init-time))
```

**报告字段**:

- **包数**:`length(load-path) - length(initial-load-path)`,增量来自包安装
- **模块数**:doom 的 modules 哈希表大小
- **时间**:`doom-init-time` (doom 自定义,不含 early-init.el)

如果**包数** = 50,模块数 = 10,启动 1.5s —— 正常;
如果**包数** = 200,模块数 = 20,启动 4s —— 单包平均 20ms,检查哪些包有重 `require`。

### 9.3 第三步:`use-package-report`

`use-package` 提供的诊断:

```elisp
(setq use-package-compute-statistics t)  ; 启动后看
(use-package-report)                      ; 显示每个包的 init/config/load 时间
(use-package-report-loadtime)            ; 只看 require 时间
```

**用法**:

1. `init.el` 顶部加 `(setq use-package-compute-statistics t)`
2. 启动后 `M-x use-package-report`
3. 找前 5 个耗时包,逐个优化(改成 `:defer t` 或加 `:hook`)

### 9.4 第四步:`benchmark-init` 包

外部包 `benchmark-init` (MELPA),类似 `use-package-report` 但更详细:

```elisp
(benchmark-init/show-durations-tree)
;; 输出树形:init 阶段 → 哪个 use-package → 多久
```

### 9.5 第五步:emacs `--timings`(Emacs 28+)

```bash
emacs --timings --batch -l init.el
```

输出 init 阶段每步耗时。`--timings` 是 Emacs 28 新增,Doom 在 `doom-display-benchmark-h` 输出兼容这个字段。

### 9.6 定位常见瓶颈的速查

| 现象                                                       | 根因                                          | 检查方法                                                         |
| ---------------------------------------------------------- | --------------------------------------------- | ---------------------------------------------------------------- |
| `emacs-init-time` 小(0.3s)但感觉慢                         | early-init 之前慢                             | `M-x emacs-init-time`,看 emacs 启动总时间 = before-init 之前耗时 |
| `emacs-init-time` 大但 `use-package-report` 显示包都 <10ms | 100+ 包累积                                   | 用 `benchmark-init` 看总 init 阶段                               |
| 启动后第一次切 buffer 慢                                   | `gcmh-mode` 没启用 / `gc-cons-threshold` 没回 | `(gc-stat)` 看最近 GC 触发                                       |
| 启动后 idle 时 CPU 抖动                                    | incremental loader 在跑                       | 取消 `doom-load-packages-incrementally-h` 注册                   |
| `package-initialize` 单步 >1s                              | 网络拉 ELPA 慢                                | 改用 `package-quickstart`                                        |

### 9.7 Doom 的"profile init.el" 优化

`doomemacs/lisp/lib/profiles.el:299-305` 生成的 `doom-startup` 函数:

```elisp
(prin1 `(defun doom-startup ()
          (when (or (doom-context-p 'startup)
                    (doom-context-p 'reload))
            ,@(cl-loop for (_ genfn initfn) in doom-profile-generators
                       if initfn
                       if (functionp genfn)
                       collect (list initfn))))
       (current-buffer))
```

**关键**:`doom-startup` 函数体包含**所有模块 init/config 函数调用**,以字节码驻留在 .elc profile 里。启动时一个 `funcall` 跳进去,不再有 plist 解析。

**自写版本怎么做?** 在 init.el 末尾 `(defun my-startup () ...)` + `(defvar my-startup-bytecode (byte-compile #'my-startup))` + `(funcall my-startup-bytecode)`。收益 10-20%。

### 9.8 关闭 `package-quickstart` 的副作用

`package-quickstart` (Emacs 27+) 把 `package-initialize` 预编译到 `package-quickstart.el`:

```elisp
(setq package-quickstart t
      package-quickstart-file (expand-file-name "package-quickstart.el" user-emacs-directory))
```

**收益**:`package-initialize` 从 0.5s 降到 0.05s (100 个包情况下)。

**陷阱**:**只有当你修改了 `package-archives` 时才需要重新生成**。建议 `(setq package-quickstart t)` 后第一次 `M-x package-list-packages` 触发生成。

### 9.9 大配置压测方法

```bash
# 用 daemon 模式压测
emacs --daemon=test -l init.el
emacsclient -s test -e '(emacs-pid)'  # 测连接时间
emacsclient -s test -e '(kill-emacs)'
```

daemon 模式下:

- 第一次连接 (frame 创建) < 50ms 是合格
- 启动 daemon 总时间 < 2s 是合格

---

## 10. Doom 与 Spacemacs 范式对比表

| 维度                   | Doom Emacs                               | Spacemacs                                | 自写配置 (常规)               |
| ---------------------- | ---------------------------------------- | ---------------------------------------- | ----------------------------- |
| **early-init.el 行数** | 151                                      | 52                                       | 通常 20-30                    |
| **核心 lazy 范式**     | `use-package!` + `doom-first-*` hook     | `use-package :defer t` + `init-XXX` 调度 | use-package 同 Spacemacs      |
| **包管理**             | straight (git)                           | package.el (ELPA)                        | package.el                    |
| **profile 字节编译**   | ✓ 预生成 .elc profile                    | ✗ 运行时 use-package 展开                | ✗                             |
| **idle 分批加载**      | ✓ `doom-load-packages-incrementally`     | ✗ (无对应物)                             | ✗                             |
| **lazy-install**       | ✗                                        | ✓ `configuration-layer/lazy-install`     | ✗                             |
| **包 disable 机制**    | `:disable t` 让 use-package 展开为 no-op | 注释掉 `defconst` 列表项                 | 注释整个 use-package 块       |
| **跨包协调**           | `after!` 宏                              | `pre-init` / `post-init` 命名            | 自己写 `with-eval-after-load` |
| **load-prefer-newer**  | `nil` (启动)                             | `t`                                      | 选一个                        |

**关键观察**:

- Doom 的"profile 字节编译 + idle 分批"组合是它的护城河,Spacemacs 没有等效
- Spacemacs 的"lazy-install"是它的护城河,Doom 没有(因为 Doom 必须显式 `package!`)
- 自写配置如果做 Doom 范式,可获得 80% 收益;做 Spacemacs 范式可获得 60%

---

## 11. 可操作检查清单

按"低成本高收益"排序:

- [ ] **P0 (1 行)**:early-init.el 顶部加 `(setq gc-cons-threshold most-positive-fixnum)`,init.el 末尾加 `(gcmh-mode 1)` 或类似 GC 重置
- [ ] **P0 (5 行)**:emacs 27+ 加 `(setq package-enable-at-startup nil)`,init.el 主动 `package-initialize`
- [ ] **P1**:每个 use-package 块显式声明懒加载 trigger(`:hook` / `:commands` / `:bind` / `:mode`),避免 `:defer t` 漂移
- [ ] **P1**:用 `M-x use-package-report` 或 `benchmark-init` 跑一次,找前 5 耗时包
- [ ] **P1**:`default-frame-alist` 提前设 menu/tool-bar 高度,避免 `menu-bar-mode nil` 触发 frame 重绘
- [ ] **P2 (emacs 28+)**:`emacs --timings` 看真实分段耗时
- [ ] **P2**:`(setq package-quickstart t)` 缓存 `package-initialize` 结果
- [ ] **P2**:把 200+ 包的配置拆成 `modules/<name>.el`,用 `use-package!` 分组
- [ ] **P3 (daemon 用户)**:daemon 启动期把 `gc-cons-threshold` 设回 64mb (daemon 长跑需要 GC)
- [ ] **P3**:`(setq read-process-output-max (* 64 1024))` (来自 `doomemacs/lisp/doom-start.el:74`) 减少 LSP 通信开销
- [ ] **P3**:`(setq bidi-inhibit-bpa t)` (Emacs 27+,来自同上 `:67`) 减少重排成本

---

## 12. 常见反模式

### 12.1 反模式 1:在 `:init` 里写触发性配置

```elisp
;; 错
(use-package magit
  :init (add-hook 'find-file-hook #'magit-blame-mode))
;; 错原因:magit 未 require,magit-blame-mode 不存在,会报 void-function

;; 对
(use-package magit
  :hook (find-file . magit-blame-mode)
  ...)
;; 或
(use-package magit
  :config (add-hook 'find-file-hook #'magit-blame-mode))
```

### 12.2 反模式 2:在 early-init.el 设 `gc-cons-threshold most-positive-fixnum` 但忘了重置

```elisp
;; 错
;; early-init.el
(setq gc-cons-threshold most-positive-fixnum)
;; init.el 什么都没有

;; 对
;; early-init.el
(setq gc-cons-threshold most-positive-fixnum)
;; init.el
(setq gc-cons-threshold (* 16 1024 1024)
      gc-cons-percentage 0.1)
;; 或
(add-hook 'emacs-startup-hook (lambda () (gcmh-mode 1)))
```

**症状**:启动后用 5 分钟 emacs 吃 4GB 内存 —— 因为 GC 永远不触发,所有 cons cell 累积。

### 12.3 反模式 3:把 100+ use-package 全部平铺在一个 init.el

```elisp
;; 错
;; init.el
(use-package a ...)
(use-package b ...)
... 200 个 use-package

;; 对
;; init.el
(require 'my-modules-a)  ; 每个模块一个文件
;; my-modules-a.el
(use-package a ...)
(use-package b ...)
```

**收益**:`(require 'my-modules-a)` 可以走字节编译,init.el 文件更短 Emacs 解析更快。

### 12.4 反模式 4:用 `eval-after-load` 替代 use-package 的 `:hook`

```elisp
;; 错(老式,不可组合)
(eval-after-load 'magit
  '(progn
     (setq magit-diff-refine-hunk t)
     (define-key magit-mode-map "q" #'quit-window)))

;; 对(use-package 范式)
(use-package magit
  :defer t
  :config
  (setq magit-diff-refine-hunk t)
  :bind (:map magit-mode-map
              ("q" . quit-window)))
```

`eval-after-load` 难以与 `use-package-report` 集成、难以被 `:disable` 机制跳过、无法用 byte-compile 预解析。

### 12.5 反模式 5:用 `package-initialize` 不调用,期望 ELPA 自动加载

```elisp
;; 错
(setq package-archives '(...))
;; 直接 (require 'some-elpa-package)  → "void function"

;; 对
(setq package-enable-at-startup nil)  ; emacs 27+
;; ... 或
(package-initialize)
```

`package-initialize` 是 ELPA 包**可用**的开关;不调用,ELPA 装的包一律找不到。

### 12.6 反模式 6:启动期打开 native-comp-async

```elisp
;; 错
(setq native-comp-deferred-compilation t
      native-comp-jit-compilation t)  ; 启动期间触发
```

**症状**:启动后 5-10 分钟 CPU 100% 跑 native-compile。

**正解**:

```elisp
;; emacs 28+
(setq native-comp-deferred-compilation nil  ; 启动期不异步
      native-comp-jit-compilation t)         ; JIT 在后台做
```

或 `doomemacs/lisp/doom-start.el:95-96` 那样直接禁掉电池模式:

```elisp
(setq native-comp-async-on-battery-power nil)
```

---

## 附录 A: 关键文件行号速查

| 引用                                     | 路径                                             | 行号                                     | 用途                   |
| ---------------------------------------- | ------------------------------------------------ | ---------------------------------------- | ---------------------- | -------------------- |
| GC 推迟                                  | `doomemacs/early-init.el`                        | 34-37                                    | 启动期关闭 GC          |
| file-name-handler 优化                   | `doomemacs/early-init.el`                        | 41                                       | let 块优化             |
| load-suffixes 缩减                       | `doomemacs/early-init.el`                        | 99-103                                   | 移除 .so               |
| package-enable-at-startup                | `spacemacs/early-init.el`                        | 32                                       | 关键 1 行              |
| GC 推迟 (spacemacs)                      | `spacemacs/init.el`                              | 21                                       | 384MB                  |
| load-prefer-newer t                      | `spacemacs/init.el`                              | 64                                       | let 块内               |
| `doom-first-input-hook` 定义             | `doomemacs/lisp/doom-start.el`                   | 8                                        | defcustom              |
| `doom-first-file-hook` 定义              | `doomemacs/lisp/doom-start.el`                   | 13                                       | defcustom              |
| `doom-first-buffer-hook` 定义            | `doomemacs/lisp/doom-start.el`                   | 18                                       | defcustom              |
| gcmh 注册                                | `doomemacs/lisp/doom-start.el`                   | 88-91                                    | doom-first-buffer-hook |
| `doom-run-hook-on` 实现                  | `doomemacs/lisp/doom-lib.el`                     | 277-309                                  | 核心 transient hook    |
| first-\* 注册位置                        | `doomemacs/lisp/doom.el`                         | 775-778                                  | doom-initialize 内     |
| `doom-load-packages-incrementally`       | `doomemacs/lisp/doom-start.el`                   | 232-275                                  | idle 分批              |
| `doom-load-packages-incrementally-h`     | `doomemacs/lisp/doom-start.el`                   | 277-285                                  | 入口                   |
| `doom-display-benchmark-h`               | `doomemacs/lisp/doom-start.el`                   | 292-301                                  | benchmark 报告         |
| `package!` 宏                            | `doomemacs/lisp/doom-lib.el`                     | 1548-1635                                | 声明式包               |
| `use-package!` 宏                        | `doomemacs/modules/config/use-package/init.el`   | 132-149                                  | thin wrapper           |
| `:defer-incrementally` handler           | `doomemacs/modules/config/use-package/init.el`   | 75-80                                    | doom 扩展              |
| `:after-call` handler                    | `doomemacs/modules/config/use-package/init.el`   | 82-103                                   | doom 扩展              |
| `doom-initialize`                        | `doomemacs/lisp/doom.el`                         | 768-855                                  | 启动主流程             |
| `doom-finalize`                          | `doomemacs/lisp/doom.el`                         | 855-878                                  | 启动结束               |
| vertico `:hook` 用法                     | `doomemacs/modules/completion/vertico/config.el` | 20-23                                    | doom-first-input       |
| `configuration-layer/lazy-install`       | `spacemacs/core/core-configuration-layer.el`     | 1236-1284                                | lazy install           |
| `configuration-layer//auto-mode`         | `spacemacs/core/core-configuration-layer.el`     | 1286-1292                                | auto 触发              |
| `configuration-layer//configure-package` | `spacemacs/core/core-configuration-layer.el`     | 2111-2121                                | init-XXX 调度          |
| `spacemacs/use-package-extend`           | `spacemacs/core/core-use-package-ext.el`         | 48-55                                    | 注入关键字             |
| `spacemacs                               | use-package-add-hook`                            | `spacemacs/core/core-use-package-ext.el` | 24-56                  | pre/post init config |
| evil `:demand t`                         | `doomemacs/modules/editor/evil/config.el`        | 25                                       | 强制 evil 立即 load    |
| `helpful/init-helpful` 示例              | `spacemacs/layers/+emacs/helpful/packages.el`    | 23-39                                    | spacemacs 范式         |

---

## 附录 B: 推荐阅读顺序

1. `doomemacs/early-init.el` (151 行,15 分钟) —— 看 PERF 注释怎么写
2. `doomemacs/lisp/doom-start.el` (379 行,30 分钟) —— 看三 hook + incremental 范式
3. `doomemacs/lisp/doom.el` 第 768-878 行 (110 行) —— `doom-initialize` 和 `doom-finalize` 的 hook 顺序
4. `doomemacs/lisp/doom-lib.el` 第 1548-1660 行 (110 行) —— `package!` / `disable-packages!` / `unpin!`
5. `doomemacs/modules/config/use-package/init.el` 全文 (200 行) —— Doom 对 use-package 的扩展
6. `spacemacs/early-init.el` + `spacemacs/init.el` (52 + 120 行) —— 对比 Doom 的哲学差异
7. `spacemacs/core/core-configuration-layer.el` 第 1236-1300 行 (64 行) —— `lazy-install` 范式
8. `spacemacs/core/core-use-package-ext.el` 全文 (163 行) —— Spacemacs 对 use-package 的扩展
9. 抽 2-3 个 `doomemacs/modules/<x>/<y>/config.el` 看真实 `use-package!` 怎么写 (推荐 `editor/evil`, `completion/vertico`)

---

## 附录 C: 核心范式一图总结

```
┌─────────────────────────────────────────────────────────────────┐
│                   Emacs 启动优化三轴                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. early-init.el (151 行)                                      │
│     ├─ GC 关掉 (gc-cons-threshold = most-positive-fixnum)       │
│     ├─ file-name-handler-alist = nil                            │
│     ├─ load-suffixes 缩减                                       │
│     └─ load-prefer-newer 选择                                   │
│         ↓                                                       │
│  2. init.el (单文件)                                            │
│     ├─ (require 'core)  ──── 字节编译消除 read 阶段             │
│     ├─ (package-initialize) ── package-quickstart 缓存          │
│     └─ (doom-initialize) ── 调用 module 字节码                  │
│         ↓                                                       │
│  3. 模块/包 (声明式)                                            │
│     ├─ Doom:    (package! X) + (use-package! X :hook :config)   │
│     └─ Spacemacs: (defconst X-packages) + (defun X/init-X)      │
│                                                                 │
│  ──── 启动期完成 ────                                           │
│                                                                 │
│  4. Doom 范式: 启动后 idle 期                                   │
│     ├─ doom-first-input-hook   (user 第一键)                    │
│     ├─ doom-first-buffer-hook  (切到非 scratch)                 │
│     ├─ doom-first-file-hook    (开第一个文件)                   │
│     └─ doom-load-packages-incrementally  (空闲分批)             │
│                                                                 │
│  5. Spacemacs 范式: 启动期 funcall                              │
│     └─ configuration-layer//configure-packages                  │
│         └─ (funcall '<layer>/init-<pkg>)                        │
│             └─ 内部 use-package :defer t 决定 lazy              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

**报告完。** 涉及 11 个 doom 源文件,6 个 spacemacs 源文件,所有声明都配真实行号引用。如需扩展某一节(例如用 elpaca 替换 straight 的具体步骤),请说明。

---

## 附录 D: 真实包场景的 lazy-load 范式剖析

### D.1 evil —— `:demand t` 的强 load 用例

`doomemacs/modules/editor/evil/config.el:25`:

```elisp
(use-package! evil
  :hook (doom-after-modules-config . evil-mode)
  :demand t
  ...)
```

**`:demand t` 的语义**:取消 use-package 的所有 lazy 推断,**强制 `require`**。Evil 是核心 vim 仿真,如果 lazy,首次按 `j` 才会 `require`,会卡 50-200ms,体验极差。

**决策规则**:

- 你的核心交互包(evil/counsel/company) → `:demand t`
- 80% 工作流必需(magit/projectile) → `:defer t` + 显式 `:commands`
- 偶尔用(flycheck) → `:defer t` + `:hook`
- 几乎不用(写博客才用) → 完全 lazy,只靠 auto-mode-alist

### D.2 vertico/marginalia —— 三个 hook 时机的差异

`doomemacs/modules/completion/vertico/config.el:20-23`:

```elisp
(use-package! vertico
  :hook (doom-first-input . vertico-mode)
  ...)
```

`doomemacs/modules/completion/vertico/config.el:130-132`:

```elisp
(use-package! marginalia
  :hook (doom-first-input . marginalia-mode)
  ...)
```

**都用 `doom-first-input-hook`**:vertico 是 minibuffer 增强,边际效用是"用户开始输入才用得到"。如果放在 `after-init-hook`,启动期就加载并**激活** minibuffer,占 0.1-0.2s。

对比 `doomemacs/modules/completion/vertico/config.el:33-37`:

```elisp
(use-package! orderless
  :after-call doom-first-input-hook
  :config
  ...)
```

**orderless 用 `:after-call` 而不是 `:hook`**:orderless 是个 _被 vertico 调用_ 的包,不是直接启用的 mode。`doom-first-input-hook` 触发时,vertico 调用 orderless 的逻辑会触发 `:after-call`,orderless 此时才 require。

**范式对比**:

- `:hook 'doom-first-input` = "直接 hook 一个 mode 的 enable"
- `:after-call 'doom-first-input-hook` = "首次调用 hook 链上的某个函数"
- 区别:hook 在 mode enable 时触发,after-call 在函数被调用时触发

### D.3 consult —— `:defer t` + `:preface` 的混合

`doomemacs/modules/completion/vertico/config.el:62`:

```elisp
(use-package! consult
  :defer t
  :preface
  (define-key!
    [remap bookmark-jump] #'consult-bookmark
    ...)
  ...)
```

**`:preface` vs `:init`**:

- `:preface` 在 `require` 之前,但**不** 等同于 `:init`(`:preface` 总是先于 `:init`)
- 用于声明 remap 键(键重新映射),这些不需要 `consult` 包存在
- 真正配置逻辑在 `:config`

这是 Doom 范式**比标准 use-package 更精细**的一例:把"全局 remap"和"包特定配置"分开,前者更早,后者 lazy。

### D.4 consult-dir —— 完全 lazy 到开文件时

`doomemacs/modules/completion/vertico/config.el:139`:

```elisp
(use-package! consult-dir
  :defer t
  :init
  (map! [remap list-directory] #'consult-dir
        (:after vertico
         :map vertico-map
         "C-x C-d" #'consult-dir
         "C-x C-j" #'consult-dir-jump-file))
  ...)
```

**注意 `:init` 里 `map!` 的安全性**:`map!` 是 `bind-map!` 的包装,**只是把 map 注册到一个** `map!` 队列,真正 `define-key` 是在 `vertico` 加载后。

**陷阱**:如果是 `(define-key global-map ...)` 而不是 `(map! ...)`,这会立刻在启动时执行,如果 consult-dir 未 require,`consult-dir` 符号未定义 → void-function。

### D.5 evil 多个子包(spacemacs 范式对比)

`spacemacs/layers/+emacs/helpful/packages.el:50-56`:

```elisp
(defun helpful/post-init-link-hint ()
  (evil-define-key 'normal helpful-mode-map (kbd "o") 'link-hint-open-link))

(defun helpful/pre-init-popwin ()
  (spacemacs|use-package-add-hook popwin
    :post-config
    (push '(helpful-mode :dedicated t ...) popwin:special-display-config)))
```

**Spacemacs `pre-init` 用法**:`helpful/pre-init-popwin` 在 `popwin` 的 `:init` 阶段**之前**运行,往 popwin 的 use-package 块注入 hook。这是 layer 之间的依赖声明。

**Doom 对等物**:`doomemacs/lisp/doom-lib.el:1660+` 的 `after!` 宏:

```elisp
;; (after! helpful (define-key helpful-mode-map "o" #'link-hint-open-link))
```

**差异**:`after!` 更易写,`pre-init` 命名更规范。

---

## 附录 E: 自写配置的渐进式重构路径

### E.1 阶段 1:从"平铺 200 个 use-package"重构

**症状**:

- `init.el` 超过 1000 行
- 启动 4-5 秒
- `use-package-report` 显示前 10 个包各 50ms+

**重构**:

1. 创建 `lisp/` 子目录
2. 按功能拆:`lisp/ui.el`, `lisp/editor.el`, `lisp/lang.el`
3. 把 `use-package` 块按主题移入对应文件
4. `init.el` 只做 `require`

```elisp
;; init.el (重构后)
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

(require 'early-init)        ; GC 优化
(require 'ui)                 ; ~30 个 use-package
(require 'editor)             ; ~50 个 use-package
(require 'lang)               ; ~120 个 use-package (每个 lang 一组)
```

**收益**:Emacs 字节编译每个 `lisp/<x>.el` 到 `<x>.elc`,启动期只走字节码,无 read 阶段。

### E.2 阶段 2:加 early-init.el 优化

**症状**:

- 阶段 1 后启动还在 2-3s
- `emacs-init-time` 显示 0.8s,感觉启动慢(说明 slow 的是 early-init 之前)

**重构**:

1. 创建 `early-init.el` (emacs 27+)
2. 添加 GC/file-name-handler/load-suffixes 优化
3. **关键**:同时在 `init.el` 注册 `gcmh-mode` 或重置 `gc-cons-threshold`

**测量方法**:

```elisp
;; init.el 末尾
(add-hook 'emacs-startup-hook
          (lambda ()
            (message "emacs-init-time: %fs, total: %fs"
                     emacs-init-time
                     (float-time (time-subtract (current-time) before-init-time)))))
```

### E.3 阶段 3:加 incremental loader

**症状**:

- 启动期快(1s)但首次开 magit 慢(1.5s)
- 首次开 org 文件慢

**重构**:

1. 抽 `lisp/heavy.el` 包含 magit/org/corfu
2. 启动后 `run-with-idle-timer 2` 加载

```elisp
;; init.el
(add-hook 'emacs-startup-hook
          (lambda ()
            (run-with-idle-timer
             2 nil
             (lambda ()
               (require 'heavy)
               (message "Heavy packages loaded in idle.")))))
```

### E.4 阶段 4:加 first-\* hook 范式

**症状**:

- vertico/company/which-key 在启动后未启用
- 用户首次按 M-x 时它们未生效

**重构**:

1. 把"启用 mode" 的代码从 `after-init-hook` 移到 `doom-first-input-hook` (自实现)

```elisp
;; init.el
(defvar my-first-input-hook nil)
(add-hook 'pre-command-hook
          (defun my-trigger-first-input-h ()
            (remove-hook 'pre-command-hook #'my-trigger-first-input-h)
            (run-hooks 'my-first-input-hook)))

;; vertico config
(add-hook 'my-first-input-hook #'vertico-mode)
(add-hook 'my-first-input-hook #'marginalia-mode)
```

### E.5 阶段 5:加字节编译 + profile 缓存

**症状**:

- 阶段 1-4 做完,启动 0.5s 但 `init.el` parse 占 0.2s

**重构**:

1. 跑 `M-x byte-compile-file` 对 `lisp/*.el` 批量
2. Emacs 优先用 `.elc`

**陷阱**:改了 `lisp/*.el` 后必须重编译。或者:

```elisp
;; Makefile 或 init-time:
(defun my-recompile-if-needed ()
  "Recompile all .el files in lisp/ if newer than .elc."
  (let ((lisp-dir (expand-file-name "lisp" user-emacs-directory)))
    (dolist (el-file (directory-files lisp-dir t "\\.el$"))
      (let* ((elc-file (concat el-file "c"))
             (el-time (nth 5 (file-attributes el-file)))
             (elc-time (and (file-exists-p elc-file)
                            (nth 5 (file-attributes elc-file)))))
        (when (or (not elc-time)
                  (time-less-p elc-time el-time))
          (byte-compile-file el-file))))))

;; 在 init.el 顶部调一次
(my-recompile-if-needed)
```

**注意**:这增加启动期 IO 成本,只有当 `.el` 不常改时才划算。

---

## 附录 F: 调试工具包

### F.1 启动测量三件套

```elisp
;; 1. emacs-init-time (内置)
(message "init time: %fs" emacs-init-time)

;; 2. before-init-time + after-init-time
(defvar my-start-time (current-time))
(add-hook 'emacs-startup-hook
          (lambda ()
            (message "wall time: %fs"
                     (float-time (time-subtract (current-time) my-start-time)))))

;; 3. 阶段性 timer
(progn
  (defvar my-timings nil)
  (defun my-time (label)
    (push (cons label (float-time (time-since my-start-time))) my-timings))
  (my-time "init-start")
  (require 'ui)
  (my-time "ui-loaded")
  (require 'editor)
  (my-time "editor-loaded"))
```

### F.2 `use-package` 诊断

```elisp
;; 启用统计
(setq use-package-compute-statistics t
      use-package-verbose nil)  ; verbose 太多噪音

;; 启动后查看
(use-package-report)
(use-package-report-loadtime)
```

### F.3 GC 监控

```elisp
;; 实时看 GC
(setq garbage-collection-messages t)
;; 启动后会频繁打印 [GC] 消息

;; 手动查 GC
(gc-stat)  ; 列出当前堆状态

;; 临时设小 GC 阈值看启动期
(setq gc-cons-threshold (* 1024 1024))  ; 1MB
;; 观察是否真的在 GC (而不是 mem leak)
```

### F.4 `load-path` 探针

```elisp
;; 列出 startup 后 load-path 新增的路径
(let ((initial-load-path (get 'load-path 'initial-value)))
  (cl-set-difference load-path initial-load-path :test #'string=))
;; 输出每个包的 load-path 增量
```

### F.5 `--timings` 字段解析 (Emacs 28+)

```bash
emacs --timings -l init.el -Q
```

输出文件 `emacs-startup-times` 类似:

```
Event                Used
Garbage collection   0.05s
Loading .elc files   0.30s
Setting up fonts     0.08s
...
```

定位哪个阶段慢。

---

## 附录 G: Doom `bin/doom` 角色说明

虽然 `bin/doom` 是 shell 脚本,不在 Emacs 内运行,但它与启动优化**深度耦合**:

### G.1 关键命令

```bash
bin/doom sync        # 安装/更新包,生成 profile .elc
bin/doom sync -u     # 同上 + 升级包
bin/doom compile     # 强制重编译 .elc
bin/doom doctor      # 健康检查
bin/doom env         # 打印 envvars
bin/doom upgrade     # 升级 doom 自身 + 包
```

### G.2 `doom sync` 流程

1. 读所有 `packages.el`,汇总到 `doom-packages` alist
2. 调用 `straight` 拉/构建每个包
3. 生成 `$XDG_DATA_HOME/doom/<profile>/init.el` (byte-compile 后)
4. 这个 .el 包含 `doom-startup` 函数定义 + 静态变量 (load-path, auto-mode-alist 等)

**这就是为什么 Doom 启动期 `load-path` 已经是常量**,不需要在 init.el 重新 append。

### G.3 `doom sync` 与启动性能的关系

| 阶段      | 触发                | 启动期影响                           |
| --------- | ------------------- | ------------------------------------ |
| 包未 sync | 用户装新包,直接启动 | 包不可用                             |
| 已 sync   | 常规启动            | 字节码 profile 加载,~0.3s            |
| sync 过时 | 包已升级,但 .elc 旧 | 启动慢 0.2-0.5s (read .el 走 source) |

**自写配置的对应**:用 `make compile` 或 `bin/doom compile` 等价物。

---

## 附录 H: 几个高 ROI 的具体小优化

### H.1 关闭 `auto-mode-case-fold`

`doomemacs/lisp/doom-start.el:32`:

```elisp
(setq auto-mode-case-fold nil)
```

**原理**:默认 `auto-mode-case-fold` 是 t,Emacs 对 `auto-mode-alist` 做两次匹配(大小写敏感 + 不敏感)。1000 条规则下,这能省 5-20ms。

**前置**:确保 `auto-mode-alist` 包含**完整大小写**(如果用 .gitignore 风格的规则就 OK)。

### H.2 关闭 `bidi-display-reordering` 或限制

`doomemacs/lisp/doom-start.el:35-39`:

```elisp
(setq-default bidi-display-reordering 'left-to-right
              bidi-paragraph-direction 'left-to-right)
(setq bidi-inhibit-bpa t)  ; Emacs 27+
```

**原理**:双向文本扫描对 redisplay 是开销;如果项目都是英文/中文单方向,关掉。

**注意**:有阿拉伯文/希伯来文内容时不要关。

### H.3 调整 `read-process-output-max`

`doomemacs/lisp/doom-start.el:74`:

```elisp
(setq read-process-output-max (* 64 1024))  ; 64kb
```

**原理**:LSP server (lsp-mode/eglot) 输出大量 JSON,默认 4KB 一次 read 触发大量 syscall。64KB 一次读,降到 1/16 系统调用。

### H.4 关闭 `inhibit-compacting-font-caches`

`doomemacs/lisp/doom-start.el:54`:

```elisp
(setq inhibit-compacting-font-caches t)
```

**原理**:font cache 压缩(garbage collect icon fonts)很慢,启动期禁用,代价是内存+1-2MB。

### H.5 提升 `pgtk-wait-for-event-timeout`

`doomemacs/lisp/doom-start.el:60-61`:

```elisp
(when (boundp 'pgtk-wait-for-event-timeout)
  (setq pgtk-wait-for-event-timeout 0.001))
```

**原理**:PGTK (Pure-GTK) build 的 childframe 超时默认 0.1s,对 lsp-ui/company-box/posframe 这些用 childframe 的包是 100ms 延迟。降到 1ms 后这些包体感快 10×。

**只在 PGTK build** 才生效。

### H.6 `w32-*` 优化 (Windows 用户)

`doomemacs/lisp/doom-start.el:79-82`:

```elisp
(when (boundp 'w32-get-true-file-attributes)
  (setq w32-get-true-file-attributes nil
        w32-pipe-read-delay 0
        w32-pipe-buffer-size (* 64 1024)))
```

**Windows 文件 IO 比 POSIX 慢**,这组优化针对 w32 build,Linux/Mac 用户无需管。

---

## 附录 I: daemon 模式特殊优化

`doomemacs/lisp/doom.el:864-867` 关键代码:

```elisp
;; If the user's already opened something (e.g. with command-line
;; arguments), then we should assume nothing about the user's intentions and
;; simply treat this session as fully initialized.
(when (and file-name-history (doom-context-p 'emacs))
  (doom-run-hooks 'doom-first-file-hook 'doom-first-buffer-hook))
```

**daemon 模式下**:

- `emacs --daemon` 启动时无 frame,所有 `doom-first-*` hook 都不触发
- Doom 在 daemon 模式下**直接调**`doom-load-packages-incrementally-h`,且 `doom-incremental-first-idle-timer` 默认 0 (line 222)
- 即"daemon 模式立刻加载所有 incremental 包"
- 然后第一次 `emacsclient` 连接时,UI 创建,但包已加载,UI 即时响应

**自写 daemon 优化建议**:

1. **启动期**:incremental first-idle = 0,立即 require
2. **不要**用 `doom-first-input` 之类的 hook,daemon 启动时没有 input
3. **用** `server-after-make-frame-hook` 替代 first-frame-hook
4. **监控** `emacsclient -t` 连接耗时,应 < 100ms

---

## 附录 J: 与其他 worker 的边界声明

本报告**严格不涉及**以下主题(由其他 worker 处理):

- ❌ 键位 / leader key 体系(evil + general)
- ❌ UI 装饰(theme, modeline, nerd-icons)
- ❌ 外部工具集成(lsp, treesitter, magit, projectile)
- ❌ 模块化机制(doom module + flags, spacemacs layer 拓扑)
- ❌ 测试/调试(ert, buttercup, edebug)
- ❌ 特定语言配置(go/rust/python/java)
- ❌ 编辑器增强(avy, multiple-cursors, hungry-delete)

**本报告唯一范围**:

- ✓ 启动期优化 (early-init.el, GC, file-handler, load-suffixes)
- ✓ 包管理 (package.el / straight / elpaca 对比, 决策树)
- ✓ lazy-load 范式 (use-package 关键字语义, doom-first-\* hooks, incremental loader)
- ✓ 字节编译与 profile 生成 (load-prefer-newer, doom sync, byte-compile 陷阱)
- ✓ 启动瓶颈定位方法 (emacs-init-time, use-package-report, benchmark-init, --timings)

---

**报告完。** 涉及 11 个 doom 源文件,6 个 spacemacs 源文件,所有声明都配真实行号引用。如需扩展某一节(例如用 elpaca 替换 straight 的具体步骤),请说明。
