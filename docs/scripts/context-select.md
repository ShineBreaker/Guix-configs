<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# context-select.sh — Pi / OMP / ZCode / Hermes / DSH 共用的会话上下文注入决策核

`dotfiles/immutable/agents/.config/agents/context-select.sh` · immutable → `~/.config/agents/context-select.sh`（改后须 `blue home`）· 调用方：zcode `~/.zcode/hooks/session-start.sh`（`--platform zcode`）、omp `dotfiles/mutable/agents/extensions/global-context/index.ts`（`--platform omp`）、hermes `plugins/global-context/__init__.py`（`--platform hermes`）、DSH `profiles/agent-extensions/global-context.js`（`--platform dsh`，路径可由 `CONTEXT_SELECT_BIN` 覆盖）。`--check` 另会探测 omp 与 crush 的配置文件，但两者都不调本脚本（crush 已整体移出本仓库，探测恒为「跳过」提示）

内容分层在 `~/.config/agents/context/`：`00-core.md` 是跨领域通用原则、`INDEX.md` 是领域路由表（XML `<domain name=… file=…>` 条目）、`domains/<name>.md` 是领域专属原则。本脚本只回答「这个会话该注入哪些文件」，不读内容；注入清单单一真相源在此，各端适配器不各自维护文件列表。

## 用法

```bash
context-select.sh [--platform P] [--cwd DIR] [--explain]   # 默认模式
context-select.sh --list-all                                # 映射表全集，不做门控
context-select.sh --check                                   # 一致性自检
```

| 面     | 形态                                                             |
| ------ | ---------------------------------------------------------------- |
| stdout | 一行一个绝对路径；`--explain` 与 `--check` 的全部输出也走 stdout |
| stderr | 只有 usage（参数错误时）                                         |
| 退出码 | 默认与 `--list-all` 恒 0；`--check` 有 fail 项为 1；参数错误 64  |

`--platform` 缺省 `generic`，只命中 `always` 与 `git` 门控。`--explain` 把逐项判定写成 `✓ <文件>（<门控>）` / `－ <文件>（<门控> 未满足）`，只作用于默认模式，`--list-all` 不看该标志。

**`--platform` 或 `--cwd` 缺参数时必须报 usage 并 exit 64**：这两个标志的分支末尾是 `shift 2`，只剩 1 个参数时 `shift` 失败且原样留参，`while` 循环原地打转挂死——分支内显式判 `$# -lt 2` 就是为这个坑。未知参数同样按 usage + exit 64 处理。

`--list-all` 输出 `INJECT_MAP` 的全集且不做门控判定：消费者先用它注册 section 集，渲染时再按默认模式的门控结果裁剪。

| 环境变量          | 语义                                                                     |
| ----------------- | ------------------------------------------------------------------------ |
| `CONTEXT_DIR`     | 覆盖 context 根，默认 `${XDG_CONFIG_HOME:-$HOME/.config}/agents/context` |
| `XDG_CONFIG_HOME` | 覆盖配置根，参与 `--check` 里 crush 与 omp 配置的定位                    |

`CONTEXT_DIR` 与各端的 selector 路径变量（zcode 与 DSH 都认 `CONTEXT_SELECT_BIN`）配合，可在 `blue home` 部署前用仓库源码跑通全链路。

### 门控语义

`INJECT_MAP` 每行是 `<相对路径>|<门控>`，恒注入在前、域文件在后；多条件用 `+` 叠加，全部满足才注入；`INJECT_MAP` 里没出现过的门控词一律判为不满足（永不注入）。

| 门控                 | 语义                                          |
| -------------------- | --------------------------------------------- |
| `always`             | 全平台恒注入                                  |
| `git`                | `--cwd` 在 git 仓库内：向上最多 8 层找 `.git` |
| `platform:p1,p2,...` | 仅列出的平台注入                              |

`git` 门控用 `[[ -e "$d/.git" ]]` 判存在而非 `[[ -d ]]`，这样 `git worktree` 的 `.git` **文件**形态同样算仓库内。

当前映射表：

```text
00-core.md|always
INDEX.md|always
domains/coding.md|git
domains/verify.md|git
domains/agent-ops.md|always
domains/dsh-sandbox.md|platform:dsh
```

### 新增领域的三步联动

`domains/<name>.md` 建文件 → `INJECT_MAP` 加一行门控规则 → `INDEX.md` 加 `<domain name="<name>" file="domains/<name>.md">` 条目。**漏任一步都是静默漏注入**：漏映射表则文件永不注入，漏 `INDEX.md` 则路由表里没有这条、agent 不会主动去读它，`--check` 会把两种不一致都报成 fail。

字符预算：`00-core.md` 与 `INDEX.md` 合计 ≤5500 字符，超限须精简（约定见 `dotfiles/immutable/agents/AGENTS.md`，脚本本身不校验）。

### `--check` 的分级

输出走 stdout，`✗` 行置 `fail=1` 并最终 exit 1，`－` 行只是提示不阻断，全过时打印 `✓` 并 exit 0。

| 检查项                                                                  | 不一致时                           |
| ----------------------------------------------------------------------- | ---------------------------------- |
| 映射表引用的文件存在                                                    | fail                               |
| `domains/` 磁盘集合 == 映射集合                                         | fail（双向，含未登记与已登记缺失） |
| `INDEX.md` 条目集合 == `domains/`                                       | fail（双向）                       |
| `INDEX.md` 条目带 `file=` 声明                                          | fail（逐条比对 name 与 file 同名） |
| crush `context_paths` 指向的文件存在、且覆盖 `00-core.md` 与 `INDEX.md` | fail                               |
| omp `global-context.json` 存在                                          | fail                               |
| crush `crush.json` 可读                                                 | 仅提示「跳过 crush 校验」          |
| omp `enabled == true`                                                   | 仅提示「已禁用」                   |
| hermes 插件已部署                                                       | 仅提示「未部署，跳过」             |

crush 已整体移出本仓库，其 `crush.json` 不再存在，因此上表的 crush 两行在当前机器上恒为「跳过」提示——`--check` 仍会照常执行这一探测。hermes 插件是可选部署，未部署时同样只提示。

依赖 `bash`、`realpath`、`grep`、`sed`、`jq`（读 crush 与 omp 的 JSON 配置）。`set -uo pipefail` 不用 `-e`：单项检查失败不应中断后续校验项。
