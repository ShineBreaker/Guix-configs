# AGENTS.md - literal-config 工作规范

本文件是本目录内 AI Agent 的唯一操作手册。配置通过 GNU Stow 逐文件链接到
`~/.config/emacs/`;改仓库源即生效,不要编辑部署位置。

## 1. 架构契约

| 文件                | 角色                  | 修改规则                         |
| ------------------- | --------------------- | -------------------------------- |
| `emacs.org`         | 唯一配置真理源        | 日常功能修改只改这里             |
| `init.el`           | 固定 bootstrap        | 不得改变 tangle 签名和单产物模型 |
| `early-init.el`     | 启动前优化            | 仅处理必须早于 `main.el` 的行为  |
| `main.el`           | tangle 产物,gitignore | 禁止手改                         |
| `data/*.el`         | 外置翻译表            | 只允许注释和预定变量的字面量 `setq` |
| `scripts/configctl` | Agent 导航与验收入口  | 新增维护能力优先扩展这里         |

启动链:

```text
emacs -> init.el -> 按需 tangle emacs.org -> main.el -> load main.el
```

`init.el` 的以下契约不可改:

```elisp
(org-babel-tangle-file org-file main-file "emacs-lisp")
```

全局 Org header 不可改成多文件输出:

```org
#+PROPERTY: header-args:emacs-lisp :tangle main.el :lexical yes :mkdirp yes :noweb tangle
```

硬约束:

- 只有一个生成物 `main.el`;禁止 `:tangle lisp/...`。
- 禁止 `(require 'literal-...)` / `(provide 'literal-...)`;末尾仅保留 `(provide 'main)`。
- 禁止添加 `lisp/` load-path;逻辑模块靠文档顺序加载。
- 不添加全局 `:comments link`;noweb 片段会让产物注释膨胀。
- 新 Emacs 包必须同步 Guix-configs 根仓库 `source/config.org` 的 `home-emacs-packages`。

## 2. Agent 快速工作流

不要先阅读全文。所有任务从动态索引开始:

```bash
scripts/configctl map
scripts/configctl show dashboard
scripts/configctl find 'eglot|flycheck'
```

命令说明:

| 命令          | 用途                                                         |
| ------------- | ------------------------------------------------------------ |
| `map`         | 列出稳定功能 ID、行号、代码量和 noweb ref                    |
| `show ID`     | 只输出一个 `CUSTOM_ID` 子树;标题模糊匹配必须唯一             |
| `find REGEXP` | 输出匹配行及其所属功能 ID                                    |
| `check`       | 检查域顺序、ID、noweb 图、旧架构残留、tangle、括号和重复定义 |
| `load`        | 先 `check`,再在 `/tmp` 隔离运行时 batch load                 |

标准步骤:

1. `scripts/configctl map` 找功能 ID。
2. `scripts/configctl show <ID>` 只读目标子树。
3. 必要时 `scripts/configctl find '<symbol|package>'` 查看跨域调用。
4. 修改一个功能子树;跨域 API 变化才更新顶部依赖表。
5. 运行 `scripts/configctl check` 和 `scripts/configctl load`。

## 3. 文档与加载顺序

`emacs.org` 的文档顺序就是求值顺序。8 个配置域固定为:

1. `startup` - 启动与基础设施
2. `appearance` - 界面与外观
3. `editing` - 编辑与文本
4. `programming` - 编程与开发
5. `projects` - 项目与导航
6. `org-knowledge` - Org 与知识库
7. `keys-completion` - 键位与补全
8. `system-tools` - 系统工具与实验性

主要跨域依赖:

```text
startup -> appearance -> editing -> programming -> projects
        -> org-knowledge -> keys-completion -> system-tools/dashboard
```

规则:

- 定义方必须在调用方之前。
- Dashboard 固定在最后一个配置域,因为它消费 frame/help/knowledge/color-scheme。
- Emacs 版本兜底 shim 集中在 `compatibility` 域(Ghostel/with-editor、which-key 中文宽度、arei `.elc`、vertico-buffer 形态降级)。这些是**生效中的版本兜底**,不是待完成功能——代码已生效,移除条件在上游修复。shim 用命名 noweb ref 展开到真实使用点。
- 功能标题可改,稳定 `CUSTOM_ID` 不改;工具和其他 Agent 依赖 ID 定位。

## 4. Noweb 组织

小模块不超过约 150 行时可使用一个普通 source block。大模块按子功能拆片段,
在功能章节末尾用唯一组装块决定写入顺序。

片段:

```org
*** 数据层
#+begin_src emacs-lisp :noweb-ref module/data :tangle no
...
#+end_src
```

组装:

```org
#+begin_src emacs-lisp
<<module/data>>
<<module/render>>
<<module/hooks>>
#+end_src
```

约束:

- ref 只用英文 `module/section` 或既有的 `module-section` 风格。
- 每个 ref 只定义一次、只组装一次;`configctl check` 强制验证。
- 片段必须 `:tangle no`;遗漏组装会被检查拦截。
- 共享实现放 `helpers/...`,在所有使用方之前组装。
- 不用 noweb 模拟 `require`;它只负责可读性和最终顺序。

## 5. 命名与代码规则

- 公开函数/变量使用 `literal/...`;路径和静态配置常量沿用 `literal:...`。
- 私有函数使用 `literal/...--...`;不要为顺序加载模块添加 `defvar nil` 注入点。
- 同一符号不得重复 `defun` / `defvar` / `defconst`;`configctl check` 会报错。
- 共享同步进程调用统一使用 `literal/call-process`。
- 全局键位优先使用 `literal/set-key`,以同步 which-key 中文描述。
- display-dependent 行为通过 `literal/add-frame-hook` 注册,覆盖 daemon/client。
- 保留第三方包的正常 `require` / `use-package`;禁止的只有历史 `literal-*` feature。
- **约束与决策写 Org 正文,不写 inline `;;` 注释**。约束、兼容性、非显然决策、跨域依赖、被否决的替代方案,一律写到代码块外的 Org 正文,优先用表格 / 列表 / `[[#custom-id]]` 链接 / 脚注 / `#+begin_example` 呈现。
- docstring 只保留 API 契约(参数 / 返回值 / 可调用行为),不写迁移历史或 commit 编号。
- inline `;;` 注释只允许用于无法用 docstring 表达、且不值得单独 Org 说明的局部提醒(如 byte-compile 前向声明、下一行的非显然键位占用原因);仅复述下一行代码的琐碎注释和「包名 — 功能」式标签一律删除。
- 不要恢复整屏分隔线或已迁移模块头。

## 6. 功能路由

| 任务                      | 功能 ID                            |
| ------------------------- | ---------------------------------- |
| 路径、命令缓存            | `bootstrap`                        |
| 同步子进程                | `process-helper`                   |
| daemon/client frame       | `frame`                            |
| 主题与字体                | `theme-fonts`, `color-scheme`      |
| Modeline / Tab-line       | `modeline`, `tab-line`             |
| Git / display-buffer      | `git-display`, `window-layout`     |
| 编辑命令 / 终端           | `editing-dwim`, `terminal`         |
| LSP / 诊断 / 格式化       | `programming-tools`                |
| 项目导航                  | `project-navigation`               |
| Org / Knowledge / agenote | `org-core`, `knowledge`, `agenote` |
| 键位 / 补全               | `keybindings`, `completion`        |
| Which-key / 右键菜单翻译  | `data/which-key-zh.el`, `data/context-menu-zh.el` |
| Dashboard                 | `dashboard`                        |
| 版本兜底 shim(生效中)   | `compatibility`                    |

## 7. 验收标准

每次修改至少执行:

```bash
scripts/configctl check
scripts/configctl load
scripts/configctl test
git diff --check
git status --short
```

`check` 成功意味着:

- 8 域加载顺序和全局 tangle header 未变化。
- `CUSTOM_ID` 唯一。
- noweb 定义/使用一一对应。
- 不存在旧多文件架构引用。
- 临时 `main.el` 可完整读取且无重复顶层定义。

`load` 成功意味着临时 tangle 产物可在 Guix Emacs 包环境中加载。D-Bus session
在 batch 环境不可用时允许出现颜色方案提示;其他 Lisp error 不允许忽略。

`test` 在隔离运行时加载 `main.el` 后跑 `test/literal-config-tests.el`。包含
两类 ERT 用例:

- **必须通过的契约测试**(`literal-config/...`):固化纯函数行为(agenote 分组、
  staleness 桶、Modeline tier 边界、Tab-line per-frame 隔离),后续 commit 必须保持。
- **基线 bug 捕获测试**(`literal-config-baseline/...`,带 `:expected-result
  :failed`):记录当前违反的 P0/P1 契约。每个用例注释中标注修复它的 commit 号;
  该 commit 落地后删除 `:expected-result` 属性,让用例转为强制约束。

`check-strict` 在 `check` 基础上同时运行 `audit-agenote-domain` 与
`audit-private-api` 并把发现的违规计为失败。默认 `check` 不跑这些,以便基线
在修复期间保持绿色;修复完成后再切到 `check-strict`。

诊断子命令(每次修改都可按需运行,输出结构化报告,**不退出非零**,便于人读):

```bash
scripts/configctl audit-keys            # 键位 ↔ help-zh ↔ dashboard 一致性
scripts/configctl audit-private-api     # 第三方私有 API 调用(compatibility 白名单除外)
scripts/configctl audit-agenote-domain  # agenote 调用必须显式 --domain
scripts/configctl audit-packages        # Guix manifest ↔ use-package/require 对照
```

翻译数据是唯一的外置数据例外：`data/which-key-zh.el` 和
`data/context-menu-zh.el` 由 `appearance/i18n-data` 加载。两者只能包含注释和
预定变量的字面量 `setq`，修改后重启 Emacs；`configctl check` 会验证其文件清单、
赋值目标、括号和纯数据边界，`configctl load` 会把它们复制到隔离运行时。

额外静态检查:

```bash
rg -n "require 'literal-|provide 'literal-|:tangle +lisp/|add-to-list 'load-path" emacs.org
test ! -e lisp
```

不要运行 `blue rebuild` 或 `guix system reconfigure`。本目录是 mutable Stow 源,
配置修改无需 `blue home`;只有新增 Guix 包时提醒用户在根仓库更新并部署。
