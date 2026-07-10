# 0001 — Self-contained `lisp/*.el` modules use `defvar` injection points instead of cross-`require`

`literal-color-scheme.el` / `literal-dashboard.el` 等模块自包含,不 `require` 其他 `literal-*` 模块;跨模块函数依赖通过「模块头部 `defvar` 占位变量 + 加载序列后方 `setq` 注入函数」解决,利用 Emacs Lisp 双命名空间下 `defun` 与同名 `defvar` 共存的特性。

**Status**: superseded by [0002 — direct `require` for sibling modules](0002-direct-require-for-sibling-modules.md) (2026-07)

**Considered Options**:

1. **`require` 链** — color-scheme 直接 `require 'literal-frame`,dashboard 直接 `require 'literal-knowledge` 等。
   - 缺点:形成 require 环或加载顺序耦合;byte-compile 时若目标模块未先编译会失败;反向耦合(轻模块被迫依赖重模块)。
2. **全局变量持有函数** — 模块加载时直接把函数赋值到全局变量(如 `*literal-frame-hooks*`)。
   - 缺点:失去命名空间隔离;变量名容易冲突;无 defvar 文档字符串承载。
3. **advice-add** — 用 advice 在目标函数上挂回调。
   - 缺点:advice 修改被建议函数本体,语义模糊,debug 时栈难以跟踪;与本项目的「注入回调」语义不直接对应。

**Consequences**:

- 每个自包含模块头部必须为每个跨模块回调声明对应 `defvar`(目前 color-scheme / dashboard 各 4–5 个);新读者扫模块头就能看清依赖图。
- 加载序列的责任落在 `emacs.org` § 启动与基础设施(加载 frame)与 § 系统工具(加载 dashboard)两处,先后顺序敏感且需在头部「启动顺序与模块依赖速查」表中明示。
- Lisp-2 同名共存特性意味着 `literal/add-frame-hook` 既是被调函数(由 frame 模块 `defun`)又是 color-scheme/dashboard 头部声明的占位变量,初次阅读易混淆——通过 `../CONTEXT.md` 词条 + 模块头部注释同时约束。
- 后续若新增自包含模块,沿用本模式即可,无需改基础设施域。
