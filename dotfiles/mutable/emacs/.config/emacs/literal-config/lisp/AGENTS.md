# AGENTS.md — lisp/ 外置模块规范

本目录存放 `literal-config` 的外置 `.el` 模块。模块间通过**直接 `require`** 表达依赖(见 [ADR-0002](../docs/domain/adr/0002-direct-require-for-sibling-modules.md)),加载顺序由 `../emacs.org`(tangle 自 `../init.el` 即 `main.el`)的 require 链保证。

**核心目标**:模块头部 `require` 即依赖图,阅读 `.el` 顶部就能看清它依赖谁;加载失败时报清晰的 void-function / file-missing 错误,而非注入点为 nil 的间接错误。

> 历史背景:本目录曾采用「defvar 注入点解耦」(ADR-0001,模块零跨模块 require、init.el 用 setq 注入函数)。2026-07 审查后确认这些模块全在同一仓库、不单独分发,注入点的复杂度(Lisp-2 同名歧义、byte-compile 警告、注入顺序敏感性)回报不成立,遂改为直接 require。详见 ADR-0002。

## 模块分类

| 类型                 | 模块                                       | 说明                                                                      |
| -------------------- | ------------------------------------------ | ------------------------------------------------------------------------- |
| **基座**(被 require) | `literal-bootstrap.el`、`literal-frame.el` | 提供路径常量、`executable-*` 缓存、frame hook 实现;被其他模块直接 require |
| **叶子/中间模块**    | 其余 11 个模块                             | 按需 `require` 依赖的基座/兄弟模块,直接调用对应函数(带 `fboundp` 守卫)    |

## 依赖表达机制

### 机制 1:路径常量 — 直接 require bootstrap

`literal-bootstrap.el` 用 `defconst` 定义路径常量(`literal:org-directory` 等)。需要这些常量的模块直接 `(require 'literal-bootstrap)` 后引用符号:

```elisp
;; ✅ 正确:require bootstrap,直接引用 defconst
(require 'literal-bootstrap)
(defcustom literal/some-path (expand-file-name "foo" literal:org-directory) ...)
```

init.el 在最开头 require bootstrap(emacs.org 启动域),保证后续模块 require 时常量已就绪。

### 机制 2:frame hook — 直接 require literal-frame

`literal-frame.el` 用 `defun` 定义 `literal/add-frame-hook` / `literal/remove-frame-hook`(**函数**)。需要 frame 生命周期的模块(color-scheme / dashboard / completion)直接 require 后调用函数:

```elisp
;; literal-color-scheme.el 顶部
(require 'literal-frame)
;; ...
;; 注册到 frame 生命周期(直接函数调用)
(literal/add-frame-hook #'literal/color-scheme-delayed-init)
(literal/add-frame-hook #'literal/color-scheme-apply-for-frame)
```

```elisp
;; ✅ 正确:require frame 后直接调用函数
(literal/add-frame-hook #'my-setup)

;; ❌ 旧模式(已废弃):defvar 注入点 + funcall 变量
(defvar literal/add-frame-hook nil ...)
(setq literal/add-frame-hook #'literal/add-frame-hook)  ; init.el 注入
(funcall literal/add-frame-hook #'my-setup)             ; 调变量
```

### 机制 3:跨模块函数 — 直接 require + fboundp 守卫

模块 A 需要调用模块 B 的函数时,A 直接 `(require 'B)` 后调用。调用点加 `fboundp` / `boundp` 守卫,使单模块在交互测试中即使依赖未加载也不崩溃(防御性,非主路径):

```elisp
;; literal-dashboard.el 顶部
(require 'literal-org-knowledge)   ; 提供 literal/knowledge-collect-org-files
(require 'literal-help)            ; 提供 literal/help--extract-dashboard-bindings
(require 'literal-color-scheme)    ; 提供 literal/register-buffer-refresh!
;; ...
;; 调用点(带 fboundp 守卫 + fallback)
(dolist (f (funcall (or (when (fboundp 'literal/knowledge-collect-org-files)
                          #'literal/knowledge-collect-org-files)
                        (lambda (d) (directory-files-recursively d "\\.org\\'")))
                    exp-dir))
  ...)
```

**命名约定**:跨模块调用走**公开名**(单横线 `literal/foo`)。双横线 `literal/foo--bar` 是模块私有约定,不跨模块调用;若需暴露私有函数,用 `(defalias 'literal/public-name #'literal/module--private)` 导出公开别名。

### 机制 4:通用工具函数 — 拷贝私有副本(保留)

`literal/call-process` 被 org-knowledge 和 org-agenote 共用。这类 8 行小工具**各模块拷贝私有副本**(命名 `literal/<module>--call-process`),不提取成被 require 的公共文件。原因:提取会引入新的"工具基座"模块,为 8 行代码增加一个依赖节点不划算;这类纯工具函数无状态、无外部依赖,拷贝无害。

## init.el 加载顺序约束

`main.el`(tangle 自 `emacs.org`)的 require 链必须满足拓扑序:

```
1. literal-bootstrap         (defconst 路径常量 + executable-* 缓存)
2. literal-frame             (defun frame hook 实现)
3. literal-git               (require bootstrap 复用 literal:executable-git)
4. literal-color-scheme      (require literal-frame 调 frame hook)
5. literal-tab-line / literal-modeline / literal-help
6. literal-context-menu / literal-which-key-data
7. literal-org-knowledge / literal-org-agenote  (require bootstrap 复用路径常量)
8. literal-completion        (require literal-frame 注册 per-frame childframe 适配)
9. literal-dashboard         (require frame/knowledge/help/color-scheme,最后加载)
```

**新增模块时**:在头部 `require` 它依赖的模块,并在 emacs.org 对应功能域的 require 串里把新模块放在其依赖之后。

## 模块依赖速查

| 模块                                                                 | require 的 literal-* 兄弟                           | 提供的关键公开函数 / 变量                                                                |
| -------------------------------------------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `literal-bootstrap`                                                  | (无)                                                | `literal:org-directory` 等 defconst、`literal:executable-*`                              |
| `literal-frame`                                                      | (无)                                                | `literal/add-frame-hook`、`literal/remove-frame-hook`、`literal/daemon-runtime-p`        |
| `literal-git`                                                        | bootstrap                                           | `literal/git-*`、`literal/register-side-window`、`literal/display-buffer-in-main-window` |
| `literal-color-scheme`                                               | literal-frame                                       | `literal/register-buffer-refresh!`、`literal/register-theme-refresh!`                    |
| `literal-dashboard`                                                  | frame / bootstrap / knowledge / help / color-scheme | `literal/dashboard-open-for-client-frame`、`literal/dashboard-invalidate-cache`          |
| `literal-completion`                                                 | literal-frame                                       | vertico/corfu/cape 框架配置、`literal/completion-setup-display`                          |
| `literal-org-knowledge`                                              | bootstrap                                           | `literal/knowledge-*`、`literal/knowledge-collect-org-files`                             |
| 其余(tab-line/modeline/help/context-menu/which-key-data/org-agenote) | bootstrap(部分)                                     | 各自功能                                                                                 |

## 验证(修改本目录文件后必做)

```bash
cd lisp/

# 1. byte-compile 改过的模块(检查 free-variable / void-function 警告)
emacs --batch -L . -f batch-byte-compile literal-color-scheme.el literal-dashboard.el literal-completion.el 2>&1

# 2. 完整 main.el 加载(在上级目录)
cd ..
emacs --batch -L . -L lisp --eval "
  (let ((user-emacs-directory default-directory))
    (load \"main.el\" nil t nil))" 2>&1 | grep -iE 'error|warning'
```

## 与上层 AGENTS.md 的边界

本文件只管 `lisp/` 目录的**模块依赖规范**。以下信息在上层 `general-config/AGENTS.md`(不在此重复):

- Emacs 配置整体架构、加载阶段、daemon/client 约束
- which-key 维护范式、外部命令加速范式
- Stow 部署模型、验证流程、`.el` 编写检查

模块内部的**设计决策、行为陷阱、与其他模块的功能关系**写到各 `.el` 的 `;;; Commentary:`,不堆进本文件。
