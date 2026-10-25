# 跨库依赖三类映射法 — emacs lisp 移植实例

本文档给出三类「上游跨库/跨模块依赖」在本机目标系统中的具体映射法。
**所有例子来自真实案例**:从 `general-config` 移植 `completion.el`(560 行)
到 `literal-config/lisp/literal-completion.el`,走完全部三类映射并通过
Tangle + init load 验证。本文档与 SKILL.md 正文里的决策表互补 —— 正文给
检测模式,这里给真实的对位映射范例。

## 通用判定:何时进入映射?

当你准备把上游的一个完整模块文件搬运到本机,grep 该模块会发现它**引用
了上游其它模块 / 库**而非完全自包含时,启动本流程。**自包含的模块直接
复制即可**,不进映射。

```bash
# 启动检测:在被搬运的模块文件上跑这三个 regex
rg "^[^;]*require '" completion.el      # 跨库 require 列表
rg "<prefix>:[a-z-]+" completion.el     # 私有常量引用
rg "<prefix>/<fn>" completion.el        # 私有函数调用
```

## 三类映射详细说明

### A. 整库 `(require 'xxx)` 的映射

**上游形态**:
```elisp
(require 'lib)   ; lib.el 是 general-config 的 core 工具
```

**问题**: `lib.el` 是上游专用工具包,在本机不存在等价物。即便存在等价物,
本机 SKILL.md/AGENTS.md 可能**禁止跨模块 require**(literal-config 的
`lisp/AGENTS.md`「硬约束 5」明确)。

**三种应对**:
1. **删除 require,函数按需内联**:本模块用到的少数函数 `defun` 进本模块
2. **替换为本机等价 require**:如上游 require 'cl-lib,本机也有 cl-lib,直接改字
3. **降级为软依赖**:`(autoload 'xxx-fn "xxx-pkg")` 加 `(when (fboundp ...) ...)`

**实测选用 1**:completion.el 里真正用 lib 的只有两个函数
(`custom/register-daemon-frame-hook` 不算 require lib 的直接消费),
把它们 defun 内联进 completion.el 头部更直接。

### B. 私有常量 `<prefix>:<const>` 的映射

**上游形态**:
```elisp
(custom/setup-ispell-program)
;; 内部引用 (when (executable-find custom:executable-aspell) ...)
;; 这里的 custom:executable-aspell 是 general-config 在 bootstrap 里 defconst
```

**问题**: 本机的常量命名空间是 `literal:`,而且本模块加载时机早于
bootstrap(可能),不能依赖 bootstrap 已 defconst。

**映射方案 — 「defvar 占位 + bootstrap 自动生效」机制**:
```elisp
;; 模块顶部(必须放在前 20 行内):
(defvar literal:executable-aspell nil
  "由 bootstrap defconst 自动生效。")
(defvar literal:executable-hunspell nil
  "由 bootstrap defconst 自动生效。")

;; 模块内使用点:直接读 variable-value,无需 if 判断
(when literal:executable-aspell ...)   ; nil 时跳过,真值时使用
```

**为什么这样能 work**:literal-config 的 bootstrap 序列在 module require
之前调 `(defconst literal:executable-aspell ...)`。由于 elisp 的变量绑定
是**全局单值**,模块加载时读到的是已 bound 的真值。如果 bootstrap 漏
defconst,模块读到 nil(默认值),触发 `when` 跳过,降级静默。

**核对 regex**:
```bash
# 模块内不应出现 <upstream-prefix>: 引用
rg "<upstream-prefix>:[a-z-]+" lisp/literal-<name>.el  # 应该为空

# 应该全部被 defvar 替换成 literal: 前缀或本模块局部
rg "literal:[a-z-]+" lisp/literal-<name>.el  # 模块顶部 defvar 列表
```

### C. 私有函数调用 `<prefix>/<fn>` 的映射

**上游形态**:
```elisp
(custom/register-daemon-frame-hook #'custom/setup-completion-display)
```

**问题**: `custom/register-daemon-frame-hook` 不是普通 defun,是
general-config 在 lib 里定义的「注册到 `after-make-frame-functions`
+ 立即 daemon 触发」复合函数。本机用 `literal/add-frame-hook`(也是注
入点),但签名不完全一样。

**映射方案 — 「fboundp 检查 + 间接调用」**:
```elisp
;; 本机 frame hook 已在 emacs.org 注入(由 Frame 块加载),名字是 literal/add-frame-hook
;; literal 版比 custom 版更完善(daemon 和 standalone 都跑)

;; 模块顶部 defvar 占位(机制 2:由 init.el 早期注入)
(defvar literal/add-frame-hook nil
  "frame 生命周期注册函数。由 init.el 注入。nil 时跳过。")

;; 使用点
(when (functionp literal/add-frame-hook)
  (funcall literal/add-frame-hook #'literal/setup-completion-display))
```

**两种降级路径**:
- **fboundp 不命中 → 整体降级**:模块只在 main.el 编排块里 require,缺
  失依赖时全部跳过(`(when (require 'xxx nil t) ...)` 包住整个模块逻辑)
- **fboundp 不命中 → 静默跳过**:仅跳过该调用,模块其它部分继续工作
  (本例走这条,因为 frame hook 只是 display 增强,核心补全不依赖)

## 真实案例:general-config completion.el → literal-config literal-completion.el

560 行模块涉及的跨库依赖总览:

| 上游依赖 | 出现次数 | 改造方案 | 行数抽样 |
|---|---|---|---|
| `(require 'lib)` | 1 | 删除(lib 中两函数内联进模块) | 上游第 1 行 |
| `custom:executable-{aspell,hunspell}` | 2 | defvar 注入点 + bootstrap 自动生效 | 上游第 N 行 |
| `custom:ispell-word-list-candidates` 等模块私有 defconst | 6 | 本模块内 defconst 改名 | 散落 |
| `custom/register-daemon-frame-hook` | 1 | `(when (functionp literal/add-frame-hook) (funcall ...))` | 上游 467-470 |
| `custom/diag-report` | 1 | 降级为 `(message ...)` 或删除 | 调试函数 |
| `(lib/random-fn)` | 2 | defun 内联 | 上游文件头 |

**改造后验证清单**:

```bash
# 1. 零跨模块 require
rg "^[^;]*require 'literal-" lisp/*.el  # 必须为空
rg "^[^;]*require '(?!literal-)" lisp/literal-completion.el  # 允许无匹配 exit=1

# 2. 零上游 namespace 残留
rg "custom[/[:]" lisp/literal-completion.el  # 必须为空
rg "\\blib\\b" lisp/literal-completion.el    # 必须为空

# 3. 单模块独立加载(不依赖 main.el 即可 require)
emacs --batch -l lisp/literal-completion.el -f 'message "MODLOAD OK"' 2>&1 | grep MODLOAD

# 4. 完整 init tangle + 加载
emacs --batch --eval "(require 'ob-tangle)" \
  --eval "(let ((org-confirm-babel-evaluate nil)) (org-babel-tangle-file \"emacs.org\"))" \
  -l main.el -f 'message "INITLOAD OK"'
```

## 跨语言对位参考

这套三段映射法是 emacs lisp 移植场景的提炼,**抽象到任何「跨库/跨
模块依赖」借鉴都是同构的**。下表给出其他语言的对应位置:

| 形态 | emacs | Python(自包含模块化) | Rust(use 声明) | Go(import) |
|---|---|---|---|---|
| 整库 require | `(require 'xxx)` | `from pkg.mod import fn` (跨包) | `use crate::other_mod;` | `import "another-pkg"` |
| 私有常量 | `(defconst prefix:key val)` | 模块级 `CONST = ...` | `pub const X` in other mod | 包级 `var Const = ...` |
| 私有函数 | `(defun prefix/fn)` | `pkg.mod.fn()` | `other_mod::fn()` | `other.fn()` |

`lisp/AGENTS.md`「禁止跨模块 require」对应 Rust 里就是 **「模块
internal-only」** 约定（用 `pub(crate)` 而非 `pub`）、对应 Python 里是
**「不要在 `__init__.py` 之外 re-export 别人」**。对位相同,具体检测
regex 不同。

## 反模式(继续往 SKILL.md 段塞的反模式不在此列)

- ❌ **"假装对接得上"**——上游函数调用机械改名 `custom/xxx` → `literal/xxx`,
  但本机根本没对应函数,运行时 `void-function` 才暴露。**必须先
  `fboundp` 软依赖**,再决定要不要内联。
- ❌ **"复制粘贴 defconst 整段"**——上游的常量值可能是上游特定环境
  检测的结果(像 `executable-aspell` 来自 `(executable-find ...)`),
  本机的常量可能早就在 bootstrap 阶段检测过。**不要重复检测,直接
  注入点引用**。
- ❌ **"模块顶 require 一堆"**——本机 lisp/AGENTS.md 禁止,即便
  你打算在新模块里 require 一个新库,也**先评估能不能加进 Guix 配置
  包清单 + bootstrap 自动加载**,再考虑 module 内 require。
