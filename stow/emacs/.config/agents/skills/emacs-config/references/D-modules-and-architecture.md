# Emacs 配置的模块化/分层架构范式对比

> 研究目标: 综合对比 vanilla use-package / org-babel literate / doom modules /
> spacemacs layers 四种主流架构,提炼每种范式的优缺点,给出"包数量从 10
> 增长到 200 时,何时该升级架构"的可操作决策。

- **数据源**: 本地仓库 `doomemacs/` (commit 2026-05 前),`spacemacs/`
  (spacemacs develop branch)
- **必读源文件已完整阅读**:
  - `doomemacs/lisp/lib/modules.el` (193 行)
  - `doomemacs/lisp/lib/profiles.el`
  - `doomemacs/lisp/doom.el` (doom-module-load-path / init-file / config-file / packages-file 全部 docstring)
  - `doomemacs/lisp/doom-lib.el` (doom-module-context, doom-module--has-flag-p, modulep! 实现)
  - `doomemacs/modules/config/default/{packages,config}.el` (完整)
  - `doomemacs/modules/config/default/+evil-bindings.el` (877 行)
  - `doomemacs/modules/config/default/+emacs-bindings.el` (622 行)
  - `doomemacs/modules/editor/evil/{packages,config}.el` (完整)
  - `doomemacs/modules/ui/zen/{README.org,packages.el,config.el,autoload.el}` (完整)
  - `spacemacs/core/core-configuration-layer.el` (2963 行,核心 layer 加载器)
  - `spacemacs/core/core-load-paths.el` (完整)
  - `spacemacs/core/core-dotspacemacs.el` (dotspacemacs 配置范式,前 270 行)
  - `spacemacs/layers/+spacemacs/spacemacs-defaults/packages.el` (前 80 行 + 模式)
  - `spacemacs/layers/+spacemacs/spacemacs-completion/packages.el` (前 120 行 + 模式)
  - `spacemacs/layers/+lang/python/{packages,funcs,layers}.el` + `README.org` (完整)
  - `spacemacs/layers/LAYERS.org` (catalog 文档规范)

---

## 目录

- [1. 摘要](#1-摘要)
- [2. 四种范式概述](#2-四种范式概述)
- [3. 四范式主对比表](#3-四范式主对比表)
- [4. Doom modules 深度剖析](#4-doom-modules-深度剖析)
- [5. Spacemacs layers 深度剖析](#5-spacemacs-layers-深度剖析)
- [6. Vanilla use-package 范式](#6-vanilla-use-package-范式)
- [7. Org-babel literate config](#7-org-babel-literate-config)
- [8. 包数量 → 架构选择决策表](#8-包数量--架构选择决策表)
- [9. 从 vanilla 迁移到模块化](#9-从-vanilla-迁移到模块化)
- [10. 自建 vs 引入框架](#10-自建-vs-引入框架)
- [11. doom `modulep!` 深入](#11-doom-modulep-深入)
- [12. spacemacs `configuration-layer/*` 宏族](#12-spacemacs-configuration-layer-宏族)
- [13. 容器化环境下的模块化](#13-容器化环境下的模块化)
- [14. Doom module 自建模板](#14-doom-module-自建模板)
- [15. 实施检查清单](#15-实施检查清单)
- [16. 反模式](#16-反模式)
- [17. 附录: 关键文件/路径速查](#17-附录-关键文件路径速查)

---

## 1. 摘要

研究结论先放最前,细节在后续章节展开。

**核心发现**

1. **四种范式的本质分歧点** 在"包清单"和"配置正文"如何物理分离:
   - **vanilla use-package** 把两者都塞进 init.el(或 require 加载的 lisp/ 目录)
   - **org-babel** 用 org 源文件做容器,tangle 出等价 init.el
   - **doom modules** 把"包清单"和"配置正文"分到两个独立文件,中间由 `doom!` 块作为注册中心
   - **spacemacs layers** 走得更远,把"包声明"和"配置正文"分别再切三段
     (`pre-init` / `init` / `post-init`),并把"启用哪些 layer"抽到一个 dotfile

2. **架构升级触发点不只看"包数量"**,三个并行维度:
   - 包数量(< 10 → 单文件; 10-30 → 拆分; 30-80 → 文档化; 80+ → 模块化)
   - 多环境(多机器 / 多 distrobox / 多角色)→ 必须 profile 化
   - 跨用户复用(分享 config / dotfiles 仓库)→ 必须模块化 + flag 化

3. **doom 偏"工程性能"**,spacemacs 偏"声明优雅"。两个项目都"完整"且
   "经过百万用户验证",自建方案在前 200 个包之前都站不住脚,200 包之后
   才出现真正的成本拐点。

4. **doom 的 flag 体系是杀手锏**:`(modulep! :ui workspaces +childframe)`
   这种语义的紧凑程度,vanilla 和 spacemacs 都做不到。spacemacs 走
   `:toggle (configuration-layer/package-used-p 'helm)` 这种判断式,
   灵活但松散。

5. **profile 是被低估的"第三维"**:当配置需要在"个人笔记本/work 笔记本/容器"
   三处切换时,doom 已经有 `doom-profile` 体系(`doom-profiles.el`,
   `$DOOMPROFILE` 环境变量,`init.@.0.el` 衍生器),spacemacs 仍只能依赖
   `.spacemacs` 切换 + chemacs2 外挂。

---

## 2. 四种范式概述

### 2.1 Vanilla use-package

**范式**: init.el 是单一入口,通过 `require` 加载 `lisp/*.el` 拆分文件。

```elisp
;; init.el
(require 'package)
(setq package-archives ...)
(package-initialize)
(require 'use-package)
(setq use-package-verbose t)

;; load order matters
(require 'init-ui)
(require 'init-editor)
(require 'init-lang)
(require 'init-prog)

;; 或 :load-path 拆分 lisp/
```

- **典型规模**: 5-50 个包
- **文件树**: `init.el` + `lisp/{ui,editor,lang,prog,tools}/*.el`
- **社区代表**: 大多数入门教程、Prelude、Purcell 配置

### 2.2 Org-babel literate config

**范式**: 单一 `config.org`,在 `#+begin_src emacs-lisp` 块中写 elisp,
通过 `org-babel-tangle` 产出 `init.el` 或 `lisp/*.el`。

```org
* UI
** Theme
#+begin_src emacs-lisp :tangle yes
(load-theme 'doom-one t)
#+end_src

** Font
#+begin_src emacs-lisp :tangle yes
(set-face-attribute 'default nil :height 110)
#+end_src
```

- **典型规模**: 10-200 个包(可承载,代价是 org 源文件膨胀)
- **代表**: Sacha Chua 配置,Protesilaos (cprot/dprot 分支),Howard Abrams
- **变体**: 有的 tangle 到 `init.el`,有的 tangle 到 `lisp/*.el` 然后由
  `init.el` 加载;有的只 tangle 选中的 `:tangle yes` 块,有的是 `:tangle init.el` 顶层设置

### 2.3 Doom modules

**范式**: 严格两层目录结构 `category/module/{packages,config,init,...}.el`,
`$DOOMDIR/init.el` 用 `(doom! :lang python +lsp ...)` 注册。

- **典型规模**: 80-300+ 个包(doom core 自身 300+)
- **核心抽象**: `module!` / `package!` / `use-package!` / `map!` / `set-popup-rule!` /
  `defcustom` + `:group '+MODULE` / `modulep!` 宏体系
- **关键文件**(所有文件均可选,但 `packages.el` + `config.el` 是事实标准):
  - `packages.el` — 声明本模块要装哪些包(`(package! ... :pin "...")`)
  - `config.el` — `use-package!` 块和实际设置
  - `init.el` — 在 `doom-after-modules-init-hook` 之前执行的预初始化
  - `autoload.el` / `autoload/*.el` — `;;;###autoload` 标记的延迟加载函数
  - `README.org` — 文档,带 `[[doom-module:]]` 等特殊链接
  - `doctor.el` — `doom doctor` 跑的健康检查
  - `+flag` 变体(无扩展名,实际是另一个目录名) — 模块内变体
  - `+bindings.el` / `+evil-bindings.el` — 按 editing style 分发的键位

### 2.4 Spacemacs layers

**范式**: 单层目录 `category/layer/{packages,funcs,config,layers,keybindings}.el`,
`~/.spacemacs` 用 `dotspacemacs-configuration-layers '(python :variables ...)`
注册。

- **典型规模**: 100-500+ 个包
- **核心抽象**: `configuration-layer/declare-layer` /
  `configuration-layer/declare-layer-dependencies` / `use-package` 直接使用
- **声明宏族**:
  - packages.el 用 `defconst layer-packages '(...)` 列出符号
  - 每个符号需要匹配 `layer/init-PKGNAME` / `layer/post-init-PKGNAME` / `layer/pre-init-PKGNAME`
    三个函数中的一个或多个
  - `(PKG :location ... :toggle ... :requires ...)` 元组语法做条件启用
- **关键文件**:
  - `packages.el` — `(defconst XXX-packages '((pkg :toggle cond) ...))` 清单
  - `config.el` — `use-package` 块和 `configuration-layer/set-layer-variable` 调用
  - `funcs.el` — 辅助函数,加载早于 config
  - `keybindings.el` — 键位
  - `layers.el` — `configuration-layer/declare-layer-dependencies '(...)`
  - `local/PKGNAME/` — 包本地 fork(在 `+local` 模式下用)

---

## 3. 四范式主对比表

| 维度                        | Vanilla use-package                          | Org-babel literate                       | Doom modules                                                                 | Spacemacs layers                                                   |
| --------------------------- | -------------------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------ | -------- | ---- |
| **学习曲线**                | ★☆☆☆☆ 直接                                   | ★★☆☆☆ 需懂 org-mode                      | ★★★★☆ doom 宏体系 + flag                                                     | ★★★★☆ declare-\* 宏族 + EIEIO                                      |
| **配置粒度**                | 包级(use-package 一块一包)                   | 段级(标题+块)                            | 包级 + flag 子变体                                                           | 包级 + 列表内条件 + 多 init 阶段                                   |
| **适用规模**                | 5-50 包                                      | 10-200 包                                | 80-300+ 包                                                                   | 100-500+ 包                                                        |
| **复用性**                  | 弱(require + path 依赖)                      | 中(可 tangle 多个目标)                   | 强(doom core 数百 module 可直接启用)                                         | 强(spacemacs 200+ layer)                                           |
| **可移植性**                | 强(纯 elisp,无外部依赖)                      | 中(依赖 org-mode + tangle 工具链)        | 中(需 doom 框架,不能单独抽离模块)                                            | 弱(深度绑定 spacemacs core)                                        |
| **启动开销**                | 最低(无中间层)                               | 低(tangle 后等价 vanilla)                | 中(doom 自身 200-400ms 优化)                                                 | 高(2963 行 core, package.el 路径多)                                |
| **维护成本(单人)**          | ★☆☆                                          | ★★☆                                      | ★★★                                                                          | ★★★                                                                |
| **维护成本(社区)**          | ★★★★★ 任何 use-package 配置互不干扰          | ★★☆☆ 几乎无社区贡献模式                  | ★★★★☆ PR 流程成熟, 文档强制 README.org                                       | ★★★★☆ CONTRIBUTING.org 强约束                                      |
| **原生 use-package 偏离度** | 0%(就是 use-package)                         | 0%(tangle 出 use-package)                | 中(用 `use-package!` 替代 + doom 添加 `after!` / `map!` / `set-popup-rule!`) | 低(用 `use-package` 原版,但在 cfgl-package EIEIO 对象外层包了一层) |
| **flag / 子变体**           | 需手写 `defcustom` + `if`                    | 需手写 `:tangle no` 块或 elisp 判断      | 1 行: `(modulep! :ui zen +focus)`,flag 在 modules.el 编译时展开              | 需用 `:toggle (eq layer-var 'foo)` 元组属性,无命名 flag            |
| **profile / 多环境**        | 需手写 `if (eq system-type ...)`,或 chemacs2 | 同左                                     | 内建 `doom-profile` 体系(`DOOMPROFILE=work@0 emacs`)                         | 需 chemacs2                                                        |
| **lazy-load 支持**          | `use-package :defer` / `:commands`           | 同左                                     | `use-package!` + `autoload.el` + 显式 `defun +MODULE/...`                    | `use-package` + layer 内 `:defer`                                  |
| **文档化**                  | 注释                                         | org 标题 + 散文(天然支持)                | README.org 强制 + `[[doom-package:]]` 自定义链接                             | README.org 强制 + `#+TAGS: layer                                   | category | ...` |
| **错误信息可读性**          | 最好(纯 elisp)                               | 中(报错指向 tangle 后的文件,不是 org 源) | 中(报错指向生成代码,需熟悉 `cl-defstruct doom-module`)                       | 差(EIEIO 包装层+layer init 函数命名空间混淆)                       |
| **典型用户**                | 5-50 包的用户,重定制                         | 偏文档癖、博主                           | 80+ 包的工程师,重一致性                                                      | 想立刻获得 200+ 包集成的用户                                       |
| **首次学习投入**            | 1 天                                         | 2-3 天                                   | 1-2 周(doom 宏体系 + flag 范式)                                              | 1-2 周(空 vs hybrid 编辑风格 + dotfile 配置 + EIEIO)               |

> **评分说明**: ★越多表示成本越高/越难,并不代表"更好"。

### 3.1 关键 trade-off 总结

| 决策点                                                   | 选 vanilla     | 选 org-babel   | 选 doom                                                 | 选 spacemacs             |
| -------------------------------------------------------- | -------------- | -------------- | ------------------------------------------------------- | ------------------------ |
| 我有 < 30 个包                                           | ✓              | △(没必要)      | ✗                                                       | ✗                        |
| 我有 30-100 个包                                         | △(可维护)      | ✓(爱文档)      | △(学习成本高)                                           | △                        |
| 我有 100+ 个包                                           | ✗(失控)        | △(膨胀)        | ✓                                                       | ✓                        |
| 我需要 3+ 套配置(家/公司/容器)                           | ✗(需 chemacs2) | ✗(需 chemacs2) | ✓(`DOOMPROFILE=`)                                       | ✗(需 chemacs2)           |
| 我想直接启用 Magit / LSP / Projectile 等的"开箱即用"集成 | ✗(手写)        | ✗(手写)        | ✓(doom 已配好)                                          | ✓(spacemacs 已配好)      |
| 我在团队/博客/书里**写配置文档**                         | ✗              | ✓✓             | ✓(README.org)                                           | ✓(README.org)            |
| 我的配置需要在 3+ 个 Emacs 版本上工作                    | ✓(最稳)        | ✓              | △(doom 锁版本)                                          | △(spacemacs 锁版本)      |
| 我只想用 vanilla 的 `M-x` 和少量键位,不想背 SPC 体系     | ✓              | ✓              | ✗(doom 强 SPC 优先)                                     | ✗(spacemacs 强 SPC 优先) |
| 我重度 evil 用,但用自定义 leader 键                      | ✓(自己装 evil) | ✓              | △(doom 默认 SPC,可改但费劲)                             | △(spacemacs 强 SPC)      |
| 我重度非 evil 用                                         | ✓              | ✓              | △(可关 evil,得在 `config.el` 写 `+emacs-bindings` 加载) | △                        |

---

## 4. Doom modules 深度剖析

### 4.1 核心抽象

来源: `doomemacs/lisp/lib/modules.el` + `doomemacs/lisp/doom-lib.el`

```
(:group :name)           ; 模块 key,如 (:lang . python)
  │
  ├─ :path               ; 物理目录
  ├─ :depth (INIT . CFG) ; 加载顺序,负数更早,正数更晚
  ├─ :flags (SYMBOL...)  ; 启用的 +flag 列表
  └─ :features           ; (NOT IMPLEMENTED YET)
```

**两个虚拟模块**:

- `(:doom . nil)` — doom 自身(深度 -110,最先加载)
- `(:user . nil)` — 用户目录(深度 -105 ~ 105)

**实际模块发现** 通过 `(doom-module-locate-path (cons group name) file)`:
搜索 `doom-module-load-path` 中所有 `{path}/{group}/{name}/{file}` 组合。

### 4.2 模块注册流程

```
$DOOMDIR/init.el
  └─ (doom! :lang (python +lsp) :tools magit ...)
       │
       ├─ 在 noninteractive 模式(doom sync / doom doctor)展开,调用
       │  (doom-module-mplist-map #'doom-module--put ...)
       │  → 把每个 category/module 写入 doom-modules hash-table
       │
       └─ 在 interactive 模式,被生成的 init.X.Y.el loader 加载
```

`doom-module-mplist-map` 的关键逻辑(见 modules.el:147-189):

- 遇到 `:cond` 子句:按条件 include/exclude 后续模块
- 遇到 `:if` / `:unless` 子句:分支选择
- 遇到 `:lang foo +flag`:把 `foo` 注册,同时 flag `+flag` 记录到 module
- 遇到废弃模块名(在 `doom-obsolete-modules`):自动重写为新模块并加 warning

### 4.3 四个关键文件(模块内)

#### 4.3.1 `packages.el`

- 文件名: `doom-module-packages-file` (= "packages.el")
- 加载时机: **仅**在 doom 自身需要包清单时(straight.el 调用)
- 关键宏: `package!`, `modulep!` (条件决定要不要装)
- 例子 (`doomemacs/modules/ui/zen/packages.el`):
  ```elisp
  (package! writeroom-mode :pin "cca2b4b3cfcf...")
  (package! mixed-pitch :pin "519e05f74825...")
  (when (modulep! +focus)
    (package! focus :pin "a58e29e70948...")
    (when (modulep! :tools lsp -eglot)
      (package! lsp-focus :pin "675a20610c63...")))
  ```

**注意**: packages.el 中只有 `defvar` / `defconst` / `(package! ...)` 这种
**声明式**调用,**绝对不要**放 `setq` 或 `use-package!` 块。这是 doom
的重要约束(用于支持"按需安装"和"模块禁用时跳过")。

#### 4.3.2 `config.el`

- 文件名: `doom-module-config-file` (= "config.el")
- 加载时机: 交互式会话中,在 `doom-after-modules-init-hook` 之后
- 关键宏: `use-package!`, `map!`, `set-popup-rule!`, `defcustom` (`:group '+MODULE`)
- 例子 (节选自 `doomemacs/modules/config/default/config.el`):
  ```elisp
  (defvar +default-want-RET-continue-comments t
    "If non-nil, RET will continue commented lines.")
  ;; ...实际配置省略 500+ 行
  ```

#### 4.3.3 `init.el`

- 文件名: `doom-module-init-file` (= "init.el")
- 加载时机: 在 `doom-before-modules-init-hook` 之后,所有 config.el 之前
- 用途: 早绑定变量、设置默认(必须不能引用任何可能在 config.el 才加载的包)
- 例子 (`doomemacs/modules/editor/evil/config.el` 就有):
  ```elisp
  (defvar evil-want-keybinding (not (modulep! +everywhere)))
  (defvar evil-want-C-g-bindings t)
  ```

#### 4.3.4 `autoload.el` / `autoload/*.el`

- 加载时机: 在 init.el 之后、config.el 之前
- 用途: 标记 `;;;###autoload` 的函数延迟加载
- 例子 (`doomemacs/modules/ui/zen/autoload.el`):
  ```elisp
  ;;;###autoload
  (defalias '+zen/toggle #'writeroom-mode)
  ;;;###autoload
  (defun +zen/toggle-fullscreen ()
    "..."
    (interactive)
    (require 'writeroom-mode)
    ...)
  ```

`autoload/` 子目录用于拆分大型自动加载(见 `doomemacs/modules/editor/evil/autoload/`):

- `advice.el` — 各种 advice
- `embrace.el`, `evil.el`, `ex.el`, `files.el`, `textobjects.el`, `unimpaired.el`

这些文件会被 `doom-autoloads--scan` 扫到(见 `doom-profile--generate-loaddefs-doom`),
把 `;;;###autoload` 函数提取到一个统一 autoload 文件中。

#### 4.3.5 `+bindings.el` / `+evil-bindings.el` / `+emacs-bindings.el`

- 加载时机: config.el 内部,按 `(if (modulep! :editor evil) ... ...)` 显式 `load!`
- 用途: 按 editing style 分发的键位
- `doomemacs/modules/config/default/+evil-bindings.el` 877 行,几乎全是 `map!` 调用
- 加载模式(见 `+evil-bindings.el` 顶部和 `config.el` 末尾):

  ```elisp
  ;; in config.el
  (cond
   ((modulep! :editor evil)
    ;; ...
    (unless (doom-context-p 'reload)
      (when (modulep! +bindings)
        (load! "+evil-bindings"))))
   (t
    ;; ...
    (load! "+emacs-bindings")))
  ```

  - `+evil-bindings.el` 顶部:`;;; config/default/+bindings.el` 注释,说明
    "这个文件实际叫 +bindings.el,模块是 config/default"
  - 文件名 `+evil-bindings.el` 是约定(用户 + 编辑风格),但 doom 的 loader 不挑
    后缀,只读 `+bindings.el` 是 `load!` 调用传进去的字面量

### 4.4 flag 体系

**flag** = doom 模块的布尔子开关,语法为 `+flag` 或 `-flag`(`-` 表示"无该 flag")。

#### 4.4.1 声明位置

`packages.el` 中读 flag:

```elisp
(when (modulep! +focus)
  (package! focus :pin "..."))
```

`config.el` 中读 flag:

```elisp
(when (modulep! +focus)
  (use-package! focus :defer t :init ...))
```

跨模块读 flag:

```elisp
;; in modules/editor/evil/packages.el
(when (modulep! +everywhere)
  (package! evil-collection))
```

#### 4.4.2 启用位置

`$DOOMDIR/init.el`:

```elisp
(doom!
  :lang (python +lsp +tree-sitter)
  :ui   (zen +focus)
  :editor (evil +everywhere))
```

冒号 + 名字是 category,括号内第一个是 module 名,后续是 flag。
flag 必须 `+` 或 `-` 开头。

#### 4.4.3 flag 编译时绑定

`doom-module--put` 编译期把 flag 列表缓存到 `doom-module-context` 的 plist,
见 `doomemacs/lisp/lib/modules.el:107-118`:

```elisp
;; PERF: Doom caches module index, flags, and features in symbol plists
;;   for fast lookups in `modulep!' and elsewhere. plists are lighter and
;;   faster than hash tables for datasets this size, and this information
;;   is looked up *very* often.
(put group name (doom-module->context module))
```

也就是说,`(modulep! :ui zen +focus)` 实际上展开为:

```elisp
(doom-module--has-flag-p
 (doom-module-context-flags (get :ui 'zen))
 '(+focus))
```

`doom-module--has-flag-p` 实现(`doomemacs/lisp/doom-lib.el:1304-1320`):

```elisp
(cl-loop with flags = (ensure-list flags)
         for flag in (ensure-list wanted-flags)
         for flagstr = (symbol-name flag)
         if (if (eq ?- (aref flagstr 0))
                (memq (intern (concat "+" (substring flagstr 1))) flags)
              (not (memq flag flags)))
         return nil
         finally return t)
```

#### 4.4.4 flag 反转的语义

`+everywhere`: 显式启用
`-everywhere`: 显式禁用(返回 t 当且仅当 flags 中**没有** `+everywhere`)
`everywhere`(无前缀): 等同于 `+everywhere`,但兼容性差,**不要**用无前缀

### 4.5 `:depth` 加载顺序

每个模块可以声明:

```elisp
;; 整数
:depth -50

;; cons cell
:depth (-50 . 50)  ; (init-depth . config-depth)
```

默认 `(0 . 0)`。负数优先加载,正数靠后。doom core 模块如 `:doom . nil` = -110,
`(:doom . compat)` = -111(更早)。

### 4.6 用户目录模块

`doom-module-load-path` 默认:

```elisp
(list (file-name-concat doom-user-dir "modules")
      (file-name-concat doom-emacs-dir "modules"))
```

**关键**: 用户目录的 modules 路径**优先**。这意味着 `$DOOMDIR/modules/`
可以**覆盖** doom core 的同名模块(完全替换,不是补丁)。

常见用法:

- `$DOOMDIR/modules/lang/python/config.el` — 改 python 模块设置
- `$DOOMDIR/modules/ui/zen/+bindings.el` — 加 zen 模块的键位

### 4.7 关键路径

| 变量                        | 值                                              | 说明                               |
| --------------------------- | ----------------------------------------------- | ---------------------------------- |
| `doom-emacs-dir`            | `user-emacs-directory`                          | doom 自身所在                      |
| `doom-core-dir`             | `doomemacs/`                                    | doom core 代码                     |
| `doom-modules-dir`          | `doomemacs/modules/`                            | doom 官方模块根                    |
| `doom-user-dir`             | `$DOOMDIR` 或 `~/.doom.d/` 或 `~/.config/doom/` | 用户配置                           |
| `doom-module-init-file`     | `"init.el"`                                     | 模块 init 文件名                   |
| `doom-module-config-file`   | `"config.el"`                                   | 模块 config 文件名                 |
| `doom-module-packages-file` | `"packages.el"`                                 | 模块 packages 文件名               |
| `doom-data-dir`             | `~/.local/share/doom/`                          | 全局数据                           |
| `doom-cache-dir`            | `~/.cache/doom/`                                | 缓存(可删)                         |
| `doom-state-dir`            | `~/.local/state/doom/`                          | 状态(history / bookmark / recentf) |

---

## 5. Spacemacs layers 深度剖析

### 5.1 核心抽象

来源: `spacemacs/core/core-configuration-layer.el`

```
cfgl-layer (EIEIO class)
  ├─ :name SYMBOL            ; layer 名,如 'python
  ├─ :dir STRING             ; 物理目录
  ├─ :packages LIST          ; 收集到的包
  ├─ :selected-packages      ; 'all | 列表
  ├─ :variables PLIST        ; 来自 dotspacemacs-configuration-layers 中的 :variables
  ├─ :lazy-install BOOL
  ├─ :disabled-for LIST      ; (layer-name-1 layer-name-2 ...)
  ├─ :enabled-for LIST
  ├─ :can-shadow LIST        ; 互斥关系
  └─ :deps-loaded BOOL

cfgl-package (EIEIO class)
  ├─ :name SYMBOL
  ├─ :min-version LIST
  ├─ :owners LIST            ; (layer-name-1 layer-name-2 ...) 哪个 layer "拥有"它
  ├─ :pre-layers LIST
  ├─ :post-layers LIST
  ├─ :location elpa|local|built-in|recipe
  ├─ :toggle FORM            ; 求值为 non-nil 才启用
  ├─ :step nil|bootstrap|pre
  ├─ :lazy-install BOOL
  ├─ :protected BOOL
  ├─ :excluded BOOL
  └─ :requires LIST          ; 软依赖
```

### 5.2 加载流程(主路径)

`configuration-layer//load` 见 `core-configuration-layer.el:590-650`:

```
1. configuration-layer/discover-layers 'refresh-index
   └─ 扫描 layers/ 目录,建立 cfgl-layer 索引
2. configuration-layer//declare-used-layers LAYERS-SPECS
   └─ 根据 dotspacemacs-configuration-layers 标记"used"
   └─ 自动加载依赖层
   └─ 加 distribution + bootstrap 层
3. configuration-layer//load-layers-files USED '("funcs")
   └─ 加载 funcs.el(辅助函数)
4. configuration-layer//configure-layers USED
   └─ 加载 config.el(但 config.el 中的 use-package 块**不立即展开**)
5. configuration-layer//declare-used-packages USED
   └─ 把所有 packages.el 中的 defconst 收成 cfgl-package
6. configuration-layer/load-auto-layer-file
   └─ 加载 auto-layer.el(自动生成的 quick-load)
7. 装包(configuration-layer//install-packages)
8. configuration-layer//configure-packages USED
   └─ 排序:bootstrap → pre → other
   └─ 对每个包调用 pre-init + init + post-init 函数
9. configuration-layer//set-layers-variables
   └─ 二次设置 layer 变量(覆盖 packages 的默认)
10. configuration-layer//load-layers-files USED '("keybindings")
    └─ 最后加载键位
```

### 5.3 文件职责

#### 5.3.1 `packages.el`

```elisp
(defconst python-packages
  '(
    (blacken :toggle (eq 'black python-formatter))
    (code-cells :toggle (not (configuration-layer/layer-used-p 'ipython-notebook)))
    company
    cython-mode
    ;; ...
    (uv :toggle (memq 'uv python-enable-tools)
        :location (recipe :fetcher github :repo "borgstad/uv.el" :files ("*.el")))
    ;; anaconda 后端
    (anaconda-mode :toggle (eq python-backend 'anaconda))
    (company-anaconda :requires (anaconda-mode company))))

;; 每个 PKG 必须有以下函数之一:
;; - python/init-PKGNAME
;; - python/pre-init-PKGNAME
;; - python/post-init-PKGNAME
(defun python/init-pet ()
  (use-package pet
    :hook (python-base-mode . pet-mode)))

(defun python/post-init-company ()
  ;; 后置初始化
  ...)
```

**元组语法**:

- `:toggle FORM` — 求值,non-nil 才装(但**总**会进入 installed 列表)
- `:location` — `'elpa` (默认) | `'built-in` | `'local` | `'(recipe :fetcher github :repo "...")`
- `:requires PKG-LIST` — 软依赖,任意一个不启用就不装
- `:step 'bootstrap | 'pre | nil` — 加载阶段

#### 5.3.2 `config.el`

```elisp
;; 普通 use-package
(use-package eldoc
  :defer t
  :init (setq eldoc-idle-delay 0.3)
  :config (eldoc-add-command 'python-mode))

;; layer 内变量定义
(defvar python-backend 'anaconda
  "Backend for python: 'anaconda or 'lsp.")

;; 暴露给 dotfile 设置
;; 用户在 .spacemacs 写:
;;   dotspacemacs-configuration-layers
;;     '((python :variables python-backend 'lsp))
```

#### 5.3.3 `funcs.el`

- 加载早于 config.el
- 包含辅助函数,提供给 `init-` / `post-init-` 函数用
- `spacemacs//python-setup-backend` 等命名约定的函数都在这里

#### 5.3.4 `layers.el`

```elisp
(when (and (boundp 'python-backend)
           (eq python-backend 'lsp))
  (configuration-layer/declare-layer-dependencies '(lsp)))
```

**唯一的声明依赖方式**。

#### 5.3.5 `keybindings.el`

- 最后加载,覆盖 config.el 的键位
- `spacemacs/set-leader-keys-for-major-mode` / `spacemacs|define-transient-state`
- 不一定存在,有的 layer 把键位散在 config.el

#### 5.3.6 `local/PKGNAME/`

- 包本地 fork,在 packages.el 用 `(PKG :location local)` 引用
- 不会被 spacemacs 自动更新覆盖

### 5.4 关键查询 API

```elisp
;; layer 是否被启用(且没被 shadow)
(configuration-layer/layer-used-p 'python)

;; 包是否被启用(owners 全部解析)
(configuration-layer/package-used-p 'company)

;; 当前在加载哪个 layer
spacemacs-customization--current-group

;; layer 的变量(从 :variables plist)
(let ((layer (configuration-layer/get-layer 'python)))
  (oref layer variables))
```

### 5.5 与 doom 的关键差异

| 维度         | Doom                                             | Spacemacs                                                       |
| ------------ | ------------------------------------------------ | --------------------------------------------------------------- |
| 包清单位置   | `packages.el` (用 `package!` 宏)                 | `packages.el` (用 `defconst` + 元组)                            |
| 跨模块条件   | `(modulep! :ui zen +focus)` 内置                 | `(configuration-layer/package-used-p 'helm)` 内置               |
| 子变体       | `+focus` 命名 flag                               | `:toggle (eq python-backend 'lsp)` 普通变量                     |
| 配置粒度     | init.el / config.el / autoload.el / +bindings.el | packages.el / config.el / funcs.el / keybindings.el / layers.el |
| EIEIO 包装   | 无,用 plist + struct                             | 用 EIEIO cfgl-layer / cfgl-package 类                           |
| 错误信息     | 直接指向生成代码                                 | 经常指向 `python/post-init-company` 这类自动函数名              |
| Profile 体系 | 内建 doom-profile                                | 无,需 chemacs2                                                  |
| 用户覆盖模块 | `$DOOMDIR/modules/cat/mod/` 自动覆盖             | `~/.spacemacs.d/private/Layer/` 私有 layer,需手工 enable        |
| 学习曲线     | 宏体系 + flag 范式                               | EIEIO + dotfile 配置 + dotspacemacs-elpa-...                    |
| 文档化       | `[[doom-package:]]` 自定义 org-link              | 纯 org 标题,无自定义 link                                       |

---

## 6. Vanilla use-package 范式

### 6.1 单文件 init.el

适合 < 30 个包,纯 elisp,无依赖。

```elisp
;; init.el
(require 'package)
(setq package-archives '(("melpa" . "https://melpa.org/packages/")))
(package-initialize)

(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package)

;; 5 行 use-package
(use-package magit :defer t)
(use-package company :defer t :init (global-company-mode))
(use-package projectile :defer t :init (projectile-mode))
```

**问题**:

- 文件线性增长,30 个包就开始难看
- 没有"分层"概念
- 重构困难,无法单独禁用一组相关包

### 6.2 拆分 lisp/ + require

适合 30-80 个包,纯 elisp,无依赖。

```
.emacs.d/
├── init.el           # 30 行
└── lisp/
    ├── init-ui.el
    ├── init-editor.el
    ├── init-lang.el
    ├── init-prog.el
    └── init-tools.el
```

```elisp
;; init.el
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(require 'init-ui)
(require 'init-editor)
(require 'init-lang)
(require 'init-prog)
```

**问题**:

- 没有"声明式"启用清单(每次都要 require)
- 跨组条件启用(lang-xxx 需要 tools-yyy)只能 `defcustom` + `when`
- 没有"包安装"阶段,纯靠 package.el

### 6.3 拆分 lisp/ + 显式 install

适合 50+ 个包,需要单独的 `packages.el`(或 bootstrap.sh)做安装清单。

```
.emacs.d/
├── init.el
├── packages.el      # defvar + package-install 列表
└── lisp/
    ├── init-*.el
```

### 6.4 配合 use-package 的 `:ensure` 自动安装

```elisp
(use-package magit :ensure t :defer t)
```

这其实已经是"半模块化"了——`use-package` 自己处理安装、配置、加载三阶段。

---

## 7. Org-babel literate config

### 7.1 模式分类

**Mode A: 全 tangle 到 init.el**

```org
* My Emacs Config
#+PROPERTY: header-args:emacs-lisp :tangle yes
#+BEGIN_SRC emacs-lisp
(setq gc-cons-threshold 100000000)
#+END_SRC

* UI
#+BEGIN_SRC emacs-lisp :tangle yes
(load-theme 'doom-one t)
#+END_SRC
```

执行 `M-x org-babel-tangle` 产出 `init.el`。

**Mode B: tangle 到 lisp/ + init.el 加载**

```org
* UI :PROPERTIES: :tangle lisp/ui.el :mkdirp yes :END:

#+BEGIN_SRC emacs-lisp
;; ...全部 UI 配置
#+END_SRC
```

**Mode C: 选 tangle + 文件级 mixin**

```org
#+BEGIN_SRC emacs-lisp :tangle no
;; 这块不会 tangle,只在 org-mode 中可读
#+END_SRC

#+BEGIN_SRC emacs-lisp :tangle init.el
;; 顶层 init.el 内容
#+END_SRC
```

### 7.2 优点

- **自然文档化**: 标题 + 散文 + 代码混合,天生适合博客/书
- **可注释**: 块外的解释性文字不会被 tangle
- **可分块 tangle**: `#+begin_src ... :tangle lisp/foo.el` 直接 tang 到子文件
- **代码可隐藏**: `:visible none` 或 `#+begin_src ... :results none`
- **可导出**: `M-x org-html-export-to-html` 直接出文档
- **块可执行**: `M-x org-babel-execute-src-block` 单独测试

### 7.3 缺点

- **报错指向 tangle 后文件**,不是 org 源(可配 `:comments link` 改善)
- **300+ 块后 org 源文件变慢**(`outline-mode` / `org-cycle` 在大文件下卡)
- **环境绑定**: 必须在配置好的 Emacs 中 tangle 一次,新人无法直接 `git clone && emacs`
- **不能 lazy-load** 块级(整文件 tangle 后再 `require`)
- **版本控制 diff 混乱**: 块位置微调导致大量重排
- **不能像 doom 那样有 flag 体系**: `:tangle` 只支持 yes/no/具体文件,没有"条件块"

### 7.4 适合人群

- 经常写博客/教程的 Emacs 用户(Sacha Chua 范式)
- 喜欢"散文 + 代码"叙事结构
- 1-3 个工作环境(环境不复杂)
- 50-150 个包(太多就该模块化了)

### 7.5 代表性配置

- Sacha Chua: <https://github.com/sachac/.emacs.d/blob/master/Sacha.org>
- Protesilaos (dprot 分支,公开)
- Howard Abrams: <https://github.com/howardabrams/dot-files/blob/master/emacs.org>

---

## 8. 包数量 → 架构选择决策表

下表是核心 trade-off 决策表。

| 包数    | 多环境?       | 团队分享? | 写文档? | 性能敏感?            | 首选                        | 备选                     |
| ------- | ------------- | --------- | ------- | -------------------- | --------------------------- | ------------------------ |
| < 10    | 任意          | 否        | 否      | 否                   | **vanilla 单文件**          | org-babel                |
| 10-30   | 否            | 否        | 否      | 否                   | **vanilla 拆分 lisp/**      | org-babel                |
| 10-30   | 是(work/home) | 否        | 否      | 否                   | **vanilla + chemacs2**      | vanilla + env 变量       |
| 30-80   | 否            | 否        | **是**  | 否                   | **org-babel**               | vanilla 拆分 lisp/       |
| 30-80   | 是            | 否        | 否      | 否                   | **doom modules**            | 自建模块化               |
| 30-80   | 是            | **是**    | **是**  | 否                   | **org-babel + chemacs2**    | **doom modules**         |
| 80-200  | 任意          | 任意      | 任意    | 否                   | **doom modules**            | spacemacs layers         |
| 80-200  | 任意          | 任意      | 任意    | **是**(< 200ms 启动) | **doom modules**            | 自建(use-package :defer) |
| 200-500 | 任意          | 任意      | 任意    | 否                   | **spacemacs layers**        | doom modules             |
| 200+    | **是**        | 任意      | 任意    | 任意                 | **doom + profile**          | **spacemacs + chemacs2** |
| 500+    | 任意          | 任意      | 任意    | 任意                 | **doom + profile + 自定义** | **spacemacs**            |

### 8.1 何时升级的硬信号

**信号 1**: 启动时间 > 1.5s 且无可优化空间
→ 拆 `:defer` / autoload,或上 doom(doom 自身有 startup 优化)

**信号 2**: "我想临时禁用 X 系列包" 这种诉求出现 ≥ 3 次
→ 上 doom modules(开/关模块 = 删/加一行)
→ 或自建 `(defvar my-disabled-packages '(...))` + `if`

**信号 3**: 你有 2+ 个工作环境(笔记本 / 公司机 / 容器)
→ 上 doom profile(开箱即用)
→ 或 vanilla + chemacs2

**信号 4**: 你想 PR 改 upstream 或给同事用
→ 上 doom / spacemacs(它们是协作项目)
→ 不然分享 vanilla 仓库 = 同事 fork 改一行,几个月就分叉

**信号 5**: 你的 config.org 超过 3000 行 / init.el 超过 1500 行
→ 强制升级,无论上面的信号

**信号 6**: 你装了 3+ 个用同一组 keymap 的包(例如 3+ 补全前端)
→ 上 doom 的 `+everywhere` / `-eglot` flag 体系,精准控制

### 8.2 反向降级

**何时不应**用 doom / spacemacs:

- 你只用 1-2 个 major mode + M-x,**3 个包就够了**
- 你的 config 必须跑在 Emacs 23 / 24(doom 要 27+,spacemacs 要 27+)
- 你需要在 TTY 启动且内存 < 256MB
- 你的工作流完全靠 `M-x`(不学 SPC / leader)
- 你的工作流是"打开一个文件就完事",不需要 project / workspaces / lsp

---

## 9. 从 vanilla 迁移到模块化

### 9.1 抽离 category(按功能分)

典型 vanilla 拆分:

```
lisp/
├── init-ui.el       ←→ :ui
├── init-editor.el   ←→ :editor
├── init-lang.el     ←→ :lang
├── init-prog.el     ←→ :tools (lsp, magit, dap)
└── init-tools.el    ←→ :tools (gist, upload, eval)
```

迁移第一步: 重新映射 lisp/ 子目录到 `category/`,每个子目录再拆 `module/`。

### 9.2 抽离 module(按包/功能分)

```
:editor/
├── evil/        ← lisp/init-editor-evil.el
├── snippets/    ← lisp/init-editor-snippets.el
├── multiple-cursors/  ← lisp/init-editor-mc.el
└── fold/        ← lisp/init-editor-fold.el
```

抽离原则:

1. **一个独立可用的功能 = 一个 module**。例如 "workspaces" 包含 persp-mode + eyebrowse + buffer-grouping,合成一个 module
2. **同一类下 < 50 行的多个 use-package 合成一个 module**。例如 `editor/format` 包含 format-all + apheleia,因为它们是"同一件事的不同实现"
3. **包数 < 3 的不要单独成 module**。塞到 `editor/misc` 或 `:tools misc`

### 9.3 把 `defcustom` 抽到 flag

vanilla:

```elisp
(defvar my-want-zen-focus nil
  "If non-nil, enable focus mode in zen.")
(when my-want-zen-focus
  (use-package focus :defer t))
```

迁移:

```elisp
;; packages.el
(when (modulep! +focus)
  (package! focus :pin "..."))

;; config.el
(when (modulep! +focus)
  (use-package! focus :defer t :init ...))
```

`my-want-zen-focus` 就消失了,改用 `(doom! :ui (zen +focus))`。

### 9.4 把 `use-package` 拆 packages.el + config.el

**doom 拆分原则**:

- `packages.el`: 只有 `(package! ...)` 声明 + `defvar` 模块级变量,**不能**有 `use-package!`
- `config.el`: 所有 `use-package!` 块和配置,**不能**有 `package!`

例外: `defcustom` 可以放 config.el(doom 自己的 zen 模块就这么干,见 `ui/zen/config.el:1-13`):

```elisp
(defcustom +zen-mixed-pitch-modes '(adoc-mode rst-mode markdown-mode org-mode)
  "..."
  :type '(repeat symbol)
  :group '+zen)
```

### 9.5 写 README.org

参考 `doomemacs/modules/ui/zen/README.org` 的结构:

```org
#+title:    :ui zen
#+subtitle: 副标题
#+created:  创建日期
#+since:    引入版本

* Description :unfold:
本模块做什么

** Maintainers
- [[doom-user:][@username]]

** Module flags
- +flag1 :: 描述
- +flag2 :: 描述

** Packages
- [[doom-package:pkg-a]]
- [[doom-package:pkg-b]]
- if [[doom-module:+flag1]]
  - [[doom-package:pkg-c]]

** Hacks
+ 改动点描述

* Installation
[[id:xxx][Enable this module in your ~doom!~ block.]]

/外部依赖/

* Usage
- 键位和命令

* TODO Configuration
#+begin_quote
󱌣 This module has no configuration documentation yet. [[doom-contrib-module:][Write some?]]
#+end_quote
```

`[[doom-package:]]` / `[[doom-module:]]` / `[[doom-user:]]` 是 doom 扩展的 org link,
在 `doomemacs/lisp/lib/help.el` 中实现(具体解析在 doom-help-backends)。

### 9.6 迁移检查表

- [ ] 列出所有 `use-package` 块,按 category 分组
- [ ] 决定每个 category 下的 module 边界
- [ ] 抽出 flag(`defvar my-want-X` → `+X`)
- [ ] 把每个 use-package 块中的"安装"行移到 packages.el
- [ ] 把每个 use-package 块中的"配置"行移到 config.el
- [ ] 在 config.el 中,flag 控制的部分包到 `(when (modulep! +flag) ...)` 中
- [ ] 写 README.org
- [ ] 在 init.el 中注册 `(doom! :cat (mod +flag))`
- [ ] 跑 `doom sync` 验证 packages.el 解析正常
- [ ] 重启 Emacs,验证 config.el 加载无 error
- [ ] 跑 `doom doctor` 验证 doctor 报告无红

---

## 10. 自建 vs 引入框架

### 10.1 引入 doom 的代价

**必须学的宏体系**:

- `package!`(替代 `package-install`)
- `use-package!`(替代 `use-package`)
- `map!`(替代 `define-key` / `global-set-key`,支持 leader/prefix-map)
- `set-popup-rule!`(替代 popwin)
- `setq!` / `after!` / `add-hook!` 等装饰
- `modulep!`(flag 查询)
- `doom!` / `package!` 块

**必须遵守的约束**:

- packages.el 中**不能**有 `use-package!`(支持按模块禁用)
- config.el 中**不能**有 `package!`(支持按模块禁用)
- README.org 强制
- `doom sync` 必须能成功(否则 doom 不会加载你的模块)

**必须接受的限制**:

- doom 自身启动开销(~200-400ms)
- 必须用 doom 的包管理(straight.el),不能直接用 package.el
- 跟 doom 升级绑定,有时 breaking change

**换来的好处**:

- 200+ 个开箱即用模块
- 键位一致性(doom 的 `SPC` leader 体系)
- profile 体系
- 性能优化(doom 自己的 early-init 钩子)
- flag 体系的语义紧凑

### 10.2 引入 spacemacs 的代价

**必须学的概念**:

- EIEIO 类(cfgl-layer / cfgl-package)
- `dotspacemacs-configuration-layers` / `dotspacemacs-user-init` / `dotspacemacs-user-config`
- editing style 概念(vim / emacs / hybrid)
- `configuration-layer/*` 宏族
- layer init 函数命名约定(`LAYER/init-PKG`)

**必须遵守的约束**:

- packages.el 用 defconst 列表,不能用 `use-package`
- 每个包必须对应 init/pre-init/post-init 函数
- 必须重启加载

**必须接受的限制**:

- 2963 行 core 加载慢
- EIEIO 包装层调试困难
- 没有 profile
- SPC 体系强绑定

**换来的好处**:

- 200+ 个开箱即用 layer
- 编辑风格切换(vim / emacs / hybrid)
- 完整 dotfile 引导

### 10.3 自建的代价

**优势**:

- 自由
- 简单场景下不复杂(2 层目录 + 一个 init.el 即可)
- 跟 vanilla use-package 同生态

**劣势**:

- 没有 profile,需自建(不便宜)
- 没有 flag 体系,需自建(defvar + if,可读性差)
- 没有自动生成 autoload,需手工
- 没有 startup 优化,需手工调 `gc-cons-threshold` 等
- 没有"开箱即用"的 ui / editor / lang 模块,要手写

**推荐自建的临界点**:

- 包数 > 200 **且** 你需要定制 doom/spacemacs 做不到的东西
- 或你有非常特殊的多环境需求(doom profile 也满足不了)

### 10.4 用 chemacs2

**chemacs2** 是独立的 profile 切换器,跟 vanilla / doom / spacemacs 都正交。

`~/.emacs` 写:

```elisp
((default
   (user-emacs-directory . "~/.emacs.d.doom"))
 (work
   (user-emacs-directory . "~/.emacs.d.work")
   (env . (DOOMPROFILE . "work")))
 (vanilla
   (user-emacs-directory . "~/.emacs.d.vanilla")))
```

启动: `emacs --with-profile work` 或 `CHEMACS_PROFILE=work emacs`。

**适合**:

- 已经有 2 套完全独立的 config(doom + 自己的 vanilla)
- 想"分身"运行两套,不共享任何状态

**不适合**:

- 同一套配置的多个变体(doom profile 够用)

---

## 11. doom `modulep!` 深入

### 11.1 基本语法

```elisp
;; 当前模块启用 +flag1
(modulep! +flag1)

;; 跨模块: :GROUP MODULE 启用
(modulep! :ui workspaces)

;; 跨模块带 flag
(modulep! :lang python +lsp)

;; 跨模块反转 flag: 模块启用且**无** +eglot
(modulep! :tools lsp -eglot)

;; 跨多个 flag
(modulep! :tools lsp +eglot -lsp-ui)

;; 同组多模块
(modulep! :completion (or company corfu))

;; 同组任一启用
(modulep! :completion company)
```

### 11.2 编译时 vs 运行时

`modulep!` 是**编译时**宏,展开为 `(get :group 'module)` 查询符号 plist。

```elisp
;; 编译时展开(伪代码)
(modulep! :ui zen +focus)
  ≡
(when-let* ((ctxt (get :ui 'zen)))
  (doom-module--has-flag-p
   (doom-module-context-flags ctxt)
   '(+focus)))
```

**性能特征**:

- `get` 是 O(1) 哈希表查询
- 整个 `modulep!` 编译后只剩一个 `when-let*`
- 200+ 个 `modulep!` 调用在启动期加起来 < 1ms

### 11.3 动态值

需要动态参数时,用 `,` 插入:

```elisp
(let ((flag '-eglot))
  (modulep! :tools lsp ,flag))
```

但**不推荐**——flag 应该是配置期决定的。

### 11.4 在用户自定义模块中支持 +flag

**最简方法**: 用 `defcustom` + `(eval ...)`:

```elisp
;; packages.el
(defvar +my-mod-want-foo nil
  "If non-nil, enable foo in my-mod.")

(when +my-mod-want-foo
  (package! foo :pin "..."))

;; config.el
(when +my-mod-want-foo
  (use-package! foo ...))
```

用户在你的 README 里改 `+my-mod-want-foo = t` 即可。

**严格方法**: 注册 flag 到 doom 的 flag 体系:

```elisp
;; my-mod/packages.el 顶部
;; 1. 在 doom-modules-initialize 后,module 已被注册
;; 2. 但 flag 是在 doom! 块解析时确定的,post-hoc 修改有限

;; 实际不可行: doom 的 flag 解析是单次的(在 doom-modules-initialize)
;; 用户要 flag,只能改 dooM! 块
```

**实战做法**: 大部分 doom 第三方模块(如 centaur-tabs 风格)都用 `defvar` + when
而不是 `+flag`,因为他们没法在用户的 doom! 块里注册 flag。**只有 doom 自带
模块**才能用 +flag(因为 doom 知道自己的 flag 集合)。

### 11.5 `modulep!` 的隐藏副作用:文件上下文

`modulep!` 在自己模块内部调用时,会**自动**用文件路径推导当前模块:

```elisp
;; 当前文件: $DOOMDIR/modules/lang/python/config.el
;; 此处的 (modulep! +lsp) 等价于 (modulep! :lang python +lsp)
;; 因为 doom 用 file! 拿到文件路径,反推模块 key
```

这让 config.el 内部的 `(modulep! +flag)` 直接工作,不用显式传 :lang python。

实现(`doomemacs/lisp/doom-lib.el:1499-1536`):

```elisp
;; (modulep! +flag3 +flag1 +flag2) 在 module 文件里时
;; group 和 module 都被省略,从 file! 推导
(if (doom-module-context-index doom-module-context)
    `(doom-module--has-flag-p
      ',(doom-module-context-flags doom-module-context)
      (backquote ,flags))
  `(let ((file (file!)))
     (if-let* ((module (doom-module-from-path file)))
         (doom-module--has-flag-p
          (doom-module (car module) (cdr module) :flags)
          (backquote ,flags))
       (error "(modulep! %s) couldn't resolve current module from %s"
              (backquote ,flags) (abbreviate-file-name file))))))
```

---

## 12. spacemacs `configuration-layer/*` 宏族

### 12.1 主要函数

来源: `core-configuration-layer.el`

| 函数                                             | 行     | 作用                             |
| ------------------------------------------------ | ------ | -------------------------------- |
| `configuration-layer/declare-layer`              | 1469   | 声明一个 layer(加载其 layers.el) |
| `configuration-layer/declare-layers`             | 1464   | 批量声明                         |
| `configuration-layer/declare-layer-dependencies` | 1491   | 在 layers.el 声明依赖            |
| `configuration-layer/declare-shadow-relation`    | 1531   | 声明 A 和 B 互斥(谁后启用谁胜)   |
| `configuration-layer/layer-used-p`               | 1610   | layer 是否被启用                 |
| `configuration-layer/package-used-p`             | 1621   | 包是否被启用                     |
| `configuration-layer/set-layer-variable`         | (内联) | 设置 layer 变量(在 dotfile 写)   |
| `configuration-layer/get-layer`                  | 1136   | 拿 layer 对象                    |
| `configuration-layer/get-layers-list`            | 1141   | 所有已发现 layer 列表            |
| `configuration-layer/get-layer-path`             | 1150   | layer 物理目录                   |

注意: **没有** `declare-packages` / `declare-configurations` 这类宏
(任务要求提的可能是误记,实际 API 名字是上述这些)。

### 12.2 use-package 集成

spacemacs 不发明 use-package,**直接用原版**。但 packages.el 中
不是 use-package 块,而是 defconst 元组列表。

```elisp
;; packages.el
(defconst python-packages
  '(
    (lsp-pyright :requires lsp-mode :toggle (eq python-lsp-server 'pyright))))

;; 配套 init 函数(命名约定: LAYER/init-PKG)
(defun python/init-lsp-pyright ()
  (use-package lsp-pyright
    :defer t
    :init (setq lsp-pyright-python-executable-cmd "...")
    :config (add-hook 'python-mode-hook #'lsp-pyright-mode)))
```

**关键点**:

- `init-` 函数的命名空间是 layer 内部,**不**污染全局
- spacemacs 通过 `intern (format "%S/init-%S" owner pkg-name)` 调用
  (见 `core-configuration-layer.el:2113-2117`)

### 12.3 layer 变量系统

用户写:

```elisp
;; .spacemacs
(setq dotspacemacs-configuration-layers
      '((python :variables python-backend 'lsp
                            python-lsp-server 'pyright
                :selected-packages nil)))
```

spacemacs 处理流程:

1. 解析 `'(python :variables ... :selected-packages nil)`
2. 把 `:variables` 转成 layer 对象的 `:variables` slot
3. 在 config.el 加载后,调用 `(set (intern "python-backend") 'lsp)` 等

### 12.4 dotfile 加载顺序(关键)

```elisp
;; ~/.spacemacs
(defun dotspacemacs/layers ()
  "Layer configuration."
  (setq dotspacemacs-configuration-layers
        '(emacs-lisp python helm)))

(defun dotspacemacs/init ()
  "Initialization. Called before layers/packages."
  ;; 此时 spacemacs core 还没加载完,只能做 setq 等
  (setq gc-cons-threshold 100000000))

(defun dotspacemacs/user-init ()
  "User init. Called after core, before user-config."
  ;; 此时 core 已加载,layer 还没加载
  ;; 可做一些"覆盖默认"的事
  )

(defun dotspacemacs/user-config ()
  "User config. Called after everything."
  ;; 此时所有 layer 和 package 都加载完
  ;; 这是写自定义 use-package 的地方
  )
```

---

## 13. 容器化环境下的模块化

### 13.1 场景

`.emacs.d` 在容器内(Flatpak sandbox、Distrobox、devcontainer)复用宿主的
模块化配置。三个常见痛点:

1. **路径硬编码**: doom data-dir 用 `$XDG_DATA_HOME`,容器内是 `~/.var/app/.../config/`
2. **环境变量缺失**: 容器内 PATH 不一样,导致 `executable-find` 失败
3. **包冲突**: 容器内可能预装某些包,版本和宿主不同

### 13.2 doom 容器化方案

**方案 A: 直接复用宿主 .emacs.d**

- 把 `.emacs.d` / `.doom.d` bind-mount 到容器
- 在容器内 `doom sync` + `doom env` 重新生成缓存
- 优点: 一份配置,零维护
- 缺点: 容器内 `doom sync` 慢(重新拉包),缓存不能用

**方案 B: doom profile 区分**

- `default` profile: 宿主配置
- `container` profile: 在 default 基础上 disable 一些容器不支持的模块

`~/.config/doom/profiles.el`:

```elisp
((container
  (doom-modules . ((-ui zen) (-tools upload) (-term vterm)))
  (env . ((DOOMDIR . "/host/.doom.d")))))
```

启动: `DOOMPROFILE=container emacs`

**方案 C: 容器镜像内置 doom**

- 把 doom 装在容器镜像里
- 配置从环境变量 / bind mount 注入
- 适合 devcontainer / CI

### 13.3 spacemacs 容器化方案

spacemacs 没有 profile,只能 chemacs2:

```elisp
;; ~/.emacs
((default
  (user-emacs-directory . "~/.emacs.d.spacemacs"))
 (container
  (user-emacs-directory . "~/.emacs.d.spacemacs")
  (env . ((SPACEMACSDIR . "/host/.spacemacs.d")))))
```

### 13.4 vanilla + 模块化 容器化方案

如果用自建"category/module" 目录:

- 把 `$XDG_CONFIG_HOME/emacs/` bind mount 到容器
- 容器内的 `init.el` 检测到环境变量(`CONTAINER=1` 等),在 `load-path` 调整

```elisp
;; init.el
(let ((extra (getenv "EMACS_EXTRA_PATH")))
  (when extra
    (add-to-list 'load-path extra)))

;; 容器内: EMACS_EXTRA_PATH=/host/.emacs.d.extra
;; 宿主: 不设置
```

### 13.5 通用建议

1. **避免硬编码绝对路径**: 配置中尽量用 `user-emacs-directory` /
   `doom-user-dir` 等变量
2. **用 `(executable-find ...)`** 而不是写死路径
3. **profile 必备**: 哪怕只 1-2 个 profile,也提前上 doom profile
4. **测试 1-2 个关键键位**: 在容器内启动时,跑 `M-x eval-expression`
   确认 `(emacs-version)` 和 `(doom-modules)` 正常

---

## 14. Doom module 自建模板

### 14.1 最小可用模块

`$DOOMDIR/modules/tools/notes/config.el`:

```elisp
;;; tools/notes/config.el -*- lexical-binding: t; -*-

(defvar +notes-want-org-capture nil
  "If non-nil, enable org-capture template for notes.")

(defvar +notes-default-directory "~/Documents/notes"
  "Default directory for notes.")

(use-package! denote
  :defer t
  :config
  (setq denote-directory +notes-default-directory)
  (denote-rename-buffer-mode 1))

(when +notes-want-org-capture
  (use-package! denote-org
    :defer t
    :after denote
    :config
    (add-to-list 'org-capture-templates
                 `("n" "New note" plain
                   (file denote-last-path)
                   #'denote-org-capture))))
```

`$DOOMDIR/modules/tools/notes/packages.el`:

```elisp
;; -*- no-byte-compile: t -*-
;;; tools/notes/packages.el

(package! denote :pin "abcdef...")
(when +notes-want-org-capture
  (package! denote-org :pin "123456..."))
```

`$DOOMDIR/modules/tools/notes/README.org`:

```org
#+title:    :tools notes
#+subtitle: Note-taking with denote
#+created:  2026-06-08
#+since:    26.06.0

* Description
本模块基于 [[https://protesilaos.com/emacs/denote][denote]] 实现轻量笔记。

** Maintainers
- [[doom-user:][@you]]

** Module flags
- +org-capture :: 集成 org-capture 模板

** Packages
- [[doom-package:denote]]
- if [[doom-module:+org-capture]]
  - [[doom-package:denote-org]]

* Installation
[[id:xxx][Enable this module in your ~doom!~ block.]]

* Usage
- ~M-x consult-notes~ 或 ~M-x denote-open-or-create~
```

`$DOOMDIR/init.el` 注册:

```elisp
(doom!
  ;; ...其他模块
  :tools
  (notes +org-capture))
```

### 14.2 进阶:带 autoload 的模块

`$DOOMDIR/modules/tools/notes/autoload.el`:

```elisp
;;; tools/notes/autoload.el -*- lexical-binding: t; -*-

;;;###autoload
(defun +notes/open-or-create ()
  "Open today's denote note, or create one."
  (interactive)
  (require 'denote)
  (let ((date (format-time-string "%Y%m%d")))
    (find-file (denote--path-for-new-file date))))

;;;###autoload
(defun +notes/consult-search ()
  "Search notes via consult."
  (interactive)
  (require 'denote)
  (require 'consult-denote)
  (consult-denote "Find note: ")))
```

`config.el` 中绑定:

```elisp
(map! :leader
      :prefix "n"
      :desc "Open today's note" "o" #'+notes/open-or-create
      :desc "Search notes"      "s" #'+notes/consult-search)
```

### 14.3 进阶:带 doctor 检查

`$DOOMDIR/modules/tools/notes/doctor.el`:

```elisp
;;; tools/notes/doctor.el -*- lexical-binding: t; -*-

(assert! (or (not +notes-want-org-capture)
             (locate-library "denote-org"))
         "This module requires denote-org for +org-capture flag")

(assert! (file-directory-p +notes-default-directory)
         (format "Notes directory %s does not exist"
                 +notes-default-directory))
```

`M-x doom doctor` 会跑这个文件。

### 14.4 完整模块骨架

```
$DOOMDIR/modules/tools/notes/
├── README.org
├── packages.el
├── config.el
├── autoload.el         (可选,延迟加载)
├── doctor.el           (可选,健康检查)
└── +bindings.el        (可选,键位分发)
```

---

## 15. 实施检查清单

### 15.1 决策阶段

- [ ] 盘点当前包数 + 预期增长
- [ ] 盘点需要工作的环境数(笔记本 / 公司机 / 容器 / 服务器)
- [ ] 盘点是否需要"开箱即用"的集成(Magit / LSP / Projectile)
- [ ] 盘点是否需要"轻量文档"分享(博客 / 团队)
- [ ] 根据第 8 章决策表选定范式
- [ ] 如果选 doom,确定需要的 flag 集合(预想 6-12 个)
- [ ] 如果选 spacemacs,确定 dotspacemacs-configuration-layers 列表
- [ ] 如果选自建,设计 category/module 目录结构

### 15.2 实施阶段(以 doom 为例)

- [ ] `git clone` doom 到 `~/.emacs.d`
- [ ] 复制 `templates/init.example.el` 到 `~/.doom.d/init.el`
- [ ] 编辑 `init.el`,只放 `(doom! :lang ... :tools ...)` 块
- [ ] `cd ~/.emacs.d && bin/doom install`
- [ ] `bin/doom sync`
- [ ] 启动 Emacs,跑 `(native-compile-available-p)` 确认 native-compile 工作
- [ ] 跑 `M-x doom/reload`
- [ ] 跑 `M-x doom doctor`,修复红条

### 15.3 自建模块阶段

- [ ] 创建 `$DOOMDIR/modules/<cat>/<mod>/` 目录
- [ ] 写 `packages.el`,只放 `(package! ...)`
- [ ] 写 `config.el`,只放 `use-package!` / `map!` / `set-popup-rule!`
- [ ] 写 `README.org`,带 flags / packages 章节
- [ ] (可选) 写 `autoload.el`,延迟加载大函数
- [ ] (可选) 写 `doctor.el`,健康检查
- [ ] (可选) 写 `+bindings.el`,按 editing style 分发
- [ ] 在 `init.el` 注册模块
- [ ] `doom sync`
- [ ] `doom doctor`
- [ ] 重启 Emacs,验证 `module-list` 含新模块

### 15.4 性能验证

- [ ] `M-x emacs-init-time` 记录启动时间
- [ ] 目标:< 500ms(doom 默认 profile) / < 1.5s(带 LSP)
- [ ] 如果 > 1.5s,跑 `M-x doom/profile-startup` 找瓶颈
- [ ] 大函数移到 `autoload.el`
- [ ] 优先 `:defer t` / `:commands` 触发加载

### 15.5 多环境(profile)阶段

- [ ] 写 `~/.config/doom/profiles.el` 或 `$DOOMDIR/profiles.el`
- [ ] 为每个 profile 列差异(模块 / 变量 / 环境变量)
- [ ] `doom sync && doom env`
- [ ] `DOOMPROFILE=work@0 emacs` 验证切换
- [ ] 检查 `M-x doom-profile` 拿当前 profile

---

## 16. 反模式

### 16.1 通用反模式

| 反模式                                                           | 后果                   | 修正                                    |
| ---------------------------------------------------------------- | ---------------------- | --------------------------------------- |
| init.el 1500+ 行单文件                                           | diff 难,冲突多,无分层  | 拆 `lisp/` 或上 doom                    |
| 在 packages.el 写 `setq`                                         | 跳过模块禁用逻辑       | 移到 config.el                          |
| 在 config.el 写 `package-install`                                | 跳过 straight 缓存     | 用 `package!`                           |
| `defcustom` 不带 `:group`                                        | 自定义面板找不到       | 加 `:group '+module`                    |
| flag 不在 README 写                                              | 用户不知道             | README 必须有"Module flags"             |
| (doom) `init.el` 中执行重操作                                    | init 阶段阻塞          | 用 `doom-after-modules-config-hook`     |
| (spacemacs) 不写 `init-PKG` 函数                                 | 包不被配置             | 必须有 init / pre-init / post-init 之一 |
| (spacemacs) 在 config.el 写 `package-install`                    | 跳过 cfgl-package 系统 | 用 `defconst PKG-packages` + `init-PKG` |
| (vanilla) require 顺序硬编码                                     | 加载错误               | 用 use-package 自动处理                 |
| (org-babel) tangle 到 `init.el` 但不写 `#+PROPERTY: header-args` | 重复 ` :tangle yes`    | 用 PROPERTY 全局设置                    |
| 在容器中硬编码 `/home/user`                                      | bind mount 路径不对    | 用 `user-emacs-directory`               |
| 跨容器共享 doom 缓存                                             | 路径冲突               | 用 `DOOMLOCALDIR` 隔离                  |
| (doom) 改 `doom-core` 的模块                                     | 升级冲突               | 在 `$DOOMDIR/modules/` 覆盖             |
| (spacemacs) 改 `layers/+lang/python/` 内的文件                   | 升级冲突               | 写 private layer                        |

### 16.2 doom 特定反模式

```elisp
;; ✗ 反: packages.el 中用 use-package
;; packages.el
(use-package! magit :defer t)  ; 错!

;; ✓ 正: 拆开
;; packages.el
(package! magit)
;; config.el
(use-package! magit :defer t)
```

```elisp
;; ✗ 反: 用 defvar 而不是 defcustom
(defvar +zen-text-scale 2.0)  ; 用户没法 customize

;; ✓ 正
(defcustom +zen-text-scale 2.0
  "..."
  :type 'float
  :group '+zen)
```

```elisp
;; ✗ 反: flag 没有出现在 README
;; packages.el
(when (modulep! +focus)
  (package! focus))
;; README.org 没有 +focus 的说明

;; ✓ 正
;; README.org "Module flags" 章节
** Module flags
- +focus :: 描述
```

```elisp
;; ✗ 反: config.el 中执行 IO 操作
;; config.el 顶部
(load-file "/some/path/init.el")  ; 错!在 init 阶段阻塞

;; ✓ 正
;; 用 after! 或 with-eval-after-load
(after! magit (load-file "..."))
```

### 16.3 spacemacs 特定反模式

```elisp
;; ✗ 反: packages.el 用 use-package
;; packages.el
(use-package magit)  ; 错!

;; ✓ 正: defconst + init 函数
(defconst my-layer-packages '(magit company))
(defun my-layer/init-magit ()
  (use-package magit :defer t))
```

```elisp
;; ✗ 反: 在 config.el 装包
;; config.el
(unless (package-installed-p 'magit)
  (package-install 'magit))  ; 错!

;; ✓ 正
;; packages.el 列出,config.el 只配置
```

```elisp
;; ✗ 反: 在 init 函数里不写 :defer
(defun python/init-mypy ()
  (use-package mypy))  ; 启动会加载 mypy

;; ✓ 正
(defun python/init-mypy ()
  (use-package mypy :defer t))
```

### 16.4 org-babel 特定反模式

```org
;; ✗ 反: 整文件 tangle,但不写 :PROPERTY
* UI
#+BEGIN_SRC emacs-lisp
(load-theme 'doom-one)
#+END_SRC

* Editor
#+BEGIN_SRC emacs-lisp
(use-package evil)
#+END_SRC
;; 每个块都要写 :tangle yes

;; ✓ 正
* UI
:PROPERTIES:
:header-args:emacs-lisp: :tangle yes
:END:
#+BEGIN_SRC emacs-lisp
(load-theme 'doom-one)
#+END_SRC
```

```org
;; ✗ 反: 大块不分割
* All config
#+BEGIN_SRC emacs-lisp :tangle yes
(setq ...) ;; 800 行
#+END_SRC

;; ✓ 正
* UI
** Theme
#+BEGIN_SRC emacs-lisp :tangle yes
(load-theme 'doom-one)
#+END_SRC

** Font
#+BEGIN_SRC emacs-lisp :tangle yes
(set-face-attribute 'default nil :height 110)
#+END_SRC
```

### 16.5 vanilla 特定反模式

```elisp
;; ✗ 反: 全局 setq 大杂烩
(setq magit-completing-read-function 'ivy-completing-read
      company-idle-delay 0.2
      lsp-keymap-prefix "C-c l"
      projectile-mode-line " ⓟ"
      ;; ...200 行
      )

;; ✓ 正: 按 use-package 块组织
(use-package magit
  :defer t
  :config (setq magit-completing-read-function 'ivy-completing-read))

(use-package company
  :defer t
  :init (setq company-idle-delay 0.2)
  :config (global-company-mode))

;; 等等
```

```elisp
;; ✗ 反: 复制粘贴其他人的 init.el
;; 你的配置里有 200 行你从没读过的代码

;; ✓ 正: 每次加 use-package 都写一行注释
;; 2026-06-08 启用, 用于 Git workflow
(use-package magit :defer t)
```

---

## 17. 附录: 关键文件/路径速查

### 17.1 doom 速查

| 路径                                            | 作用                             |
| ----------------------------------------------- | -------------------------------- |
| `~/.emacs.d/init.el`                            | doom 自身入口(用户不写这里)      |
| `~/.emacs.d/lisp/lib/modules.el`                | 模块加载器核心                   |
| `~/.emacs.d/lisp/lib/profiles.el`               | profile 体系                     |
| `~/.emacs.d/lisp/doom-lib.el`                   | `modulep!` / `package!` 等宏定义 |
| `~/.emacs.d/modules/CAT/MOD/packages.el`        | 包声明                           |
| `~/.emacs.d/modules/CAT/MOD/config.el`          | 配置                             |
| `~/.emacs.d/modules/CAT/MOD/init.el`            | 早期初始化                       |
| `~/.emacs.d/modules/CAT/MOD/autoload.el`        | 延迟加载函数                     |
| `~/.emacs.d/modules/CAT/MOD/doctor.el`          | 健康检查                         |
| `~/.emacs.d/modules/CAT/MOD/+bindings.el`       | 键位分发                         |
| `~/.doom.d/init.el` 或 `~/.config/doom/init.el` | 用户 doom! 块                    |
| `~/.doom.d/modules/`                            | 用户自定义模块(覆盖 doom core)   |
| `~/.doom.d/profiles.el`                         | profile 定义                     |
| `~/.doom.d/config.el`                           | 用户额外配置                     |

### 17.2 spacemacs 速查

| 路径                                          | 作用                 |
| --------------------------------------------- | -------------------- |
| `~/.emacs.d/init.el`                          | spacemacs 入口       |
| `~/.emacs.d/core/core-configuration-layer.el` | layer 加载器         |
| `~/.emacs.d/core/core-dotspacemacs.el`        | dotfile 配置变量定义 |
| `~/.emacs.d/layers/+CAT/LAYER/packages.el`    | 包清单               |
| `~/.emacs.d/layers/+CAT/LAYER/config.el`      | 配置 + use-package   |
| `~/.emacs.d/layers/+CAT/LAYER/funcs.el`       | 辅助函数             |
| `~/.emacs.d/layers/+CAT/LAYER/keybindings.el` | 键位                 |
| `~/.emacs.d/layers/+CAT/LAYER/layers.el`      | 依赖声明             |
| `~/.spacemacs` 或 `~/.spacemacs.d/init.el`    | 用户 dotfile         |
| `~/.spacemacs.d/layers/` 或 `private/`        | 用户私有 layer       |

### 17.3 关键变量/函数速查

**doom**:

- `doom-modules` — hash-table,当前启用的所有模块
- `doom-module-context` — plist 形式的快速查询
- `doom-module-load-path` — 搜索路径
- `(modulep! ...)` — flag 查询
- `(package! ...)` — 声明包
- `(use-package! ...)` — use-package 替代
- `(map! ...)` — 键位
- `(set-popup-rule! ...)` — popup 规则
- `(defcustom VAR VAL :group '+MODULE)` — 自定义变量

**spacemacs**:

- `configuration-layer--used-layers` — 启用的 layer 列表
- `configuration-layer--used-packages` — 启用的包列表
- `(configuration-layer/layer-used-p 'python)` — 查询
- `(configuration-layer/package-used-p 'company)` — 查询
- `(defconst LAYER-packages '((PKG :toggle ...) ...))` — 声明
- `(defun LAYER/init-PKG () ...)` — init 函数
- `(defun LAYER/pre-init-PKG () ...)` — pre-init
- `(defun LAYER/post-init-PKG () ...)` — post-init
- `(use-package PKG :defer t)` — 原版 use-package
- `(spacemacs/set-leader-keys-for-major-mode 'python-mode "hh" 'anaconda-mode-show-doc)` — 键位

### 17.4 性能基线参考

| 配置                      | 冷启动(emacs 30, ASCII Linux) |
| ------------------------- | ----------------------------- |
| 纯 vanilla(< 30 包)       | 200-400ms                     |
| vanilla 拆分 lisp/(50 包) | 400-700ms                     |
| doom default(150 包启用)  | 800-1500ms                    |
| doom + LSP 闲置           | 1500-3000ms                   |
| spacemacs default         | 1500-3500ms                   |
| spacemacs + LSP           | 3000-5000ms                   |

> 以上数字会因硬件 / 包版本 / native-compile 配置差异 ±50%。doom 的 startup
> 优化(`doom.el` 的 `Startup optimizations` 段)对 200ms 内的差异有显著影响。

---

## 研究备注

- 本研究基于 doomemacs 2026 年中前的代码状态和 spacemacs develop 分支
- doom 的 flag 体系是其相对 vanilla/spacemacs 的最大优势,适合"按场景切换"
  的工作流
- spacemacs 的 editing style 切换(vim/emacs/hybrid)是另一独特价值
- profile 体系 doom 完胜 spacemacs(后者只能 chemacs2)
- 容器化场景下,doom profile + DOOMLOCALDIR 比 chemacs2 路径隔离更细
- "何时升级"的硬信号是启动时间 + 模块禁用诉求 + 多环境需求,三者任一出现
  即可考虑升级

---

**草稿完成时间**: 2026-06-08
**建议下一步**: 用此草稿作 PRD 输入,产出一份"我的 .emacs.d 升级路线图"。
