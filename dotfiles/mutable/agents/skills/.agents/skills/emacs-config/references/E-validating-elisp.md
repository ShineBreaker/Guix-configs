# 验证 Elisp:三件套模板与反模式

> 写完 Emacs Lisp 配置后,**第一件事**是调工具验证,不是数括号。
> Emacs 自带 `check-parens` / `byte-compile-file` / ert,都比 LLM 数 `(`/`)`
> 准确一万倍。本章给出每个工具的 emacsclient 模板 + 本地脚本包装。

## 痛点:agent 卡在"数括号"

agent 写 Emacs Lisp 时常见的两类错误范式:

1. **自己数 `(`/`)`** —— LLM 在上下文里维护一个计数器,数到一半就漏。
   这是**根本错误**的范式。Emacs 自己能秒解,准确率 100%,速度 < 100ms。
2. **写完不验证就声称"完成"** —— 编译错误、undefined variable、require 缺失,
   这些都是 byte-compile 一跑就出来的东西,不需要 LLM 读代码"看出来"。

**正确范式**:**写完一段就跑一次工具**,把工具输出贴回上下文,再决定下一步。
这跟"写 Rust 写完跑 `cargo check`"是一回事。

## 三件套(按速度/成本排序)

| 工具                  | 用途                | 速度       | 成本(Emacs 状态) |
| --------------------- | ------------------- | ---------- | ---------------- |
| `check-parens`        | 纯括号平衡,无副作用 | < 100ms    | 纯静态           |
| `byte-compile-file`   | 完整语法检查 + 警告 | 200-500ms  | 生成 .elc        |
| ERT (`ert-run-tests`) | 行为验证            | 100ms-数秒 | 副作用看测试     |

**经验法则**:

- 写完一段大改 → 先 `check-parens`(< 100ms,几乎免费)
- 改完要保证无 warning → `byte-compile-file`
- 改完函数行为变化 → 跑对应 ERT 测试

## emacsclient 模板(三条核心命令)

> **必须用 `emacsclient` 走本机 daemon,禁 `emacs --batch`**
> (除非首次装包无 daemon 的特殊场景)。
> 这是 `emacsclient` skill 的硬约束:**所有 Emacs 操作走 daemon,不快启新进程**。

### 模板 1:check-parens(纯括号平衡,最快)

```sh
emacsclient --eval '
(with-temp-buffer
  (insert-file-contents "/path/to/file.el")
  (check-parens))'
```

返回 `t` = 平衡;信号 `end-of-file` = 不平衡(括号不配对)。

### 模板 2:byte-compile-file(完整语法检查 + 警告)

```sh
emacsclient --eval '
(let ((load-path (cons "/path/to/config" load-path)))
  (byte-compile-file "/path/to/file.el"))'
```

> **警告**: `byte-compile-file` 默认会**生成 .elc 留在原地**。
> agent 写代码时通常不想要这个产物 —— 用本地 `scripts/elisp-compile.sh`
> 包装一次,会自动清理 .elc(见下)。

### 模板 3:ERT 跑测试

```sh
emacsclient --eval '
(progn
  (load "/path/to/test-file.el" nil t)
  (ert-run-tests t))'
```

> **关键**: `emacsclient` 模式下**禁止调 `ert-run-tests-batch-and-exit`**
> —— 那个函数会调 `kill-emacs`,会**杀掉用户正在用的 daemon**。
> 用 `ert-run-tests t` 同步跑测试,返回 `(ert-test-result ...)` 列表;本地 `scripts/run-tests.sh` 实际用 `ert--failed-list` 取失败数(避免解析列表结构)
> 本地 `scripts/run-tests.sh` 把结果翻译成 bash 退出码 0/1。

## 本地脚本(本 skill 自带,位置 `scripts/`)

完整路径:`~/.agents/skills/emacs-config/scripts/`

| 脚本               | 用途                            | 包装的 elisp             |
| ------------------ | ------------------------------- | ------------------------ |
| `elisp-compile.sh` | 单文件 byte-compile + 自动清理  | `byte-compile-file`      |
| `elisp-reload.sh`  | load-file 到运行中的 daemon     | `load-file`              |
| `run-tests.sh`     | ERT 跑测试,返回失败数作为退出码 | `ert-run-tests t`        |
| `clean-up-elc.sh`  | 删 .elc 产物(可独立用)          | 纯文件操作,无 Emacs 调用 |

### 用法

```sh
# 编译单文件
scripts/elisp-compile.sh FILE.el

# 加载到运行中的 Emacs(改完想看效果)
scripts/elisp-reload.sh FILE.el [FILE2.el ...]

# 跑所有 ERT 测试
scripts/run-tests.sh

# 跑指定测试文件(可重复 --test-file)
scripts/run-tests.sh --test-file foo-tests.el --test-file bar-tests.el

# 删 .elc 产物
scripts/clean-up-elc.sh FILE.el
```

### 环境变量覆盖

所有脚本都支持环境变量,默认是 `REPO_ROOT = $(scripts/../..)`,
即 `~/.agents/skills/`。通常你**不会**用这个默认,会显式覆盖:

| 变量                     | 作用                                  | 默认值            |
| ------------------------ | ------------------------------------- | ----------------- |
| `EMACS_CONFIG_LOAD_PATH` | 编译/跑测试时加到 `load-path`         | `REPO_ROOT`       |
| `EMACS_TEST_DIR`         | `run-tests.sh` 找 `*-tests.el` 的目录 | `REPO_ROOT/tests` |
| `EMACSCLIENT_EXECUTABLE` | 替换 `emacsclient` 可执行             | `emacsclient`     |

示例:

```sh
# 编译 user 自己的 config
EMACS_CONFIG_LOAD_PATH=~/.config/emacs \
  scripts/elisp-compile.sh ~/.config/emacs/init.el

# 跑某个项目的测试
EMACS_TEST_DIR=~/myproject/tests \
  EMACS_CONFIG_LOAD_PATH=~/myproject \
  scripts/run-tests.sh

# 自定义 daemon 客户端
EMACSCLIENT_EXECUTABLE=/opt/emacs/bin/emacsclient \
  scripts/elisp-reload.sh init.el
```

## 典型工作流(3 步)

```
1. 改完 .el → scripts/elisp-compile.sh xxx.el
   (自动 byte-compile + 删 .elc,失败时退出码 2)

2. 涉及行为改动 → scripts/run-tests.sh --test-file xxx-tests.el
   (跑 ERT,失败时退出码 1,可被 pre-commit 钩子用)

3. 改完想看效果 → scripts/elisp-reload.sh xxx.el
   (live reload,无副作用)
```

完整链路大概是:

```
改文件 → check-parens(可省) → byte-compile → ERT 测试 → reload 到 daemon
   ↑                                                            ↓
   └──────────────── 改坏了立即 rollback 重新跑 ←────────────────┘
```

## 反模式(避免这些)

| ❌ 反模式                                                  | 后果                                            | ✅ 替换                                 |
| ---------------------------------------------------------- | ----------------------------------------------- | --------------------------------------- |
| agent 自己数 `(`/`)` 括号                                  | 数错率高,浪费时间                               | 调 `check-parens` 或 `elisp-compile.sh` |
| 写完代码不验证就声称完成                                   | 留下语法错误,跑运行时才暴露                     | 写完一段就跑一次工具                    |
| 用 `emacs --batch` 而非 `emacsclient`                      | 慢 + 起新进程 + 违反 `emacsclient` skill 硬约束 | 用 `emacsclient --eval` 或本地脚本      |
| 跳过 byte-compile 只看 check-parens                        | 漏掉 `lexical-binding` / undefined variable     | `check-parens` 是 100ms 防线,但不是全部 |
| 跑测试用 `ert-run-tests-batch-and-exit` (emacsclient 模式) | 杀掉 daemon,用户 Emacs 没了                     | 用 `(ert-run-tests t)`,本地脚本已包装   |
| 编译后留着 .elc 不清理                                     | 污染源目录,git status 噪声                      | 用 `elisp-compile.sh`(自动 clean)       |

## 常见 byte-compile 警告速查

| 警告                                            | 含义                                        | 修复                                                           |
| ----------------------------------------------- | ------------------------------------------- | -------------------------------------------------------------- |
| `lexical-binding: nil` 在前 5 行 = 文件未声明   | 文件首行缺 `;;; -*- lexical-binding: t -*-` | 加 `;;; -*- lexical-binding: t -*-` 到文件首行                 |
| `reference to free variable`                    | 变量未 `require` / 未 `defvar`              | 加 `(require 'xxx)` 或 `(defvar xxx ...)`                      |
| `the function `xxx' is not known to be defined` | 用了未 `require` 的包                       | 加 `(require 'xxx)`                                            |
| `cl.el is deprecated`                           | 用了过时的 `cl` 包                          | 改用 `cl-lib`(Emacs 24+),`cl-incf` / `cl-loop` / `cl-defun` 等 |
| `assignment to free variable`                   | 试图 `setq` 一个未声明的变量                | 加 `defvar` / `defcustom`                                      |
| `unused lexical variable`                       | 写了 let 绑定但没用到                       | 删绑定 或 加 `_` 前缀约定                                      |

> **重要**:`lexical-binding: t` 在前 5 行不等于"启用了 lexical binding"——是
> _声明_。Emacs 27+ 会按 declaration 走,byte-compile 找不到会警告。
> 项目级 .el 文件**必须**显式声明,不要靠外部 `setq` 临时切。

## 决策树:写完一段 elisp 后

```
我刚改完 .el 文件
│
├─ 改动很小(几行 / 一两个 defun)?
│   └─ 直接 scripts/elisp-compile.sh FILE.el(200ms)
│
├─ 改动涉及行为(逻辑分支 / 状态)?
│   └─ 先 byte-compile → 再 scripts/run-tests.sh --test-file xxx-tests.el
│
├─ 改动只动了空白 / 注释?
│   └─ 跳过验证,直接 reload
│
└─ 改完想立即在 daemon 里看效果?
    └─ scripts/elisp-reload.sh FILE.el
```

## 与 `emacsclient` skill 的关系

**两者配套使用**:

- `~/.agents/skills/emacsclient/SKILL.md` —— **规则层**:所有 Emacs 操作走 daemon
- 本文件 —— **实践层**:具体怎么调 daemon 验证 elisp

脚本内部就是 emacsclient 的薄包装,不会起新 Emacs 进程。
当用户没启 daemon 时,脚本会报错并提示"is the daemon running?"。
