# Emacs 配置审核与重构方法论

> 适用于"对一份现有的 Emacs 配置做体检并提出改造方案"的场景。
> 配合 `assets/audit-checklist.md` 的 40 条可勾选清单使用。

## 0. 适用范围

✅ 适合: 用户提交了 `init.el` / `early-init.el` / `config.org` / `use-package` 块,希望改善性能、可维护性、键位可发现性。

❌ 不适合: 用户刚装 Emacs 还没有 init.el(直接看 `references/startup-and-packages.md` §2-§3)。

## 1. 总览: 三步走

```
┌─────────────────────────────────────────────────────────────┐
│  Step 1: 现状评估(量化)                                     │
│  - 启动时间: emacs-init-time, benchmark-init                │
│  - 包数量: package installed count                          │
│  - lazy-load 比例: use-package report                       │
│  - 文件结构: ls -la $EMACSDIR                               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Step 2: 五维审查(定性)                                     │
│  - 启动性能 / 包管理 / 键位与 UI / 外部工具集成 / 模块化结构│
│  - 用 assets/audit-checklist.md 40 条逐项打勾               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Step 3: 重构路径(分阶段)                                   │
│  - 0-10 包: 不用动                                          │
│  - 10-30 包: 拆 lisp/ 子目录                                │
│  - 30-80 包: 引入 early-init + 全面 lazy-load               │
│  - 80-200 包: 模块化(category/module 双层)                  │
│  - 200+ 包: 考虑 doom profile / chemacs2                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 现状评估(Step 1:量化)

### 2.1 启动时间

**测量方法 1 — 手动**: `M-x emacs-init-time` 会显示上次启动耗时(秒)。

**测量方法 2 — 精确分项**: 安装 [`benchmark-init`](https://github.com/dholm/benchmark-init),在 `early-init.el` 末尾加:

```elisp
(add-hook 'after-init-hook
          (lambda () (benchmark-init/deactivate)))
```

启动后会显示每个 `init.el` 加载阶段的时间。

**测量方法 3 — 工具调用级**:

```bash
emacs --batch --eval '(progn (require (quote use-package)) (use-package-report))'
```

### 2.2 包数量与 lazy-load 比例

```elisp
;; M-x use-package-report
;; 显示:
;;  - Loaded: 已加载数 / 总数
;;  - By [:defer|:commands|...]: 各类 lazy 触发器数
;;  - Time spent loading: 总加载时间
```

**健康指标**:

- 启动后 `Loaded` ≤ 总包数的 30%
- 启动期无 `:defer nil` 包
- 没有任何 `use-package` 块的 `:init` 中调用了 `xxx-mode 1`

### 2.3 文件结构

```bash
$EMACSDIR=$(emacs --batch --eval '(princ user-emacs-directory)')
ls -la $EMACSDIR
find $EMACSDIR -name '*.el' | wc -l
find $EMACSDIR -name '*.el' -exec wc -l {} + | tail -1
```

记录:

- 总 el 文件数
- 全部行数(超过 5000 行就考虑模块化)
- 是否有 `early-init.el`(没有 = 缺失优化窗口)
- 是否有 `lisp/` `modules/` `layers/` 子目录(有 = 已有结构)

### 2.4 评估表模板

| 指标               | 当前值  | 健康值                    | 是否需要重构 |
| ------------------ | ------- | ------------------------- | ------------ |
| 启动时间           | ?s      | <0.5s daemon / <2s 冷启动 | 是 / 否      |
| 包数量             | ?       | <300                      | 是 / 否      |
| 启动后已加载       | ?       | <30%                      | 是 / 否      |
| init.el 行数       | ?       | <300                      | 是 / 否      |
| 有 early-init.el   | 是 / 否 | 是                        | 是 / 否      |
| 有模块结构         | 是 / 否 | 当包数 >80 时是           | 是 / 否      |
| 字节编译           | ?       | 100%                      | 是 / 否      |
| 启动期 GC 推迟     | 是 / 否 | 是                        | 是 / 否      |
| exec-path 修复     | 是 / 否 | 是(非 Linux 桌面)         | 是 / 否      |
| which-key 启用时机 | ?       | first-input               | 是 / 否      |

---

## 3. 五维审查(Step 2:定性)

### 3.1 启动性能审查

**核心问题**: 启动期做了哪些**不需要立即做**的事?

**典型症状**:

- `init.el` 顶部有 `(require 'xxx)` → 包未 lazy
- `init.el` 直接 `(load-theme 'xxx)` → 主题闪烁
- `init.el` 调用 `(global-xxx-mode 1)` 多个 → 链式强制加载
- `(custom-set-variables ...)` 在 `init.el` 中段 → 与 `custom.el` 冲突
- 没有 `early-init.el` → 失去 27+ 唯一优化窗口

**必查项**:

- [ ] `gc-cons-threshold` 启动期是否被推到 `most-positive-fixnum`
- [ ] `file-name-handler-alist` 启动期是否被 `let` 临时清空
- [ ] `package-enable-at-startup` 是否被设为 `nil`(配合 27+ `package.el` 早初始化)
- [ ] `load-prefer-newer` 是否被设为 `nil`(字节编译优先)
- [ ] `auto-mode-case-fold` 是否被设为 `nil`
- [ ] `site-run-file` 是否被禁用(如果用 `package.el` + `use-package` 的话)
- [ ] `gcmh-mode` 或类似 GC 策略是否在 idle 时复位 GC 阈值(避免卡顿)

详细模板见 `assets/early-init-snippets/optimal.el`。

### 3.2 包管理审查

**核心问题**: 包的来源、版本控制、懒加载是否合理?

**典型症状**:

- 用 `package-install` 手动装包,没有声明式管理 → 别人无法复现
- `package.el` 跟 `use-package` 之外的工具混用 → 重复加载
- 没有 `:pin` → 上游可能 break
- `straight.el` 跟 `package.el` 同时启用 → 锁文件冲突

**必查项**:

- [ ] 选一个包管理器并**只用它**: `package.el` + `use-package` / `straight` / `elpaca` / `quelpa`
- [ ] 每个 `use-package` 块都有明确的 lazy 触发器(`:defer`、`:commands`、`:hook`、`:mode`、`:bind`、`:custom`)
- [ ] `:init` 块里没有调用包内函数(只允许 `setq` 顶层变量)
- [ ] `:config` 块用 `with-eval-after-load` 还是包内?统一一种
- [ ] 重要包(magit、vertico、eglot 等)有 `:pin` 锁版本
- [ ] 不活跃的包(<2 年没更新)考虑替换

### 3.3 键位与 UI 审查

**核心问题**: 键位是否可发现?leader-key 是否合理?which-key 是否友好?

**典型症状**:

- which-key 启用时机不当(在 init 而不是 first-input)
- leader-key 路径分支过多(>3 层)或过深
- 键位散落多处(`global-set-key` / `define-key` / `bind-key` / `general-define-key` 混用)
- 没有"主要快捷键总览"(用户找不到常用功能)
- modeline / theme / popup 风格不一致

**必查项**:

- [ ] which-key 启用时机是 first-input / first-buffer / first-file,而非 `init.el` 顶层
- [ ] leader-key 只有 1 个(可加 localleader),没有多个 `SPC` 系
- [ ] 用统一的绑定宏(doom `map!` 或 `general.el` 的 `general-def`)
- [ ] 每个键位都带 `:desc`(doom)或 `(interactive "...")`(vanilla)描述
- [ ] 主题在 `after-init-hook` 中加载,不在 `init.el` 顶层
- [ ] popup / childframe 规则统一(doom `set-popup-rule!` 或 `popwin.el`)
- [ ] modeline 段命名一致(prefix `+`)
- [ ] 有 `+which-key/replacements` 或等价机制(为不友好的命令名提供人类可读描述)

详细清单见 `references/keybinds-ui-workspaces.md` §3 (which-key 12 条)+ §8 (可发现性陷阱)。

### 3.4 外部工具集成审查

**核心问题**: ripgrep/fd/tree-sitter/LSP/magit/vterm 等外部工具是否被正确接入?

**典型症状**:

- macOS / WSL / Flatpak 上 ripgrep 找不到 → `M-x grep` 退回内置慢 grep
- LSP server 启动慢 → 没调高 `read-process-output-max`
- vterm 启动后无法跟 eshell 区分使用
- magit 打开新 buffer 占满 frame → 没设置 side-window 规则

**必查项**:

- [ ] 用了 `executable-find` 检测外部工具,缺失时降级而非报错
- [ ] GUI 启动时 `exec-path` 包含用户 shell 的路径(macOS / WSL 必须)
- [ ] ripgrep / ag / ack / grep 有优先级列表(spacemacs `dotspacemacs-search-tools` 范式)
- [ ] LSP server 启停时调 GC 阈值(doom `+lsp-optimization-mode` 范式)
- [ ] tree-sitter 用 Emacs 29+ 内置或 `treesit-auto`,有降级路径
- [ ] vterm 启动时检测 `module-file-suffix`(动态模块可用性)
- [ ] magit 不跟 `global-auto-revert-mode` 混用(doom 用 `+magit-auto-revert`)
- [ ] 退出时清掉 `*vterm*` buffer(doom `vterm-kill-buffer-on-exit`)

详细清单见 `references/external-tools.md` §11 (工具/场景对应表)+ §12 (降级策略)。

### 3.5 模块化结构审查

**核心问题**: 包数量增长后,配置组织是否还能维护?

**典型症状**:

- `init.el` 超过 800 行
- 想找某个包的配置要翻 200 行
- 多个 major mode 的配置混在一起
- 跟人协作时,对方完全看不懂

**必查项**:

- [ ] 有 `lisp/` 子目录按主题拆分(UI / Editor / Lang / Tools / Term)
- [ ] 同一主题下,多个相关包集中在一个文件(如 `lisp/completion.el` 包含 vertico + consult + embark)
- [ ] 命名一致: `xxx-config.el` 放配置,`xxx-pkg.el` 放包声明
- [ ] 文件头部用 `;;; xxx.el --- <用途> -*- lexical-binding: t -*-` 标准化
- [ ] 第三方贡献清晰(从 doom module 或 spacemacs layer 学)
- [ ] 当包数 > 80 时,考虑迁移到 doom / spacemacs / chemacs2 风格

详细决策表见 `references/modules-and-architecture.md` §8。

---

## 4. 重构路径(Step 3:分阶段)

### 阶段 0: 准备(无论何种规模都先做)

1. **备份**: `cp -r ~/.emacs.d ~/.emacs.d.bak.$(date +%Y%m%d)`
2. **基准**: 测启动时间,记录 `init.el` 行数
3. **版本控制**: `git init ~/.emacs.d && cd ~/.emacs.d && git add -A && git commit -m "snapshot before refactor"`
4. **结构固定**: 写一份 `README.md` 说明此配置的用途、目标 Emacs 版本、外部依赖

### 阶段 1: 拆 early-init(适用于所有规模)

**目标**: 拿到 Emacs 27+ 唯一的"零负担优化窗口"。

**操作**:

1. 创建 `$EMACSDIR/early-init.el`
2. 拷贝以下片段(完整版见 `assets/early-init-snippets/optimal.el`):

   ```elisp
   ;;; early-init.el --- early optimizations -*- lexical-binding: t -*-
   ;;; Commentary:
   ;;; Loaded before init.el, before package.el, before UI.
   ;;; Only put things here that prevent expensive work later.

   ;; Defer GC during startup (must be reset later via gcmh-mode or similar)
   (setq gc-cons-percentage 1.0
         gc-cons-threshold most-positive-fixnum
         load-prefer-newer nil
         ;; Don't let `package.el' auto-initialize (we use straight/elpaca)
         package-enable-at-startup nil)

   ;; Empty file-name-handler-alist for fast expand-file-name
   (let ((file-name-handler-alist nil))
     ;; Do file operations here if needed
     )
   ```

3. 验证: 重启 Emacs,确认启动时间有改善(M-x emacs-init-time)

**重构前 → 重构后预期**: 启动时间下降 100-300ms。

### 阶段 2: 全面 lazy-load(包数 30+)

**目标**: 启动后已加载包数 < 30%。

**操作**:

1. 用 `M-x use-package-report` 找"启动期就加载但其实可以懒"的包
2. 给每个"启动期加载"的包加 `:defer t` 或合适的触发器(详见 `references/startup-and-packages.md` §4)
3. 把所有 `use-package` 的 `:init` 块里**调用包内函数**的代码挪到 `:config`(重要!否则 lazy 失效)
4. 用 `benchmark-init` 对比重构前后的启动时间

**反模式自检**:

- [ ] 没有 `use-package` 块的 `:init` 里出现 `(xxx-mode 1)`
- [ ] 没有 `use-package` 块的 `:init` 里出现 `(require 'xxx)`(那是 redundant)
- [ ] 所有 `load-theme` 在 `after-init-hook` 里
- [ ] 所有 `global-xxx-mode` 在 `after-init-hook` 里(避免链式强制加载)

**重构前 → 重构后预期**: 启动时间再降 200-500ms,首屏更快。

### 阶段 3: 模块化(包数 80+)

**目标**: 配置可读、可维护、可分享。

**决策**: 选一个范式

| 范式                  | 适用        | 学习成本       | 复用性     |
| --------------------- | ----------- | -------------- | ---------- |
| **手拆 lisp/**        | 包数 30-100 | 低             | 低(自己的) |
| **doom-style 自建**   | 包数 80-200 | 中             | 中         |
| **引入 doom**         | 包数 200+   | 高(doom 宏)    | 高         |
| **引入 spacemacs**    | 包数 200+   | 高(layer 生态) | 高         |
| **chemacs2 profiles** | 多环境切换  | 低             | 高         |

**操作**(以 doom-style 自建为例,完整模板见 `assets/doom-module-template/`):

```
$EMACSDIR/
├── early-init.el
├── init.el
├── lisp/
│   ├── +defaults.el            ; 全局默认
│   ├── +keybindings.el         ; 键位(doom 风格 map!)
│   ├── +ui.el                  ; UI 加载入口
│   ├── +editor.el              ; 编辑器相关
│   ├── +tools.el               ; 工具
│   └── +lang.el                ; 语言
├── modules/
│   ├── ui/
│   │   ├── completion/
│   │   │   ├── config.el
│   │   │   ├── packages.el
│   │   │   └── autoload.el
│   │   ├── workspaces/
│   │   └── ...
│   ├── editor/
│   │   ├── evil/
│   │   └── snippets/
│   ├── tools/
│   │   ├── magit/
│   │   ├── lsp/
│   │   └── tree-sitter/
│   └── lang/
│       ├── python/
│       ├── rust/
│       └── web/
└── README.md
```

`init.el` 只负责按需 `load!` 各 category:

```elisp
;;; init.el -*- lexical-binding: t -*-
(load! "+defaults")
(load! "+keybindings")
;; ...
```

**重构前 → 重构后预期**: `init.el` 从 1500 行变 50 行,新加模块只需在 `modules/<cat>/<mod>/` 加一个目录。

### 阶段 4: 性能微调(包数 150+ 或启动仍慢)

**目标**: 进一步优化,达到 <0.5s 启动。

**操作**:

1. `doom-load-packages-incrementally` 范式: idle 时分批加载,见 `references/startup-and-packages.md` §6
2. `doom-first-input-hook` 范式: 把 which-key / vertico / modeline 全部挂这里
3. 字节编译: 排除不会改的包,加速加载
4. 用 `gcmh-mode`(由 doom 提供)管理 GC 阈值

### 阶段 5: 多环境/多 profile(可选)

**目标**: 工作/个人/旧配置切换。

**操作**: 引入 `chemacs2`(`~/.emacs-profiles.el` 声明多 profile),或用 doom 的 `profiles/` 机制。

---

## 5. 验证回归(必做)

重构后必须验证:

1. **启动时间**: `M-x emacs-init-time` 不应增加
2. **行为一致**: 跑一次"日常编辑器操作清单"(打开文件、搜索、补全、保存、git status),确认跟重构前体验一致
3. **包数量**: `package-selected-packages` 不应减少(除非主动卸载)
4. **byte-compile**: `M-x byte-compile-file` 全部模块,无 warning(doom 在 `bin/doom` 里有 `doom compile`)
5. **错误日志**: `*Messages*` 不应有 `Warning` 或 `Error`

如果发现回归,**回滚**:

```bash
cd ~/.emacs.d && git checkout . && git clean -fd
```

---

## 6. 案例研究(简版)

### 案例 1: 800 行 init.el,启动 4.2s

**症状**:

- 启动后已加载 85% 包
- `init.el` 直接 `(load-theme 'doom-one)`
- 多个 `(global-xxx-mode 1)`
- 没有 `early-init.el`

**重构(3 个 commit)**:

1. `feat: split early-init.el with GC defer + file-name-handler-alist` → 启动 4.2s → 3.5s
2. `feat: move all global-mode to after-init-hook + defer all use-package` → 启动 3.5s → 1.8s
3. `feat: split lisp/ into ui, editor, tools, lang` → 启动 1.8s → 1.6s,可读性大幅提升

### 案例 2: 50+ 包,which-key 一团乱

**症状**:

- 60+ 个 leader-key 绑定,3 层嵌套
- which-key popup 高度 > 15 行,看不清
- 不知道哪个 key 是干什么的

**重构**:

1. 引入分类标题:`spacemacs/declare-prefix "..." "Window"` 等,或 doom `map! :prefix "SPC w" :desc "Window"`
2. 拆分 leader-key:`SPC` 全局,`,` 备用,`SPC m` localleader
3. which-key 优化:`which-key-min-display-lines 6`、`which-key-side-window-slot -10`、`which-key-add-key-based-replacements`
4. 详情见 `references/keybinds-ui-workspaces.md` §3

---

## 7. 附:常见反驳与解答

| 反驳                                              | 解答                                                                                                    |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| "我的 init.el 才 200 行,不需要重构"               | 是的,不需要。`init.el` 越短越早重构越好。                                                               |
| "doom 强制我用它的宏,我不想被锁定"                | 选 chemacs2 或自建模块化。doom 不是唯一选择。                                                           |
| "我装包用 M-x package-install,懒得写 use-package" | 短期省事,长期必后悔。任何超过 30 包的配置都需要声明式管理。                                             |
| "字节编译没什么用"                                | 字节编译让 `load` 快 30-50%,在 100+ 包时差异显著(doom 默认编译所有 `lisp/`)                             |
| "我用 daemon,启动时间无所谓"                      | daemon 也需要"冷启动"和"首屏",该优化的还是优化。                                                        |
| "use-package 已经很好了,不需要新框架"             | `use-package` 是基础,doom 的 `use-package!` 加了 `modulep!` 集成、`:when`、`:preface` 等扩展,体验更好。 |
| "org-babel tangle 才是未来"                       | 如果你想要 literate config,确实;否则 tangling 的开销(启动需 `org-babel-load-file`)不划算。              |

---

## 8. 配套工具

- `assets/audit-checklist.md` — 40 条可勾选审计项(精简版)
- `assets/early-init-snippets/optimal.el` — 早期优化完整代码
- `assets/use-package-patterns.el` — 12 种 use-package 模式
- `assets/lsp-server-degradation.el` — 外部依赖缺失时的降级
- `assets/doom-module-template/` — doom 风格自建模块骨架
- `references/startup-and-packages.md` — 启动+包管理深度参考
- `references/keybinds-ui-workspaces.md` — 键位+UI 深度参考
- `references/external-tools.md` — 外部工具集成深度参考
- `references/modules-and-architecture.md` — 模块化架构对比
