---
name: emacs-config
description: 配置或重构 GNU Emacs 的最佳范式指南。当用户提到"配置 Emacs"、"emacs init.el 怎么写"、"emacs 启动太慢"、"which-key 怎么分类"、"emacs 模块怎么组织"、"use-package 怎么用"、"用 ripgrep/LSP/vterm 加速 Emacs"、"doom emacs vs spacemacs 怎么选"、"emacs 配置重构"、"audit 我的 emacs 配置"时使用。基于对 doomemacs 与 spacemacs 两大生产级框架的真实代码剖析,提炼"从裸 init.el 增长到 200+ 包"全程的可复用范式、决策表与反模式。
metadata:
  version: 1.0.0
  sources:
    - doomemacs (doom v25.01.0-pre)
    - spacemacs (develop branch, 2026-06)
  research-date: 2026-06-08
---

# emacs-config — Emacs 配置最佳范式

> 经验证的真实代码范例,基于对 doomemacs / spacemacs 逐文件剖析。完整 5 条核心原则 + 源码佐证 → `references/principles.md`。

## 核心原则(doom / spacemacs 共同范式)

> 完整 5 条原则 + 源码佐证 → `references/principles.md`

1. **early-init.el 是真正的主入口** — 唯一的"零负担优化窗口"
2. **不要让 Emacs 在启动期"知道"任何不需要立即用的包** — `:defer` / `:hook` / `:mode` / `:bind`
3. **用"等待时机"代替"全部加载"** — `doom-first-input-hook` / `doom-first-file-hook` / `doom-first-buffer-hook`
4. **用 macro 把范式固化成 DSL** — `package!` / `use-package!` / `map!`
5. **把"包"组织成"功能单元"，而非按字母排序的清单** — doom `modules/<category>/<module>/` 双层目录

## 决策树(用户的第一入口)

```
你想做什么?

├─ 1. 从零开始写 init.el
│   └─ §2(early-init 模板), §6(vanilla use-package 范式)
│
├─ 2. init.el 启动变慢(<1s → 5s+)
│   └─ §9(瓶颈定位), §2(early-init 优化), §5-§6(doom first-* + incremental)
│
├─ 3. init.el 超过 500 行,开始混乱
│   └─ §8(包数量 → 架构), §9(vanilla → 模块化迁移 6 步)
│
├─ 4. 我想用 doom / spacemacs 风格
│   ├─ 性能优先 + 愿意学 doom 宏体系 → doom(§4, §10)
│   ├─ 想要现成 layer 生态(700+ 主题 layer) + 声明式 dotspacemacs → spacemacs(§5, §10)
│   ├─ 想完全控制 + 不引入大依赖 + init.el 已 500+ 行 → 自建模块化(`assets/doom-module-template/`)
│   ├─ 多个 Emacs 配置要快速切换(工作/个人/旧) → chemacs2(profiles 切换)
│   └─ 想要 literate config(文档即配置) → org-babel tangle
│
├─ 5. 100+ 包,键位/which-key 一团乱
│   └─ §3(which-key 12 条), §8(可发现性陷阱)
│
├─ 6. 想用外部工具加速 Emacs 内部
│   └─ §2(exec-path), §3(ripgrep), §5(LSP), §11(工具/场景对应表)
│
├─ 7. 审计一份现有 Emacs 配置
    │   └─ `references/audit-and-refactor.md` + `assets/audit-checklist.md`(40 条)
│
└─ 8. 写完 .el 怎么验证(避免数括号)
    └─ `references/E-validating-elisp.md` + `scripts/` (4 个 shell 包装)
```

§N 编号对应见底部 references 清单。审计流程详见 `references/audit-and-refactor.md`(现状评估 / 五维审查 / 重构路径 / 验证回归)。

### §N 章节索引

| §N  | 内容                     | 文件                            |
| --- | ------------------------ | ------------------------------- |
| §2  | early-init.el 优化       | `A-startup-and-packages.md`     |
| §3  | which-key 集成           | `B-keybinds-ui-workspaces.md`   |
| §5  | Doom "等待时机"三 hook   | `A-startup-and-packages.md`     |
| §6  | Vanilla use-package 范式 | `D-modules-and-architecture.md` |
| §8  | 包数量 → 架构选择        | `D-modules-and-architecture.md` |
| §9  | 瓶颈定位方法论           | `A-startup-and-packages.md`     |
| §10 | Doom vs Spacemacs 对比表 | `A-startup-and-packages.md`     |
| §11 | 工具/场景对应表          | `C-external-tools.md`           |

## 反模式速查(高频 6 条;完整 11 条见 `references/audit-and-refactor.md`)

| 反模式                                             | 修复                                                     |
| -------------------------------------------------- | -------------------------------------------------------- |
| agent 自己数 `(`/`)` 括号                          | 调 `check-parens` / `scripts/elisp-compile.sh`           |
| `:init` 里调包内函数                               | 挪到 `:config`                                           |
| `which-key-mode` 写在 `init.el` 顶层               | 挂 `doom-first-input`                                    |
| 配置文件不区分 `early-init.el`                     | 拆 `early-init.el`(启动期) + `init.el`(主配置)           |
| 主题在 `init.el` 里直接 `load-theme`               | 用 `doom-after-init-hook` 或 `after-init-hook`           |
| 键位散落多处(`global-set-key` / `define-key` 混用) | 统一一个宏: doom `map!` 或 `general.el` 的 `general-def` |

## 资产 (assets/)

- `early-init-snippets/` — 早期优化综合模板(GC 推迟 / file-name-handler-alist / GUI 关闭)
- `doom-module-template/` — doom 风格自建模块的最小骨架
- `audit-checklist.md` — 40 条可勾选审计项
- `use-package-patterns.el` — 12 种最常见 use-package 模式
- `lsp-server-degradation.el` — 外部依赖缺失时的降级策略

## 验证脚本 (scripts/)

通过 `emacsclient` 走本机 daemon 做 byte-compile / reload / 跑测试 / 清理 .elc。详细见 `references/E-validating-elisp.md`。

- `elisp-compile.sh` — 单文件 byte-compile + 自动清理 .elc
- `elisp-reload.sh` — `load-file` 到运行中的 daemon
- `run-tests.sh` — ERT 跑测试,返回失败数作为退出码
- `clean-up-elc.sh` — 删 .elc 产物

ENV 变量: `EMACS_CONFIG_LOAD_PATH` / `EMACS_TEST_DIR` / `EMACSCLIENT_EXECUTABLE`。脚本用法详见 `scripts/README.md`。

## 参考文档 (references/)

§N 编号对应:

| 引用前缀 | 文件                            | 范围                                  |
| -------- | ------------------------------- | ------------------------------------- |
| startup  | `A-startup-and-packages.md`     | 启动优化 + 包管理(1802 行)            |
| keybinds | `B-keybinds-ui-workspaces.md`   | 键位 + which-key + UI(1582 行)        |
| external | `C-external-tools.md`           | 外部工具集成(1923 行)                 |
| modules  | `D-modules-and-architecture.md` | 模块化架构对比(1901 行)               |
| audit    | `audit-and-refactor.md`         | 审核与重构方法论(446 行)              |
| validate | `E-validating-elisp.md`         | 验证 .el / emacsclient(207 行)        |
| —        | `principles.md`                 | 5 条核心原则完整版(本 skill 主页链接) |
