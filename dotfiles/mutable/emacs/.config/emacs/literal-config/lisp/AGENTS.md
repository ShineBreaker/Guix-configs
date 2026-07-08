# AGENTS.md — lisp/ 外置模块插件化规范

本目录存放 `literal-config` 的外置 `.el` 模块。所有模块**必须遵循自包含插件化规范**——零跨模块 `require`，模块间不直接耦合，所有联系由 `../init.el`（tangle 自 `../emacs.org`）编排。

**核心目标**：任一 `.el` 模块可独立 `M-x load-file` 加载（可能功能降级，但不报 void-function / void-variable），方便单独分享、移植、复用。

## 硬约束

<critical>
1. **禁止** 在本目录任何 `.el` 中 `(require 'literal-...)` 引用本目录其他模块。
2. 模块用到的、原本由 `literal-bootstrap.el` / `literal-frame.el` 定义的符号，一律改为**本模块自带 `defvar` 注入点**（默认 nil），由 `init.el` 在 `require` 本模块前/后注入真实值。
3. 跨模块函数调用一律走**回调注入点**（`defvar ...-fn nil` + `(when fn (funcall fn ...))`），不直接调用其他模块的函数。
4. 通用工具函数（如 `call-process`）若被多个模块共用，**各模块拷贝私有副本**（命名 `literal/<module>--call-process`），不提取公共依赖。
5. 模块的 `;;; Commentary:` 必须声明其注入点（注入哪些变量、init.el 何时注入），方便分享者理解依赖。
</critical>

## 模块分类

| 类型                       | 模块                                       | 说明                                                                                                     |
| -------------------------- | ------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| **常量源**（init.el 专用） | `literal-bootstrap.el`、`literal-frame.el` | 仅 `init.el` require；提供路径常量、`executable-*` 缓存、frame hook 实现。**不**被本目录其他模块 require |
| **自包含插件**             | 其余 10 个模块                             | 零跨模块 require；通过注入点接收外部依赖                                                                 |

## 插件化解耦机制

### 机制 1：路径常量 — `defconst` 优先 + `defvar` 不覆盖

`literal-bootstrap.el` 用 `defconst` 定义路径常量（`literal:org-directory` 等）。`init.el` 先加载 bootstrap，使这些常量绑定值。插件模块用**同名 `defvar`** 声明（默认 nil）：

```elisp
;; literal-org-knowledge.el 头部
(defvar literal:org-directory nil
  "Org 文件根目录。由 init.el 注入。")
```

**关键原理**：`defvar` 不会覆盖已 bound 的变量。bootstrap 的 `defconst` 先执行并绑定值后，模块的 `defvar` 只是声明（保持已 bound 值）。因此路径常量自动生效，`init.el` 无需额外注入。

```elisp
;; ✅ 正确：模块自带 defvar 注入点，bootstrap defconst 自动生效
(defvar literal:org-directory nil "...")

;; ❌ 禁止：require 其他模块获取常量
(require 'literal-bootstrap)
```

**验证**：`defconst` 后再 `defvar` 同名，值保留为 defconst 的值（已验证）。

### 机制 2：frame hook — Lisp-2 双命名空间注入

`literal-frame.el` 用 `defun` 定义 `literal/add-frame-hook`（**函数**）。需要 frame 生命周期的插件模块（color-scheme、dashboard）用**同名 `defvar`** 声明注入点（**变量**，默认 nil）：

```elisp
;; literal-color-scheme.el 头部
(defvar literal/add-frame-hook nil
  "注册函数在每个新 frame 创建时执行的 hook。
由 init.el 注入 literal-frame.el 的实现。nil 时 per-frame 初始化跳过。")
```

`init.el` 加载 frame 后注入：

```elisp
;; init.el（emacs.org 的 Frame 生命周期块）
(require 'literal-frame)
(setq literal/add-frame-hook    #'literal/add-frame-hook
      literal/remove-frame-hook #'literal/remove-frame-hook)
```

**关键原理**：Emacs Lisp 是 Lisp-2，函数与变量有独立命名空间。`defun literal/add-frame-hook`（函数）与 `defvar literal/add-frame-hook`（变量）同名共存。模块用 `(funcall literal/add-frame-hook fn)` 调用变量值（函数对象）。

```elisp
;; ✅ 正确：模块内部用 funcall 软调用注入点（检查 nil）
(when (functionp literal/add-frame-hook)
  (funcall literal/add-frame-hook #'my-setup))

;; ❌ 禁止：直接调用（nil 时 void-function）
(literal/add-frame-hook #'my-setup)
```

**验证**：`defun` 与 `defvar` 同名共存，`setq` 变量为函数对象后 `funcall` 正确调用（已验证）。

### 机制 3：跨模块函数 — 回调注入点

模块 A 需要调用模块 B 的函数时，**A 不 require B**，而是在 A 头部定义 `defvar ...-fn nil` 注入点，`init.el` 在加载 B 后注入 B 的函数到 A 的注入点。

```elisp
;; literal-dashboard.el 头部（4 个回调注入点）
(defvar literal/dashboard-collect-knowledge-files-fn nil
  "收集知识库 org 文件的函数。init.el 注入 literal/knowledge--collect-org-files。
nil 时回退到 directory-files-recursively。")
(defvar literal/dashboard-extract-bindings-fn nil
  "提取快捷键的函数。init.el 注入 literal/help--extract-dashboard-bindings。")
;; ... 共 4 个

;; 模块内部用 when + funcall 软调用，并提供回退
(defun literal/dashboard--compute-recent-knowledge-entries (max-items)
  (dolist (f (funcall (or literal/dashboard-collect-knowledge-files-fn
                          (lambda (d) (directory-files-recursively d "\\.org\\'")))
                      exp-dir))
    ...))
```

`init.el` 在所有依赖加载后注入（注意顺序：dashboard 必须在 knowledge/help/color-scheme 之后加载）：

```elisp
;; init.el 末尾（Dashboard 回调注入块）
(require 'literal-org-knowledge)   ; 提供 literal/knowledge--collect-org-files
(require 'literal-help)            ; 提供 literal/help--extract-dashboard-bindings
(require 'literal-color-scheme)    ; 提供 literal/register-buffer-refresh!

(setq literal/dashboard-collect-knowledge-files-fn #'literal/knowledge--collect-org-files
      literal/dashboard-open-knowledge-file-fn     #'literal/knowledge-open-file
      literal/dashboard-extract-bindings-fn        #'literal/help--extract-dashboard-bindings
      literal/dashboard-register-refresh-fn        #'literal/register-buffer-refresh!)

(require 'literal-dashboard)       ; 回调已注入，最后加载 dashboard
```

### 机制 4：通用工具函数 — 拷贝私有副本

`literal/call-process` 被 org-knowledge 和 org-agenote 共用。为保持零依赖，**各模块拷贝私有副本**（8 行），命名 `literal/<module>--call-process`：

```elisp
;; literal-org-knowledge.el
(defun literal/knowledge--call-process (command &rest args)
  "同步执行 COMMAND 与 ARGS，返回 (STATUS . OUTPUT)。本模块私有拷贝。"
  (with-temp-buffer
    (cons (or (apply #'call-process command nil t nil (remq nil args)) -1)
          (string-trim (buffer-string)))))

;; literal-org-agenote.el（各自拷贝）
(defun literal/agenote--call-process (command &rest args)
  ...)
```

**为何不提取公共依赖**：提取即引入跨模块 require，违背插件化目标。8 行代码重复 < 1 个隐式依赖。

## init.el 编排约束

`init.el`（tangle 自 `../emacs.org`）是唯一编排者。加载顺序必须满足：

```
1. literal-bootstrap   （defconst 路径常量 → 让模块 defvar 自动生效）
2. literal-frame       → setq 注入 frame hook 到 color-scheme/dashboard 的 defvar
3. literal-git         （literal:executable-git 由 defconst 自动生效）
4. literal-color-scheme（frame hook 已注入）
5. literal-tab-line / literal-modeline / literal-help
6. literal-context-menu / literal-which-key-data
7. literal-org-knowledge / literal-org-agenote（路径常量已生效）
8. setq 注入 dashboard 4 回调 → literal-dashboard（最后加载，所有依赖已就绪）
```

**新增模块时**：判断它依赖哪些注入点，把它的 `require` 放在对应注入之后。

## 反模式（禁止）

| 反模式                                     | 原因                                           | 正确做法                                  |
| ------------------------------------------ | ---------------------------------------------- | ----------------------------------------- |
| `(require 'literal-xxx)` 引用本目录模块    | 制造隐式依赖，破坏独立性                       | defvar 注入点 + init.el 注入              |
| 直接调用其他模块函数 `(literal/foo)`       | nil 时 void-function                           | 回调注入点 + `(when fn (funcall fn ...))` |
| 提取公共工具函数到被多模块 require 的文件  | 引入跨模块耦合                                 | 各模块拷贝私有副本                        |
| 模块 `defvar` 覆盖 bootstrap 的 `defconst` | defvar 不覆盖已 bound 值，但若模块先加载会破坏 | 保证 init.el 先加载 bootstrap             |
| `(literal/add-frame-hook fn)` 直接调用     | 注入点为 nil 时 void-function                  | `(when (functionp ...) (funcall ...))`    |

## 模块注入点速查

| 模块                                                                                                     | 注入点                                                                                                             | 注入来源                          | 默认 nil 时行为                                                |
| -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | --------------------------------- | -------------------------------------------------------------- |
| `literal-git`                                                                                            | `literal:executable-git`                                                                                           | bootstrap defconst 自动生效       | 首次用时 `executable-find` 兜底                                |
| `literal-color-scheme`                                                                                   | `literal/add-frame-hook`、`literal/remove-frame-hook`                                                              | init.el setq（来自 frame）        | daemon per-frame 初始化跳过                                    |
| `literal-org-agenote`                                                                                    | `literal:agenote-directory`、`literal:executable-agenote`                                                          | bootstrap defconst 自动生效       | index.json 路径为 nil，命令不可用                              |
| `literal-org-knowledge`                                                                                  | `literal:org-directory`、`literal:org-inbox-file`、`literal:org-knowledge-directory`、`literal:executable-agenote` | bootstrap defconst 自动生效       | 知识库功能不可用                                               |
| `literal-dashboard`                                                                                      | `literal:org-directory`、`literal:org-inbox-file`、`literal/add-frame-hook` + 4 个回调 fn                          | bootstrap defconst + init.el setq | 知识库卡片空、快捷键卡片空、不参与主题刷新、per-frame 接管跳过 |
| `literal-context-menu`、`literal-help`、`literal-modeline`、`literal-tab-line`、`literal-which-key-data` | 无（完全自包含）                                                                                                   | —                                 | —                                                              |

## 验证插件化（修改本目录文件后必做）

```bash
cd lisp/

# 1. 零跨模块 require 检查（应为空）
grep -l "require 'literal-" *.el  # 期望无输出

# 2. 单模块独立加载（每个改造过的模块都应 OK）
for mod in literal-git literal-color-scheme literal-org-agenote \
           literal-org-knowledge literal-dashboard; do
  emacs --batch -L . --eval "
    (condition-case e
        (progn (load \"$mod\" nil t nil)
               (message \"MODLOAD $mod OK\"))
      (error (message \"MODLOAD $mod FAIL: %S\" (cdr e)))))" 2>&1 | grep MODLOAD
done

# 3. 完整 init.el 加载（在上级目录）
cd ..
emacs --batch -L . -L lisp --eval "
  (let ((user-emacs-directory default-directory))
    (load \"init.el\" nil t nil))" 2>&1 | grep -i error
```

## 与上层 AGENTS.md 的边界

本文件只管 `lisp/` 目录的**插件化解耦规范**。以下信息在上层 `general-config/AGENTS.md`（不在此重复）：

- Emacs 配置整体架构、加载阶段、daemon/client 约束
- which-key 维护范式、外部命令加速范式
- Stow 部署模型、验证流程、`.el` 编写检查

模块内部的**设计决策、行为陷阱、与其他模块的功能关系**写到各 `.el` 的 `;;; Commentary:`，不堆进本文件。
