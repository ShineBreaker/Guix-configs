<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# toolbox — 自研工具目录（fzf 浏览 → 看帮助 → Tab 补全传参 → 运行）

`dotfiles/mutable/tools/toolbox/.local/bin/toolbox` + `.local/share/toolbox/tools.yaml` · 部署到 `~/.local/bin/toolbox` 与 `~/.local/share/toolbox/tools.yaml`（mutable，stow 直链，改源即时生效）· 调用方：手动运行

本文只写**机制与不变量**；文件清单与收录标准的操作视角见 [toolbox/AGENTS.md](../../dotfiles/mutable/tools/toolbox/AGENTS.md)。

## 用法

```bash
toolbox              # 交互浏览（fzf 列表 + 右侧详情预览）
toolbox run <name>   # 跳过列表，直接进入指定工具的运行页
toolbox list         # 非交互列出全部工具（category/name/brief 按字母序对齐输出）
toolbox check        # 对账：清单条目 vs 部署位 + 一包一入口准入 + 未登记脚本
toolbox help         # 本帮助
```

依赖 `yq`（清单解析）、`fzf`（浏览）、`timeout` 与 `head`（`help_cmd` 抓取）、bash readline（`read -e` + `bind -x`）。清单位置可用 `TOOLBOX_HOME` 覆盖（默认 `$HOME/.local/share/toolbox`），`PATH` 前置 `$HOME/.local/bin`，脚本经 `readlink -f "$0"` 自定位仓库源（`check` 靠它上溯到 `dotfiles/`）。

运行页（`run_entry`）是用法页循环：展示 brief + usage 示例 + `help_cmd` 输出 → readline 预填工具名等参数（Tab 补全 `args` 词表）→ 回车执行 → 可选再次运行。`preview` 是 fzf `--preview` 子进程调用的内部命令（brief + 分类 + 用法示例 + help 输出 + 源码路径），不进 `help`。

## 实现与约束

- **数据源单一**：`tools.yaml` 每条记录 `name / brief / category / usage(示例列表) / args(补全词表) / help_cmd / source`，收录标准写在清单头部与 AGENTS.md，本文不重复。
- **`eval` 是故意的**：运行页输入的是带 shell 引用的命令行（`secrets get foo --json`），必须经 shell 词法解析才能正确切分；注入面被收窄——首词必须严格等于选中工具名（不符则打印提示并回到循环），只允许参数部分。
- **`help_cmd` 是白名单**：只登记确证过「该旗标只打印用法、不触发主逻辑」的工具；反例 `niri-app-switcher --help` 直接启动切换器、`pi --help` 挂起，这些条目 `help_cmd` 留空，运行页与预览改显示「该工具无安全的 --help」。抓取一律带 `timeout` 与行数上限（预览 `timeout 2 … | head -60`，运行页 `timeout 3 … | head -40`）。
- **Tab 补全走 `bind -x`**：`complete -W` 只覆盖交互提示符，`read -e` 的 readline 补全必须由 `bind -x '"\t": _tb_complete_word'` 挂入，词表经 `TB_COMPLETE_WORDS` 传入；词表为空时回落 `compgen -f` 文件名补全，多候选补公共前缀或列出候选。
- **SIGINT 被捕获而非忽略**：顶层 `trap ':' INT`，让 `read` / `fzf` / 被 `eval` 的工具各自收到信号后落回循环，而不是非交互 bash 默认的整体杀死；子进程不继承「已捕获」，不受影响。
- **`usage()` 不得回读自身注释**：历史实现用 `sed` 从文件头注释提取帮助，精简注释即自毁帮助；现为独立 heredoc，文本与历史输出一致。
- **`run` 分支不用 `&&` / `||` 链**：`run_entry` 未来返回非零会让 `|| die` 误报用法错（SC2015），故写成 `if-then-else`。
- **`check` 两级**：阻断级 ① `check_catalog`——清单每条 `name` 必须能被 `command -v` 解析（`PATH` 首位即 `~/.local/bin`），捕获工具改名/删除后的残留条目；阻断级 ② `check_one_entry_per_package`——以 `dotfiles/mutable/**/.stow-package` 定界包（判据与 `blue stow` 一致），每个包的 `.local/bin` 直下 `-perm -u+x` 的常规可执行文件只允许 1 个（子目录会整目录链接，不算入口），额外入口须在包根 `.bin-entries-allow` 声明「入口名 # 理由」且**理由不可省略**（缺理由的声明行同样算违规），`*-acp` 协议入口自动豁免（外部 ACP host 按命令名寻址 agent，无法子命令化）；信息级 `check_unregistered`——仓库 `.local/bin` 里未登记的脚本（`comm -23` 差集，wrapper 类预期不登记），恒不致失败。

## 排障

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `toolbox check` 报一包一入口违规 | 某包 `.local/bin` 多了未声明的入口 | 合并为子命令到主入口，或在包根 `.bin-entries-allow` 加一行「入口名 # 理由」 |
| `toolbox check` 报豁免行缺理由 | `.bin-entries-allow` 有无 `#` 理由的行 | 补上理由——豁免是给人看的决策记录 |
| 运行页显示「无安全的 --help」 | 该工具的 `--help` 会触发主逻辑 | 正常现象；确证某旗标只打印用法后才填入 `help_cmd` |
| Tab 补全无效 | `args` 词表为空或工具未登记 | 编辑 `tools.yaml` 的 `args` 字段 |