# AGENTS.md - custom-config 工作规范

本文件是本目录内 AI Agent 的唯一操作手册。`emacs.org` 只保存配置、功能语义和设计理由，不再重复 Agent 工作流、功能索引或验收规则。

配置通过 GNU Stow 逐文件链接到 `~/.config/emacs/`。修改仓库源即修改部署源，不要编辑 `~/.config/emacs/` 中的部署路径。

## 1. 架构契约

| 文件                          | 角色                   | 修改规则                            |
| ----------------------------- | ---------------------- | ----------------------------------- |
| `emacs.org`                   | 唯一配置真理源         | 日常功能修改只改这里                |
| `init.el`                     | 固定 bootstrap         | 不改变 tangle 签名和单产物模型      |
| `early-init.el`               | 启动前优化             | 只放必须早于 `main.el` 的行为       |
| `main.el`                     | tangle 产物，gitignore | 禁止手改                            |
| `data/*.el`                   | 外置翻译数据           | 只允许注释和预定变量的字面量 `setq` |
| `scripts/configctl`           | 导航、审计和验收入口   | 维护能力优先扩展这里                |
| `test/custom-config-tests.el` | ERT 契约测试           | 行为修复必须补回归测试              |

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
- 禁止添加 `lisp/` load-path、`(require 'custom-...)` 或 `(provide 'custom-...)`。
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
| 7    | `keys-completion` | 前缀声明、跨域基础键、内置补全栈              | 前述交互命令、frame 生命周期  |
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
| 键位 / 补全               | 功能键随其功能域；跨域基础键 `keybindings`；补全 `completion` | 对应命令必须先定义                   |
| 翻译数据                  | `data/which-key-zh.el`, `data/context-menu-zh.el` | `appearance/i18n-data`               |
| Dashboard                 | `dashboard`                                       | knowledge、help、color-scheme、frame |
| 版本兜底                  | `compatibility`                                   | noweb 展开到真实使用点               |

### 键位归属规则

键位默认跟随其功能实现所在的域（*功能内聚* 原则），不再集中到 `keybindings` 块。`custom/bind` 内部通过 `custom--pending-wk-descs` 暂存 which-key 描述、延迟到 `with-eval-after-load 'which-key` flush；Dashboard 通过扫描 `custom:binding-spec` 生成——二者均与代码物理位置无关。

| 前缀 / 键类              | 归属域 / ID                              | 说明                                       |
| ------------------------ | ---------------------------------------- | ------------------------------------------ |
| `C-c g` Git              | `appearance` / `git-display`             | Git 函数所在域                             |
| `C-c l` `M-g` `C-c f` `C-c z` 代码 | `programming` / `programming-keys` | 含 `code-commands` 函数族                  |
| `C-c e` 编辑变换         | `editing` / `editing-dwim`               | DWIM 与 mc 函数所在域                      |
| `C-c m` 补全             | `keys-completion` / `completion`         | 内置补全栈（Emacs 31）配置同源             |
| `C-x p` 项目             | `projects` / `project-navigation`        | project.el 函数所在域                      |
| `C-c o` `C-c c` Org      | `org-knowledge` / `knowledge`            | Org / Knowledge 函数所在域                 |
| `C-c a` 生活应用         | `system-tools` / `applications` 或应用 `use-package` 所在域 | 每个应用键紧跟其 `use-package` 声明  |
| markdown 等局部键        | 对应 major mode 的 `use-package` 所在域  | `custom/bind-local` 紧跟 mode 声明         |
| 无前缀 IDE 直达键（`C-` / `M-` / `F-`） | `keys-completion` / `global-keys` | 跨多域基础操作，保留为基础键位域          |
| `C-x` `M-s` `C-c w` `C-c h` 跨域键 | `keys-completion` / `keybindings`   | 引用命令跨多个功能域，无单一归属           |
| 14 个前缀声明（`custom/declare-binding-prefix`） | `keys-completion` / `keybindings` | Dashboard 前缀摘要的唯一声明源，必须集中   |

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
- 公开函数和变量使用 `custom/...`，路径与静态常量使用 `custom:...`。
- 私有函数使用 `custom/...--...`；不要添加顺序加载用的 `defvar nil` 注入点。
- 同一符号不得重复 `defun`、`defvar` 或 `defconst`。
- agenote 同步/异步调用统一走 `custom/agenote-call` 和 `custom/agenote-call-async`，每次显式传 domain。
- 全局键使用 `custom/bind`，局部键使用 `custom/bind-local`，前缀声明使用 `custom/declare-binding-prefix`，保持键位、Which-key、帮助和 Dashboard 同源。`custom/bind` 默认跟随其功能域（见第 2 节「键位归属规则」）；只有 14 个前缀声明、`C-x` / `M-s` / `C-c w` / `C-c h` 跨域键和无前缀 IDE 直达键集中在 `keys-completion` 域。
- display 初始化注册到 `custom/add-frame-created-hook`；依赖 client 最终 buffer 的行为注册到 `custom/add-server-ready-hook`。
- 保留第三方包正常的 `require` / `use-package`；禁止的只有历史 `custom-*` feature。

`emacs.org` 正文只记录靠近实现才有价值的功能语义、API 契约、兼容原因和设计取舍。Agent 工作流、索引、验收命令和通用性能规则只写在本文件。

- docstring 只写参数、返回值和可调用行为，不写迁移历史或 commit 编号。
- inline `;;` 只用于局部且非显然的提醒，不复述下一行代码。
- 不恢复整屏分隔线、模块标签或无信息量的说明。

### 4.1 Org 章节编排约定

`emacs.org` 的文档结构遵循以下编排约定，增强可读性与 AI 导航性：

**1. 配置域总览头节**

文件顶部 `* 配置域总览`（CUSTOM_ID: `overview`）是 8 域架构地图，列明每域职责与加载前提。这是新增功能的入口定位点——确认归属域后再改代码。该节只含 org prose 与表格，无源代码块，因此对 tangle 输出零影响。

**2. 组装块用 `#+NAME:` 定址**

每个 noweb 组装块（即包含 `<<ref>>` 的 `#+begin_src emacs-lisp` 块）以 `#+NAME:` 标记，提供 org 间跳转锚和 `configctl map` 定位入口。命名格式为 `<domain>-assembly`（如 `#+NAME: appearance-tab-line-assembly`），全小写连字符，与 noweb-ref 的 `module/section` 风格区分以避免混淆。

**3. 节首 prose 声明契约**

每个 `*`/`**` 节开头的 prose 段落声明：section 的职责、必须已就绪的外部依赖、与跨域设计的根因。`#+attr_org: :width 70` 的 org table 优先于自由文本表述结构关系（如 face 继承链、API 路由表）。

**4. 安全门：tangle 差异零容忍**

编排修改只改 prose、headings 与 `#+NAME:`/CUSTOM_ID，不得改动 `#+begin_src emacs-lisp` 的 body（除非分解为 noweb 片段 + 组装块并以 diff 验证）。验证流程：

1. 基线：`cp main.el /tmp/main.baseline.el && md5sum /tmp/main.baseline.el`
2. 编辑 prose/结构
3. 重新 tangle：`emacs --batch -Q --eval '(progn (require (quote org)) (org-babel-tangle-file "emacs.org"))'`
4. 验证：`diff /tmp/main.baseline.el main.el` 必须为空
5. 结构：`scripts/configctl check` 必须通过

分解 monolith 为 noweb 片段时，组装块的 `<<ref>>` 必须在列 0（无缩进），避免 org 重复缩进导致的空白噪音 diff。

### 4.2 精简公约

配置代码持续做减法，遵循以下公约：

- 只用一次的小函数直接内联到调用方；零转发 wrapper（函数体仅原样调用另一函数）禁止保留，调用方直接用被包装者。
- 内置命令直接绑定，不包「`(interactive)` + `call-interactively`」转发层；跳转类键位直接绑 `xref-*` 等内置命令。
- 同构命令用工厂宏统一生成（如 `custom/git--define-file-command` / `custom/git--define-repo-command`），不逐个手写；宏生成的命令名仍遵守 `custom/` 命名规范。
- 同构渲染 / 数据逻辑提取参数化 helper 收敛（如 `custom/dashboard--render-item-list` 统一列表卡片渲染），重复分支与重复计算合并。
- 优先用内置 `seq` / `subr-x` / `cl-lib` 函数替代手写 lambda（如 `seq-some #'fn`）。
- 删除符号时必须同步清理全部引用点：`data/*.el` 翻译数据、prose、docstring、`custom:pulse-commands` 等列表，不留失效引用。
- 全局绑定的命令必须已定义（或为 keymap）；`binding-spec-global-commands-resolve` ERT 契约强制这一点，新增绑定前先确认命令存在。

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
- `test`：必须是 `0 unexpected`。当前两个历史占位用例会 skipped，Emacs 31 可能因此返回 1；不要为退出码增加 workaround，以测试汇总为准。含 `binding-spec-global-commands-resolve` 绑定完整性契约：`custom:binding-spec` 的每个全局绑定命令必须可解析为已定义命令或 keymap。
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
rg -n "require 'custom-|provide 'custom-|:tangle +lisp/|add-to-list 'load-path" emacs.org
test ! -e lisp
```
