<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# toolbox — 自研工具目录

- 源码：`dotfiles/mutable/tools/toolbox/.local/bin/toolbox` + `dotfiles/mutable/tools/toolbox/.local/share/toolbox/tools.yaml`
- 部署：`~/.local/bin/toolbox`、`~/.local/share/toolbox/tools.yaml`（mutable，改源即时生效）
- 调用方：手动运行；`tools.yaml` 同时被 `toolbox` 自身与 `toolbox check` 消费

## 用法

```bash
toolbox              # 交互浏览（fzf 列表 + 详情预览）
toolbox run <name>   # 跳过列表，直接进入指定工具的运行页
toolbox list         # 非交互列出全部工具
toolbox check        # 对账：清单条目 vs 部署位 + 未登记仓库脚本 + 一包一入口准入
toolbox help         # 本帮助
```

运行页流程：展示 brief + usage 示例 + `help_cmd` 输出 → readline 预填工具名等待输入参数（Tab 补全 `args` 词表）→ 回车执行 → 可选择再次运行。

## 依赖

- 必需：`yq`（清单解析）、`fzf`（浏览模式）
- 运行页：`timeout`、`head`、bash readline（`read -e` + `bind -x`）

## 工作原理

`tools.yaml` 是单一数据源，每条记录：`name / brief / category / usage(示例列表) / args(补全词表) / help_cmd / source(仓库源路径)`。

- `list`：非交互 TSV 输出全部条目。
- `check`（对账，分两级）：
  - 阻断级：清单条目在 `~/.local/bin` 必须存在且是 stow 软链；一包一入口准入（每个 stow 包只允许一个 `.local/bin` 入口，额外入口须在 `.bin-entries-allow` 声明理由）。
  - 信息级：仓库 `.local/bin` 里未登记的脚本（提醒收录）、清单里失效的 `source` 路径。
- `run <name>` / 浏览选中 → `run_entry`：用法页循环，直到用户直接回车返回。
- `_preview <name>`：fzf 预览面板调用的内部命令（brief + help_cmd 输出 + 源码路径），不进 help。

## 设计决策与不变量

- **`eval` 是故意的**：用户在运行页输入的是带 shell 引用的命令行（如 `secrets get foo --json`），必须经 shell 词法解析才能正确切分参数；注入面被收窄——首词强制等于选中工具名，只允许参数部分。
- **`help_cmd` 是白名单**：只登记确认过「该旗标只打印用法、不触发主逻辑」的工具。反例：`niri-app-switcher --help` 会直接启动切换器、`pi --help` 会挂起——这些条目的 `help_cmd` 留空，运行页显示「该工具无安全的 --help」。
- **Tab 补全走 `bind -x`**：`complete -W` 只覆盖交互提示符；`read -e` 的 readline 补全需要 `bind -x` 挂 `_tb_complete_word`，词表经 `TB_COMPLETE_WORDS` 传入。
- **SIGINT 被捕获而非忽略**：脚本顶层 `trap ':' INT`，让 `read`/`fzf`/被 eval 的工具各自收到信号后落回循环，而不是整体被杀；子进程不继承捕获，不受影响。
- **`usage()` 不得回读自身头部**：曾经 `sed -n '2,12p' "$SELF"` 从注释提取帮助文本——精简注释即自毁帮助。现为独立 heredoc，文本与历史输出保持一致。
- **收录标准**（写在 tools.yaml 头部）：命令（含子命令）有自研实质逻辑才登记；纯透传 wrapper 不收；子命令化工具（update/web 等并入主命令）条目挂主命令名下。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `toolbox check` 报一包一入口违规 | 某包 `.local/bin` 多了未声明的入口 | 合并为子命令到主入口，或在包内 `.bin-entries-allow` 加一行「入口名 # 理由」 |
| 运行页显示「无安全的 --help」 | 该工具的 `--help` 会触发主逻辑 | 正常现象；确证某旗标只打印后可填入 `help_cmd` |
| Tab 补全无效 | `args` 词表为空或工具未登记 | 编辑 tools.yaml 的 `args` 字段 |

## 变更记录

- 2026-09-29：`usage()` 从「`sed` 回读自身头注释」改为独立 heredoc（文本不变，消除注释-帮助耦合）；`run` 分支的 `A && B || C` 改为 `if-then-else`（修复 run_entry 未来返回非零时被误报「用法」的隐患）；`check_one_entry_per_package` 删除重复的 `local` 声明。
