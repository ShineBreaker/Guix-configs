# Emacs 配置审计清单(40 条可勾选项)

> 用于 `references/audit-and-refactor.md` Step 2 的逐项审查。
> 每条都对应 doom 或 spacemacs 真实代码中的范式,带简短说明。

## A. 启动性能 (10 条)

- [ ] **A1**: `early-init.el` 存在(Emacs 27+ 唯一优化窗口)
- [ ] **A2**: `gc-cons-threshold` 在启动期被设为 `most-positive-fixnum`
- [ ] **A3**: `file-name-handler-alist` 启动期被临时清空(`let` 块)
- [ ] **A4**: `package-enable-at-startup` 设为 `nil`(配合 use-package 手动 init)
- [ ] **A5**: `load-prefer-newer` 设为 `nil`(让 .elc 优先于 .el)
- [ ] **A6**: `auto-mode-case-fold` 设为 `nil`(避免二次扫描)
- [ ] **A7**: GC 阈值在 idle 时被合理恢复(`gcmh-mode` 或等价机制)
- [ ] **A8**: `bidi-display-reordering` 和 `bidi-paragraph-direction` 设为 `left-to-right`
- [ ] **A9**: `bidi-inhibit-bpa` 设为 `t`(减少重绘工作量,Emacs 27+)
- [ ] **A10**: `M-x emacs-init-time` 显示 <2s(冷启动),<0.5s(daemon)

## B. 包管理 (8 条)

- [ ] **B1**: 只用一个包管理器(`package.el` / `straight` / `elpaca` / `quelpa`)
- [ ] **B2**: 每个 `use-package` 块都有明确 lazy 触发器
- [ ] **B3**: 没有 `use-package` 块的 `:init` 里出现 `(xxx-mode 1)` 或 `(require 'xxx)`
- [ ] **B4**: 重要包(magit / vertico / eglot / consult)有 `:pin` 锁版本
- [ ] **B5**: `package-selected-packages` 与 `use-package` 声明一致(没漏)
- [ ] **B6**: 没有同时启用 `package.el` 跟 `straight`/`elpaca` 的锁文件冲突
- [ ] **B7**: `M-x use-package-report` 显示 lazy-load 比例 > 70%
- [ ] **B8**: 字节编译覆盖所有用户包(M-x `byte-recompile-directory`)

## C. 键位与 UI (8 条)

- [ ] **C1**: which-key 在 `first-input`/`first-file`/`first-buffer` 之后启用,非 init
- [ ] **C2**: leader-key 只有一个(可加 localleader,不要多个 `SPC` 系)
- [ ] **C3**: 键位绑定用统一宏(doom `map!` 或 `general.el` 的 `general-def`)
- [ ] **C4**: 每个 key 都有描述(doom `:desc` 或 vanilla `interactive "..."`)
- [ ] **C5**: 主题在 `after-init-hook` 里加载(避免闪烁)
- [ ] **C6**: popup/childframe 规则统一(doom `set-popup-rule!` 或 `popwin.el`)
- [ ] **C7**: modeline 段命名一致(prefix `+`)
- [ ] **C8**: 有 `+which-key/replacements` 机制(为不友好命令名提供描述)

## D. 外部工具集成 (8 条)

- [ ] **D1**: 用 `executable-find` 检测 ripgrep/fd/node/pyright 等,缺失时降级
- [ ] **D2**: macOS / WSL / Flatpak 上 `exec-path` 包含用户 shell 路径
- [ ] **D3**: ripgrep/ag/ack/grep 有优先级列表(如 `("rg" "ag" "grep")`)
- [ ] **D4**: LSP 启停时调 GC 阈值(doom `+lsp-optimization-mode` 范式)
- [ ] **D5**: tree-sitter 用 Emacs 29+ 内置或 `treesit-auto`,有降级路径
- [ ] **D6**: vterm 启动时检测 `module-file-suffix`(动态模块可用性)
- [ ] **D7**: magit 不跟 `global-auto-revert-mode` 混用
- [ ] **D8**: 退出时清掉 `*vterm*` buffer(doom `vterm-kill-buffer-on-exit`)

## E. 模块化结构 (6 条)

- [ ] **E1**: 有 `lisp/` 或 `modules/` 子目录(包数 > 50 时必备)
- [ ] **E2**: 同一主题下相关包集中在一个文件(如 `completion.el` 含 vertico+consult+embark)
- [ ] **E3**: 命名一致: `xxx-config.el` 放配置,`xxx-pkg.el` 放包声明
- [ ] **E4**: 文件头部用 `;;; xxx.el --- <用途> -*- lexical-binding: t -*-`
- [ ] **E5**: 包数 > 80 时考虑迁移到 doom / spacemacs / 自建模块化
- [ ] **E6**: `init.el` < 300 行(主入口只负责加载,不分发配置)

## 评分规则

- 每个勾 = 1 分
- A 维度 ≥ 9: 启动性能优秀
- B 维度 ≥ 7: 包管理规范
- C 维度 ≥ 7: 键位/UI 良好
- D 维度 ≥ 6: 外部工具集成完善
- E 维度 ≥ 5: 模块化合理
- 总分 ≥ 30: 优秀
- 20-29: 需要重构
- < 20: 急需重构

## 严重问题(任何一条都需要立即处理)

- 🚨 `init.el` 启动期 `(require 'xxx)` 超过 5 次 → 包未 lazy
- 🚨 没有 `early-init.el`(Emacs 27+)
- 🚨 `init.el` 顶层 `(load-theme 'xxx)` → 主题闪烁
- 🚨 `:init` 块里调用包内函数 → lazy 完全失效
- 🚨 启动后已加载 > 50% 包
- 🚨 `*Messages*` 有 `Error` 或持续 `Warning`
