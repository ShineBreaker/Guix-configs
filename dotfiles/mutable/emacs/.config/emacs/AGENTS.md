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
- Emacs 版本 workaround 集中在 `compatibility`,但用命名 noweb ref 展开到真实使用点。
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
- 注释解释约束、兼容性和非显然决策;不要恢复整屏分隔线或已迁移模块头。

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
| Dashboard                 | `dashboard`                        |
| 版本 workaround / 待确认  | `compatibility`                    |

## 7. 验收标准

每次修改至少执行:

```bash
scripts/configctl check
scripts/configctl load
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

额外静态检查:

```bash
rg -n "require 'literal-|provide 'literal-|:tangle +lisp/|add-to-list 'load-path" emacs.org
test ! -e lisp
```

不要运行 `blue rebuild` 或 `guix system reconfigure`。本目录是 mutable Stow 源,
配置修改无需 `blue home`;只有新增 Guix 包时提醒用户在根仓库更新并部署。
