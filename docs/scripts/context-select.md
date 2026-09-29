<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# context-select.sh — 四方共享的上下文注入决策核（单一真相源）

- 源码：`dotfiles/immutable/agents/.config/agents/context-select.sh`
- 部署：`~/.config/agents/context-select.sh`（immutable，改后须 `blue home`）
- 调用方：zcode `session-start.sh`（SessionStart）、omp `extensions/global-context/index.ts`（before_agent_start）、hermes `plugins/global-context/__init__.py`；crush 无 hook 机制，`context_paths` 静态声明恒注入集，由 `--check` 校验引用不烂

## 用途

决定会话启动时把 `~/.config/agents/context/` 下哪些文件注入 agent 上下文。内容分层：

| 文件            | 门控            | 语义                                                           |
| --------------- | --------------- | -------------------------------------------------------------- |
| `00-core.md`    | always          | 跨领域通用原则，恒注入（与 INDEX 合计需 ≤5500 字符）            |
| `INDEX.md`      | always          | 领域路由表（XML `<domain name file>`）；无门控端靠它指引手动拉取 |
| `domains/*.md`  | 见 `INJECT_MAP` | 领域专用原则，按门控条件按需注入                               |

当前 `INJECT_MAP`（有序，恒注入在前）：

```text
00-core.md|always
INDEX.md|always
domains/coding.md|git
domains/verify.md|git
domains/agent-ops.md|always
domains/dsh-sandbox.md|platform:dsh
```

## 用法

```bash
context-select.sh [--platform zcode|omp|crush|hermes|dsh] [--cwd DIR] [--explain]
context-select.sh --list-all
context-select.sh --check
```

- stdout 一行一个绝对路径（select/list 模式退出码恒 0）；`--explain` 把逐项判定（`✓`/`－` + 门控）写 stderr。
- `--list-all` 输出映射表全集（不做门控判定）——消费者用它注册 section 集，渲染时再以 select 结果门控。
- `--check` 一致性自检，失败 exit 1，全过 exit 0。
- 未知参数打 usage 到 stderr，exit 64。
- 环境变量 `CONTEXT_DIR` 覆盖 context 目录（默认 `$XDG_CONFIG_HOME/agents/context`），供 `blue home` 部署前用仓库源树验证。

### 门控语义

多条件用 `+` 叠加，全部满足才注入：

| 门控                | 语义                                          |
| ------------------- | --------------------------------------------- |
| `always`            | 全平台恒注入                                   |
| `git`               | `--cwd` 在 git 仓库内（向上 ≤8 层找 `.git`）   |
| `platform:p1,p2,...` | 仅列出的平台注入（`--platform` 指定；缺省 `generic`，只命中 always/git） |

### `--check` 检查项

1. 映射表引用的文件存在；
2. `domains/` 磁盘文件集合 == 映射表登记集合（防加文件忘登记 → 永不注入，静默漏）；
3. `INDEX.md` 的 `<domain>` 条目集合 == `domains/` 文件集合，且条目带 `file="domains/<name>.md"`；
4. crush：`crush.json` 的 `options.context_paths` 引用存在且覆盖恒注入集（00-core.md / INDEX.md）；
5. omp：`omp/global-context.json` 存在且 `enabled == true`；
6. hermes：`plugins/global-context/__init__.py` 存在（仅提示，不阻断）。

## 依赖

`bash`、`realpath`、`grep`、`sed`、`jq`（读 crush/omp 配置）。`set -uo pipefail`（无 `-e`：单项检查失败不中断后续校验项）。

## 设计决策与不变量

- **注入清单单一真相源**：四端经此决策，适配器不各自维护文件列表——`00-core`/`INDEX` 恒注入保证无门控端（crush 静态声明）也有原则层兜底。
- **git 门控用 `-e` 判 `.git`**（兼容 worktree 的 `.git` 文件形态，不只 `-d`）。
- **新增领域三步联动**（`--check` 校验三者一致）：`domains/` 加文件 + `INJECT_MAP` 加行 + `INDEX.md` 加 `<domain name=".." file="domains/..">` 条目。漏任一步都会静默漏注入。
- **本地调试**：`CONTEXT_DIR` + zcode `session-start.sh` 的 `CONTEXT_SELECT_BIN` 可在 `blue home` 前完成全链路验证。

## 变更记录

- 2026-10：重构——头部分层/消费链路说明迁入本文档。**修复一个真 bug**：`--platform` / `--cwd` 缺参数时 `shift 2` 失败留参，`while` 死循环挂起；现按未知参数同样处理（usage + exit 64）。基线语料其余行为逐字节一致。
