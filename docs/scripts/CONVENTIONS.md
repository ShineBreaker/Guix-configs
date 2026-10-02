<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# 脚本编写与维护规范

本仓库所有自研脚本（`blueprint.scm`、`tools/`、`dotfiles/` 下的入口与钩子、`source/config.org` 内嵌脚本、`tools/linux-setup/`）统一遵循本规范。目标：人类读者打开脚本能直接读懂代码本身，背景知识、历史与设计理由一律进文档。

## 1. 注释与文档的分工

代码里**只保留最关键的注释**，其余内容写进文档。

脚本内允许保留：

1. shebang、SPDX 版权头、编辑器/解释器指令（如 `-*- lexical-binding: t -*-`）、lint 指令（`# shellcheck disable=...`，须附简短理由）。
2. 文件头：一行用途说明 + 一行文档指针，例如：

   ```bash
   # toolbox — 自研工具目录（fzf 浏览、运行、对账）
   # 文档：docs/scripts/toolbox.md
   ```

3. 仓库规则强制要求的头注释（见 `dotfiles/mutable/AGENTS.md` 的入口准入规则）：`*-acp` 入口的约束来源、「拦截即覆写」分发与原生行为的直调路径。压缩到 1–2 行即可。
4. **不写就容易改出 bug** 的「为什么」：安全不变量、反直觉的变通、顺序依赖。每处 1–2 行，可附文档章节指针（`见 docs/scripts/<name>.md §实现与约束`）。
5. 超过约 300 行的文件可保留单行分节标记（`# --- 子命令分发 ---`），不使用多行横幅。
6. Scheme / Emacs Lisp 的 docstring 属于接口文档而非注释，保留但压缩为一句话摘要。

必须移出代码、写进文档的：用法说明与示例、历史沿革、方案对比、调用链解释、数据格式说明、逐行复述代码行为的注释。

## 2. 文档位置

| 脚本来源                       | 文档位置                                                                             |
| ------------------------------ | ------------------------------------------------------------------------------------ |
| 本仓库脚本                     | `docs/scripts/<name>.md`；同族合并为一篇，索引见 `docs/scripts/README.md`            |
| 已有专题手册的脚本             | 沿用原手册（如 `docs/emergency-blue.md`、`docs/rescue-chroot.md`），索引直接链接过去 |
| `source/config.org` 内嵌脚本   | 不进 `docs/`，写在代码块旁的 org 正文里（见 §5）                                     |
| `tools/linux-setup/`（子模块） | 该仓库自己的 `docs/`，保持子模块自包含；父仓库索引链接过去                           |

命名与归并：

- 文件名取脚本名去掉扩展名；重名时加来源前缀（如 `wireplumber-force-unmute.md`）。
- **同族同构脚本合并为一篇**，族文档用 `## <脚本名>` 分节，脚本头注释的指针相应写成 `docs/scripts/<族文档>.md §<脚本名>`。判定标准是「共享同一套前置信息、拆开后每篇只剩模板」：同一程序的多个模块（如 tmux sidebar 的 `sidebar/*.scm`）、一族一次性助手（如 `bootstrap.sh` / `build-image.scm` / `gen-partial.scm`）、一族小函数（如 fish 自定义函数）。体量大到自成子系统、或属另一体系（如注入决策核与拦截决策核）的不合并。
- **反向合并**：读者被迫在两篇之间来回跳、且两篇内容已互相复述时，并进主线那篇（`anchors-lib.md` 并入 `gate-core.md`）。
- 文档描述的源码被删除时，文档一并删除——不保留无源码可校的存档。

## 3. 文档模板与排版

```markdown
<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# <脚本名> — <一句话用途>

<源码路径> · <部署方式> · <调用方>

## 用法

## 实现与约束

## 排障（可选）

## 变更（可选，仅破坏性改动：日期、旧行为 → 新行为、迁移方式）
```

族文档：标题行与元信息行写一次，之后每个脚本一个 `## <脚本名>`；共用协议、差异对照提到族首的公共小节，不要在每个脚本下重复。

排版规则：

1. **段落写成单行，禁止手动折行**。让编辑器软折行随窗口宽度走，不要在源码里切断句子——切断后 diff 变成噪音，grep 也搜不到完整语句。
2. 命令与输出协议用代码块或表格，不用散落的行内反引号拼接。
3. 表格不超过 5 列；一行能说完的不建表。
4. 不留空壳小节。凑不出内容的「依赖」「工作原理」直接删掉，依赖并进元信息行。
5. 「变更」只在有破坏性行为变化时出现；没有就整节省略，**禁止写「无破坏性改动」这类零信息量条目**。目录迁移类事实写成「现状陈述」，历史事故只在仍会复发时保留为一行排障线索。
6. 只写可以从代码、上游文档或实测确证的内容，不臆测历史原因。
7. 文档里引用的命令、路径、退出码必须与源码对得上；源码变了就改文档，不留过时说法。
8. 排版交给 `blue format <文件>`，别手工调：标点与中英间距走 `doc-punct.py`，表格列宽、列表缩进、末尾换行走 prettier（编排见 [doc-format.md](doc-format.md)）。两级都不折正文，所以第 1 条的单行规则不会被工具推翻。

### 章节标题是跨文件契约

源码注释常按名字引用文档章节（如 `gate-core.md §设计决策与不变量`、`sidebar-toggle.md §宽度策略`）。Markdown 锚点只是文字，没有校验，标题一改指针就静默悬空。因此：

- **§ 锚点一律带空格分隔**，不用 `.` 或 `-` 连接（只有仓库内多词 id 如 `agent-ops`、`dsh-sandbox` 例外）。
- 重排标题或拆并文档前，先 `rg -n 'docs/scripts/\S+\.md §|\.md §' --hidden` 把所有引用捞出来逐一核对；顺带修正**已经悬空**的旧引用。
- 合并文档时优先选**沿用旧文件名**的那篇做族首，把被合并的脚本写成它的 `## <脚本名>` 小节，可让大部分指针原地继续有效。

## 4. 可靠性要求

### Bash

- 默认 `set -euo pipefail`。刻意不用 `-e` 的脚本（如 `gate-core.sh`：单项检查失败不能中断后续检查）在文件头用一行写明理由。
- 被 `source` 的库文件（`*-lib.sh`、`anchors-lib.sh`、`hermes-lib.sh` 等）**不修改**调用方的 shell 选项，也不 `exit`。`theme-common.sh` 是 `exec` 的可执行入口而非库，不受此条约束。
- 所有变量展开加引号；命令行参数用数组传递；避免 `eval`，确需使用时注释理由。
- 统一的 `die` / `warn` 辅助函数：错误写 stderr、带脚本名前缀、非零退出。
- 非基础依赖（`jq`、`yq`、`fzf`、`age` 等）在入口处用 `command -v` 检查并给出可操作的报错。
- 临时文件用 `mktemp` + `trap` 清理；改写配置文件时先写临时文件再 `mv`（原子替换）。
- 帮助文本写在 `usage()` 的 heredoc 里，**不**从脚本自身的注释截取。CLI 类脚本支持 `-h` / `--help`。
- POSIX `sh` 脚本保持 POSIX，不引入 bash 语法。
- `set -e` + `pipefail` 下的已知陷阱（本仓库都真实踩过）：
  - `x=$(grep … | head -1)` 在无匹配时会中止脚本：无匹配属正常情况时写成 `… || true`。
  - 以 `[[ 条件 ]] && cmd` 作为函数或脚本的最后一条语句，条件为假时返回非零：改写成 `if`。
  - `A && B || C` 不等于 if-else（B 失败时也会跑 C）：改写成 `if`。
  - 经 `$(func)` 调用的函数，菜单和提示要写到 stderr，否则会被吞掉并混进返回值。
  - 被 `head` 截断的长输出管道，用 `while …; done < <(cmd | head -n N)`，避免 SIGPIPE 触发 pipefail。
- 格式：`shfmt -i 2 -ci -bn`；检查：`bash -n` 与 shellcheck（`uvx --from shellcheck-py shellcheck`）零告警，确需豁免的逐条 `disable` 并写理由。

### Fish

- `fish --no-execute` 通过；用 `fish_indent` 格式化。
- 函数用 `argparse` 解析参数，`-h/--help` 输出用法；错误写 stderr 并 `return 1`。

### Guile Scheme

- 遵循仓库根 `AGENTS.md` 的方括号规范。
- 顶层定义按「常量 → 工具函数 → 业务逻辑 → 入口」排列。

### Emacs Lisp

- 文件首行 `lexical-binding: t`；`emacs --batch` 字节编译无警告。
- 验证 `tools/*.el` 时走生产路径（blueprint 的 `%run-elisp`：`guix time-machine -C source/channel.lock -- shell emacs-minimal -- emacs …`）：`~/.guix-home/profile/bin/emacs` 包装器会吞掉子进程的退出码。
- 在 temp buffer 里 `write-region` 时显式绑定 `coding-system-for-write`（如 `'utf-8-unix`），否则会回退到 locale 默认编码。

### Python

- `python3 -m py_compile` 通过；`uvx ruff check` 零告警。

## 5. `source/config.org` 内嵌脚本

`config.org` 是文学式配置，解释工作交给 org 自身的文档结构：

- 每个内嵌脚本所在的标题下，用 org 正文说明用途、运行时机、依赖与不变量；需要结构化元数据时使用标题的 `:PROPERTIES:` 抽屉（已有 `CUSTOM_ID` 约定）。
- 代码块用 `#+NAME:` 命名，必要时加 `#+CAPTION:` 一句话说明。
- 代码块内只保留短分类标签与关键警示（它们会进入 tangle 产物）。
- 遵循 `source/AGENTS.md` 的 org 写法：`=code=` 两侧留 ASCII 空白或标点，全角标点。
- 验证：`blue check` 与 `blue --dry-run rebuild`；并把改动前后的 tangle 产物逐文件 diff，确认差异只在注释与预期改动。

## 6. 接口变更

允许为可靠性做破坏性改动，但同一次改动内必须同步：

- 所有调用方（`rg --hidden` 全仓搜索脚本名，含 niri / tmux / fish 配置、`config.org`、其他脚本）；
- fish 补全 `dotfiles/immutable/terminal/.config/fish/completions/<name>.fish`；
- toolbox 清单 `dotfiles/mutable/tools/toolbox/.local/share/toolbox/tools.yaml`（`usage` / `args` / `help_cmd`）；
- 相关 `AGENTS.md` 与文档的「变更记录」。

跨语言协议保持稳定：`gate-core.sh` 的 CLI 与 stdout 行协议、`context-select.sh` 的输出格式、各 agent 宿主规定的钩子协议。

## 7. 验证方法

1. **基线**：改动前把 HEAD 版本（`git show HEAD:<path>`）复制到 `/tmp/<任务名>/head/`，改动后的版本放在 `new/`。
2. **用例**：覆盖帮助、参数错误、主路径和主要失败路径；安全相关脚本还要覆盖文档「设计决策与不变量」里的每一条，命中和未命中都要有。
3. **沙箱**：
   - 外部命令用 PATH 桩：把 argv 追加写进日志后返回预设结果。
   - `HOME` 指向临时目录，其中复制真实规则文件（如 `anchors.json`）以保证用例贴近实际。
   - tmux 用 `tmux -L <name> -f /dev/null`，结束后 kill 掉。
   - 需要 Emacs server 时使用独立的 socket 名。
4. **比较**：同一组用例分别跑新旧两版，归一化临时路径、时间戳、PID 后 `diff -r`。stdout、stderr、退出码、桩日志、生成的文件都要比。
5. **完成判据**：差异为空，或每一处差异都在「变更记录」里说明原因。
6. **静态检查**：§4 里对应语言的检查全部通过；`config.org` 额外对比改动前后的全部 tangle 产物。
7. **部署位置陷阱**：
   - `gate-core.sh` 优先加载已部署的 `~/.config/agents/anchors-lib.sh`：测试源码版本时用临时 `HOME`。
   - `blueprint.scm` 以 cwd 为 `%repo-root`：放在仓库副本里测试。
