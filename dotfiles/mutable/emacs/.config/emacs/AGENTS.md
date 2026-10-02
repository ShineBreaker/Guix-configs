# AGENTS.md — Emacs 配置规范与工作手册

本文件是本目录下 AI Agent 的唯一操作规范。`emacs.org` 只维护配置逻辑、功能语义与设计取舍，不重复 Agent 工作流与验收规则。

本配置经 GNU Stow 逐文件软链到 `~/.config/emacs/`，**改仓库源码即时更新部署侧**，切勿直接编辑 `~/.config/emacs/` 下的部署文件。

## 1. 架构契约

| 文件 / 脚本         | 角色定位                 | 维护规则                                                                                                                             |
| ------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `emacs.org`         | 唯一配置真理源           | 日常功能配置一律在此修改                                                                                                             |
| `init.el`           | 固定 Bootstrap 引导      | 独立维护，不由 tangle 生成；保持「按需 tangle → 加载 main.el」两步模型稳定                                                           |
| `early-init.el`     | 启动前优化配置           | 只放必须早于 `main.el` 的底层设置（禁 package.el、GC 阈值、Frame 几何、TTY）                                                         |
| `main.el`           | Tangle 产物（gitignore） | **禁止手动编辑**，由 `emacs.org` 编译生成                                                                                            |
| `data/*.el`         | 静态翻译与数据           | 仅允许字面量 `setq` 与注释                                                                                                           |
| `scripts/configctl` | 代码块操纵工具           | 面向 Agent 的提取/定位/拼合/静态检查入口（用法见 [docs/scripts/emacs-configctl.md](../../../../../docs/scripts/emacs-configctl.md)） |

启动调用链：`emacs → init.el → （仅当 emacs.org 比 main.el 新时）tangle → main.el → (load main.el)`。

> **`init.el` 的 Stow 陷阱**：`emacs.org` 经 Stow 软链到仓库源，org 全局 `:tangle main.el` 的相对路径按 org 的 **truename**（仓库源目录）解析而非部署目录，`org-babel-tangle-file` 的 TARGET-FILE 参数因每块显式 `:tangle` 而被忽略——结果是 tangle 产物落在仓库源、部署侧 `main.el` 永远 stale。`init.el` 末尾因此显式做一次 `copy-file` 同步。改动这段时别把它当冗余代码删掉。

**核心硬约束**：只生成唯一的 `main.el`，严禁 `:tangle lisp/...`，禁止引入 `lisp/` 目录到 `load-path`，禁止 `(require 'custom-...)` / `(provide 'custom-...)`；`main.el` 尾部仅保留 `(provide 'main)`。

## 2. 导航与配置域

改配置前不必通读 `emacs.org`，用 `scripts/configctl` 定位（`map` 列全部 `CUSTOM_ID`、`show <ID>` 取子树、`locate <ID|REF>` 定位行号）。五个子命令的契约（`map` / `show` / `locate` / `tangle` / `check`）见 [docs/scripts/emacs-configctl.md](../../../../../docs/scripts/emacs-configctl.md)。

`emacs.org` 的文档编排顺序即求值顺序——前面的域定义变量与函数，后面的域才能调用，8 个域固定：

| 序号 | 配置域 / ID       | 主要职责                                                   | 前置依赖                  |
| ---- | ----------------- | ---------------------------------------------------------- | ------------------------- |
| 1    | `startup`         | 路径、外部进程、Frame 行为、键位基础原语                   | 无                        |
| 2    | `appearance`      | 帮助系统、Modeline、Tab-line、Git 状态、主题与字体         | `startup` 的 Frame 原语   |
| 3    | `editing`         | 通用编辑增强、DWIM 变换、内置终端                          | `git-display`             |
| 4    | `programming`     | Tree-sitter、Eglot (LSP)、Flymake、代码格式化与各语言 Mode | `bootstrap`、`appearance` |
| 5    | `projects`        | Project.el、目录树与项目导航                               | `terminal`、`git-display` |
| 6    | `org-knowledge`   | Org Mode、Roam 笔记、Agenote 知识库                        | `bootstrap`               |
| 7    | `keys-completion` | 顶层前缀声明、跨域基础键、内置补全栈 (Vertico/Consult)     | 交互命令与 Frame 体系     |
| 8    | `system-tools`    | Daemon 预热、Dashboard 欢迎屏、版本兼容兜底                | 前述全部模块              |

**键位归属（功能内聚）**：功能专属按键跟随其实现所在域就近绑定，不集中塞进全局按键块；`custom/bind` 内部用 `custom--pending-wk-descs` 暂存 Which-key 描述，等 Which-key 就绪后统一刷新。全局只保留 14 个顶层前缀声明（`custom/declare-binding-group`）、跨域基础键（`C-x` / `M-s` / `C-c w` 等）与 IDE 直达键，落在 `keys-completion` 域。

## 3. 编码规范与设计公约

### Noweb 规则

绝大多数代码块按文档顺序直接 tangle 进 `main.el`。Noweb 只用于两类场景：**版本兼容 Shim（前向引用）**——定义在 `compatibility` 域尾部，由靠前的使用点通过顶格 `<<emacs31/...>>` 展开；**`#+name` 纯文本数据块**（如 Capture 模板）——声明 `:tangle no` 并紧跟引用者。

### 精简与防御边界

- **消除冗余 Wrapper**：只用一次的辅助函数直接内联，禁止仅做原样转发的包装函数。
- **守卫边界（`fboundp` / `boundp`）**：仅用于**延迟加载的第三方包**与**跨构建变量**；同一 `main.el` 内部的函数互调不加守卫（加载顺序已保障可用）。
- **进程与异步安全**：存活检查（`frame-live-p` / `buffer-live-p`）仅在异步回调（Timer、D-Bus、Process Sentinel）中保留，遍历 `frame-list` / `window-list` 时不逐层检查。
- **异常捕获**：`condition-case` 仅包裹文件 I/O、外部子进程或 D-Bus 调用；对返回 nil 的查询型 API（如 `project-current`、`treesit-ready-p`）不加包裹。

### 可读性与抽象边界（目标读者：Emacs Lisp 入门者）

代码的第一属性是**可读、可学、可改**——写给认识 `defun`/`setq`/`let`/`dolist`/`use-package`、刚接触反引号的读者。省几行的高阶写法若提高阅读门槛，一律不用：

- **不为少量重复引入宏**：2~3 处同构命令直接平铺为 `defun`（可 `C-h f` 跳转、错误栈有名字）；禁止 `intern`/`format` 动态拼函数名或变量名。
- **数据表可留，派生链要平铺**：plist/alist 单一事实源（如 `custom:language-capabilities`）保留；派生逻辑用 `dolist` + 具名函数 + `push`/`nreverse`，禁止多层 `seq-*`/lambda 嵌套写成单个表达式。
- **高阶解构降级**：`cl-loop` 解构、`pcase-let` 反引号解构、`cl-flet` 局部函数、`cl-remove-if-not` 等混用方言，一律降级为 `dolist` + 具名函数 + `car`/`cdr`；集合操作统一 `seq-*`。
- **必要技巧必须就地解释**：`cl-letf`、`advice-add`、buffer 差集、`setf (alist-get ...)` 等无法平铺的技巧保留时，就近补 3~8 行「为什么需要它」与取舍说明。
- **教读者自助查询**：涉及新机制时在 org 文字里给出 `C-h k` / `C-h f` / `C-h v` / `M-x customize-group` / `(info ...)` 路径；文字克制，不写长篇教程。
- **命名约定**：`custom:` = 配置变量，`custom/` = 命令与函数，`custom--` 前缀与 `custom/模块--名称` = 内部实现细节。

### 文学编程编排（反模式禁令）

- **禁止解释与代码割裂**：严禁把大量解释堆在章节顶部、下方只放一个数百行的超长源码块。
- **就近成对拆分（Literate Pairing）**：按功能颗粒度拆成 `*** 子节名称`，每节「一段针对性的机制解释/设计取舍 + 紧跟对应代码块」，控制实现块在 20~80 行量级。
- **代码块内禁止残留大量行注释**：源码块内只留文件头声明与函数/变量 Docstring；原理解释、踩坑经验、API 取舍一律移到块上方的 org 正文。

## 4. 性能硬约束

1. **优先级**：Client 首次打开与交互延迟 > Daemon 长时间运行稳定性与内存 > Daemon 启动时间。
2. **热路径禁令**：禁止在 Mode-line、Tab-line、Redisplay、Post-command 等高频回调中执行文件 I/O、同步子进程或重复 `require`。
3. **缓存与失效**：昂贵计算结果用 Buffer-local 或 Frame-local 缓存，并在 Save、Revert、Major-mode 切换时精准失效。
4. **异步 I/O**：UI 交互绝不同步等待外部 CLI，统一用 `make-process` 异步刷新与展示。

## 5. 标准工作流

1. **定位与提取**：`scripts/configctl map` 查目标 ID，`show <ID>` 取子树，`locate <ID>` 看行号区间。
2. **就地修改**：编辑对应功能子树；除非改动跨域导出的公共 API，否则不影响其他域。
3. **同步 manifest**：引入新包时在 `source/config.org` 的 `emacs-packages` 块（`(packages (specifications->manifest '(…)))`，由 `emacs-services` 块同时喂给 home-emacs 与 neomacs 两个服务）登记包名，先用 `guix package -A '^emacs-<name>$'` 确认包存在。包本体由 Guix profile 提供，`use-package` 不要写 `:ensure`。
4. **编译与验收**：跑第 6 节的静态检查与加载验证；改了包清单再 `blue --dry-run home` 校验配置有效性，`blue home` 应用部署，最后 `herd restart emacs-daemon`（Daemon 启动时按需重新 tangle）。

## 6. 验收标准

### 6.1 静态检查

```bash
scripts/configctl check     # 结构 + 双源键门禁 + data 键唯一性 + 隔离 tangle + 括号/重复定义
git diff --check
```

`check` 在 `mktemp` 的隔离目录里 tangle 一份副本，不写真实 `main.el`。

### 6.2 加载验证（隔离环境）

```bash
scripts/configctl tangle
emacs --batch -q -l main.el
```

> 用 `-q` 而非 `-Q`：`-Q` 跳过 `site-start`，Guix profile 的 `guix-emacs.el` autoloads（如 `telega-prefix-map`）不注册，`custom/bind` 会报 void-variable 假阳性。`load` 遇 Error 直接中断后续配置，必须确认 batch-load 零 Error 且 `custom:binding-spec` 条目数符合预期。

### 6.3 按键与包清单核对

- 功能键必须写 `<f12>` 形式而非 `"F12"`（后者会被 `key-parse` 拆散）。
- `C-S-*`、`C-<tab>` 在部分终端会退化，高频操作须另给 `C-c` 前缀备用键。
- manifest 里每个 `emacs-*` 包在 `emacs.org` 都有实际引用（防无用包），`emacs.org` 引用的每个第三方包都在 manifest 登记（防依赖缺失）。

### 6.4 Tmux TTY 真机验收

Daemon、按键或包改动做端到端实测：

```bash
tmux new-session -d -s emacsprobe -x 180 -y 45
tmux send-keys -t emacsprobe 'emacsclient -t' Enter
sleep 3
tmux capture-pane -t emacsprobe -p | tail
tmux kill-session -t emacsprobe
```

### 6.5 重构等价性（纯可读性改动）

平铺、拆分、抽象降级不改变行为，必须给出**等价性证据**，禁止「看起来一样」式判断：

- 从 `git show HEAD:./emacs.org` 与改动后版本各提取真实函数体，在 batch Emacs 中对典型输入（含边界值）对比返回值与副作用输出；渲染类函数还要对比文本属性、overlay 位置与 point。
- 仅改写法时，`(custom/bind ` 真实调用数与 `custom:binding-spec` 条目数须与改动前一致：`emacs --batch -q -l main.el --eval '(message "%d" (length custom:binding-spec))'`。
- 多表达式验证脚本写成 `.el` 用 `-l` 加载：`--eval` 只读第一个完整 sexp，其余被静默忽略（rc=0 的假通过）。
