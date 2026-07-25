# AGENTS.md - literal-config 工作规范

本文件是本目录内 AI Agent 的唯一操作手册。`emacs.org` 只保存配置、功能语义和设计理由，不再重复 Agent 工作流、功能索引或验收规则。

配置通过 GNU Stow 逐文件链接到 `~/.config/emacs/`。修改仓库源即修改部署源，不要编辑 `~/.config/emacs/` 中的部署路径。

## 1. 架构契约

| 文件                           | 角色                   | 修改规则                            |
| ------------------------------ | ---------------------- | ----------------------------------- |
| `emacs.org`                    | 唯一配置真理源         | 日常功能修改只改这里                |
| `init.el`                      | 固定 bootstrap         | 不改变 tangle 签名和单产物模型      |
| `early-init.el`                | 启动前优化             | 只放必须早于 `main.el` 的行为       |
| `main.el`                      | tangle 产物，gitignore | 禁止手改                            |
| `data/*.el`                    | 外置翻译数据           | 只允许注释和预定变量的字面量 `setq` |
| `scripts/configctl`            | 导航、审计和验收入口   | 维护能力优先扩展这里                |
| `test/literal-config-tests.el` | ERT 契约测试           | 行为修复必须补回归测试              |

启动链：

```text
emacs -> init.el -> 按需 tangle emacs.org -> main.el -> load main.el
```

以下契约不可改变：

```elisp
(org-babel-tangle-file org-file main-file "emacs-lisp")
```

```org
#+PROPERTY: header-args:emacs-lisp :tangle main.el :lexical yes :mkdirp yes :noweb tangle
```

硬约束：

- 只有一个生成物 `main.el`，禁止 `:tangle lisp/...`。
- 禁止添加 `lisp/` load-path、`(require 'literal-...)` 或 `(provide 'literal-...)`。
- 文件末尾只保留 `(provide 'main)`。
- 不添加全局 `:comments link`，避免 noweb 注释膨胀。
- 新 Emacs 包必须同步根仓库 `source/config.org` 的 `home-emacs-packages`。
- 不把本文件的 Agent 指引复制回 `emacs.org`。

## 2. 导航与加载顺序

不要先阅读全文。先用动态索引定位：

```bash
scripts/configctl map
scripts/configctl show dashboard
scripts/configctl find 'eglot|flymake'
```

| 命令           | 用途                                           |
| -------------- | ---------------------------------------------- |
| `map`          | 列出稳定 `CUSTOM_ID`、行号、代码量和 noweb ref |
| `show ID`      | 只输出一个功能子树；模糊匹配必须唯一           |
| `find REGEXP`  | 输出匹配行及所属功能 ID                        |
| `check`        | 检查域顺序、ID、noweb、tangle、括号和重复定义  |
| `load`         | `check` 后在 `/tmp` 隔离 runtime 中 batch load |
| `test`         | 加载隔离 runtime 后运行 ERT                    |
| `check-strict` | 额外强制 domain 与私有 API 审计                |

`emacs.org` 的文档顺序就是求值顺序，8 个配置域固定为：

| 顺序 | 配置域 / ID       | 主要职责                                      | 必须已就绪                    |
| ---- | ----------------- | --------------------------------------------- | ----------------------------- |
| 1    | `startup`         | 路径、进程、frame、键位原语、基础行为         | 无                            |
| 2    | `appearance`      | 帮助、modeline、tab-line、Git、主题           | `startup` 的 frame 原语       |
| 3    | `editing`         | 通用编辑、DWIM、终端                          | `git-display`                 |
| 4    | `programming`     | Tree-sitter、Eglot、Flymake、格式化、语言模式 | `bootstrap`、`appearance`     |
| 5    | `projects`        | project.el、目录与项目导航                    | `terminal`、`git-display`     |
| 6    | `org-knowledge`   | Org、Roam、Knowledge、agenote                 | `bootstrap`、`process-helper` |
| 7    | `keys-completion` | 全局键、前缀键、Vertico、Corfu                | 前述交互命令、frame 生命周期  |
| 8    | `system-tools`    | daemon 预热、Dashboard、版本兼容              | 前述全部；Dashboard 必须最后  |

```text
startup -> appearance -> editing -> programming -> projects
        -> org-knowledge -> keys-completion -> system-tools/dashboard
```

常用功能路由：

| 修改目标                  | 首选 ID / 文件                                    | 直接依赖                             |
| ------------------------- | ------------------------------------------------- | ------------------------------------ |
| 路径与外部命令            | `bootstrap`                                       | 无                                   |
| agenote 进程接口          | `process-helper`                                  | `bootstrap`                          |
| 新 frame / client 行为    | `frame`                                           | `bootstrap`                          |
| 主题、字体、深浅色        | `theme-fonts`, `color-scheme`                     | `frame`                              |
| Modeline / Tab-line       | `modeline`, `tab-line`                            | `theme-fonts`                        |
| Git / display-buffer      | `git-display`, `window-layout`                    | `frame`                              |
| 编辑命令 / 终端           | `editing-dwim`, `terminal`                        | `git-display`                        |
| LSP / 诊断 / 格式化       | `programming-tools`                               | `bootstrap`, `appearance`            |
| 项目导航                  | `project-navigation`                              | `terminal`, `git-display`            |
| Org / Knowledge / agenote | `org-core`, `knowledge`                           | `bootstrap`, `process-helper`        |
| 键位 / 补全               | `keybindings`, `completion`                       | 对应命令必须先定义                   |
| 翻译数据                  | `data/which-key-zh.el`, `data/context-menu-zh.el` | `appearance/i18n-data`               |
| Dashboard                 | `dashboard`                                       | knowledge、help、color-scheme、frame |
| 版本兜底                  | `compatibility`                                   | noweb 展开到真实使用点               |

## 3. 标准修改流程

1. `scripts/configctl map` 找稳定 ID。
2. `scripts/configctl show <ID>` 只读目标子树。
3. 用 `scripts/configctl find '<symbol|package>'` 检查跨域调用。
4. 修改一个功能子树；只有跨域 API 变化时才调整其他域。
5. 新增包时同步 `source/config.org`；仅重排或精简现有代码不改包清单。
6. 运行本文件第 7 节的验收命令。

标题可以改，稳定 `CUSTOM_ID` 不可改。定义方必须在调用方之前。

## 4. Noweb、命名与文档

小模块可以使用一个普通 source block。大模块按子功能拆成命名片段，并在章节末尾用唯一组装块确定最终加载顺序：

```org
#+begin_src emacs-lisp :noweb-ref module/data :tangle no
...
#+end_src

#+begin_src emacs-lisp
<<module/data>>
<<module/render>>
<<module/hooks>>
#+end_src
```

规则：

- ref 使用英文 `module/section` 或既有 `module-section` 风格。
- 每个 ref 只定义一次、只组装一次；片段必须 `:tangle no`。
- 共享实现放在 `helpers/...`，并在所有调用方之前组装。
- noweb 只负责组织与顺序，不模拟 `require`。
- 公开函数和变量使用 `literal/...`，路径与静态常量使用 `literal:...`。
- 私有函数使用 `literal/...--...`；不要添加顺序加载用的 `defvar nil` 注入点。
- 同一符号不得重复 `defun`、`defvar` 或 `defconst`。
- agenote 同步/异步调用统一走 `literal/agenote-call` 和 `literal/agenote-call-async`，每次显式传 domain。
- 全局键使用 `literal/bind`，局部键使用 `literal/bind-local`，前缀声明使用 `literal/declare-binding-prefix`，保持键位、Which-key、帮助和 Dashboard 同源。
- display 初始化注册到 `literal/add-frame-created-hook`；依赖 client 最终 buffer 的行为注册到 `literal/add-server-ready-hook`。
- 保留第三方包正常的 `require` / `use-package`；禁止的只有历史 `literal-*` feature。

`emacs.org` 正文只记录靠近实现才有价值的功能语义、API 契约、兼容原因和设计取舍。Agent 工作流、索引、验收命令和通用性能规则只写在本文件。

- docstring 只写参数、返回值和可调用行为，不写迁移历史或 commit 编号。
- inline `;;` 只用于局部且非显然的提醒，不复述下一行代码。
- 不恢复整屏分隔线、模块标签或无信息量的说明。

## 5. 性能硬约束

性能优先级固定为：

1. `emacsclient` 首次打开和高频交互延迟。
2. daemon 长时间运行时的稳定性、内存与持续响应。
3. daemon 自身启动时间。

daemon 启动慢可以接受，但不能把工作推迟到首个 client 或高频热路径。

### 5.1 加载与预热

- 首个 client 必需的纯 Lisp feature、主题、D-Bus 注册和只读缓存，应在 daemon 对外服务前同步完成。
- daemon 预热白名单只放经过冷 `require` 测量的高频交互 feature；不得因此启动 LSP、聊天、邮件、PDF、网络连接或长期子进程。
- 不使用 `:defer 0.5`、任意 idle timer 或“稍后再加载”掩盖首用成本。
- `:defer t` 必须有真实触发入口，如 `:commands`、`:mode`、`:hook` 或 autoload。
- client 高频功能若没有可靠触发入口，使用 `:demand t` 或纳入 daemon 预热。
- 不启用会把编译警告或 native compilation 成本转移到首个 client 的实验性方案。

### 5.2 热路径

- mode-line、tab-line、redisplay、window-size、post-command、focus-change 等热路径中禁止文件 IO、同步子进程、递归目录扫描、完整 buffer 扫描或重复 `require`。
- 昂贵结果使用 buffer-local 或 frame-local 缓存，并在 save、revert、major-mode、project、theme 等真实状态变化点失效。
- 全局缓存必须有明确上限；长驻 daemon 不允许无界 hash table、buffer、timer 或 process 累积。
- 大文件必须在扫描行数、fontification 或启用高成本显示功能之前走快速降级路径。

### 5.3 外部 IO 与 Dashboard

- 交互 UI 不等待外部 CLI。使用 `make-process`、缓存和 stale-while-revalidate；旧数据可以立即展示，后台刷新完成后再增加 generation 并重绘。
- process 成功、失败、signal 和同步启动异常都必须清理 stdout/stderr buffer、timer 和全局 process 引用。
- Dashboard buffer、owner、rendered width/generation 和 tab 列表必须 per-frame 隔离；数据 generation 可以全局共享。删除 frame 时同步释放所有权和 buffer。
- `server-after-make-frame-hook` 早于最终文件切换。Dashboard 只能在下一事件循环判定 placeholder，绝不能覆盖 `emacsclient FILE`、with-editor 或已分窗的 client。
- 连续 resize/theme/data 变化必须合并刷新，避免每个事件立即完整重渲染。

### 5.4 正确性边界

- 不为 daemon 启动速度清空 `file-name-handler-alist`、关闭 bidi，或破坏 TRAMP、压缩文件、RTL、GUI/TTY 混合 frame。
- 外部命令只保存命令名；通过当前 `exec-path` / `executable-find` 解析，不缓存 `/gnu/store/...` 绝对路径，避免 daemon 跨 Guix generation 使用旧程序。
- GC 启动期可提高阈值；启动完成后由 GCMH 接管，不额外写入相互竞争的 GC timer。
- 自动保存只处理正常访问、可写、已修改的本地文件；不保存远程、间接、只读、内部或仅伪造 `buffer-file-name` 的临时 buffer。
- 性能优化不能以删除现有信息密度、键位功能或多 frame 隔离为代价。

### 5.5 基准安全

- 先记录基线，再修改，再使用相同 workload 复测；不提交没有测量依据的复杂优化。
- 基准临时 buffer 禁止绑定仓库真实路径。使用 `/tmp`、保持 `buffer-file-truename=nil`，或 stub `project-current` / 路径函数。
- 禁止在加载用户配置的 benchmark 中把真实 `emacs.org` 赋给 `buffer-file-name`；失焦保存等全局 hook 可能把样本写回源文件。
- daemon 基准使用唯一 socket 名，短请求、短迭代，并用 `unwind-protect` 或 shell `trap` 清理自建 daemon/client。
- 报告 GUI frame、冷 require、mode-line 等数据时说明环境，非同环境结果不得宣称为严格 A/B。

## 6. 兼容性、包与部署

- Emacs 版本兜底集中在 `compatibility`。shim 用命名 noweb ref 展开到真实加载点，并在正文记录根因与移除条件。
- 只有实际功能故障才添加兼容代码。Emacs 31 预发布的 `Missing 'lexical-binding' cookie` 警告不投入专门修复，也不添加 warning 抑制层。
- Arei/Yasnippet 从 `.el` 源加载是旧 Guix `.elc` 在 Emacs 31 下的实际行为故障，与上述警告不同；上游或 Guix 重编译后应删除 shim。
- 新包必须加入根仓库 `source/config.org` 的 `home-emacs-packages` 并运行 `scripts/configctl audit-packages`。
- 本目录是 mutable Stow 源，普通配置修改不需要 `blue home`。运行中的 daemon 仍持有旧内存配置，验收完成后提醒用户执行 `herd restart emacs-daemon`。
- 不运行 `blue rebuild`、`guix system reconfigure`，也不直接编辑 `main.el`。

## 7. 验收标准

每次修改至少执行：

```bash
scripts/configctl check
scripts/configctl load
scripts/configctl test
scripts/configctl check-strict
git diff --check
git status --short
```

审计命令：

```bash
scripts/configctl audit-keys
scripts/configctl audit-private-api
scripts/configctl audit-agenote-domain
scripts/configctl audit-packages
```

验收要求：

- `check`：8 域顺序、header、ID、noweb、单产物、括号和顶层定义全部通过。
- `load`：隔离 runtime 完整加载，除明确的 Emacs 31/第三方 warning 外无 Lisp error。
- `test`：必须是 `0 unexpected`。当前两个历史占位用例会 skipped，Emacs 31 可能因此返回 1；不要为退出码增加 workaround，以测试汇总为准。
- `check-strict` 和四项 audit：零违规、零 unknown package。
- `git diff --check`：无空白错误；`git status` 只包含本任务文件和已知用户改动。

涉及 daemon、frame、Dashboard、主题或 client 启动时，还要用唯一命名 daemon 验证：

- 预热 feature、主题、D-Bus、缓存和兼容状态在 server ready 前已就绪。
- 两个 client frame 的 Dashboard/tab 状态互不污染。
- `emacsclient FILE` 保持文件 buffer，不被 Dashboard 覆盖。
- GUI 与 TTY 分支按 frame 生效。
- 测试 daemon、socket、process buffer 和临时文件全部清理。

额外静态检查：

```bash
rg -n "require 'literal-|provide 'literal-|:tangle +lisp/|add-to-list 'load-path" emacs.org
test ! -e lisp
```
