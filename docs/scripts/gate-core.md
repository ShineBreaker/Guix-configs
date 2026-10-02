<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# gate-core.sh 与 anchors-lib.sh — agent 工具调用的判定核与规则源

`dotfiles/immutable/agents/.config/agents/{gate-core.sh,anchors-lib.sh}` · immutable → `~/.config/agents/`（改后须 `blue home`）· 调用方：zcode `~/.zcode/hooks/{bash,edit}-gate.sh`、pi `dotfiles/mutable/agents/extensions/pi-gate/index.ts`、hermes `dotfiles/mutable/agents/hermes/.local/share/hermes/plugins/gate/__init__.py`、DSH `dotfiles/mutable/agents/dsh/.local/share/dsh/profiles/agent-extensions/gate.js`（`anchors-lib.sh` 另被 zcode `session-start.sh` 直接 source）

判定核是四端共享的唯一真相源：CLI、行协议、环境变量与安全不变量全部定义在 `gate-core.sh`，适配器只做协议转换。`anchors-lib.sh` 只做「读 + 合并」，不含任何判定语义。**改匹配逻辑前先通读 §设计决策与不变量**——每条不变量在实现处都有一行注释指回该节。

## 用法

```bash
gate-core.sh bash <cmd>    # Bash 命令判定；全部参数以 "$*" 合并成一条命令
gate-core.sh edit <file>   # 写入判定；只取首参为路径，待检内容从 stdin 读（可为空）
```

| 场景                     | 退出码 | 输出                            |
| ------------------------ | ------ | ------------------------------- |
| 判定跑完（无论是否拦截） | 0      | stdout 行协议                   |
| 无子命令或未知子命令     | 64     | usage 到 stderr，无 stdout      |

**判定退出码恒 0**：拦截与否只体现在 stdout 的行类型里，不体现在退出码上（进程级失败属异常，由各适配器自己的 fail-closed 策略兜底）。

stdout 行协议每行一条 `TYPE<TAB>payload`，payload 内的换行由 `emit` 压成空格，保证一行一裁决。核实际发出的类型只有以下七种：

| TYPE        | 语义                                             | 发出位置                       |
| ----------- | ------------------------------------------------ | ------------------------------ |
| `BLOCK`     | 硬拦截，payload 为理由                           | frozen 命令 / git / 路径 / glob |
| `SENSITIVE` | 待检内容命中 `sensitive_patterns`，payload 汇总 label | edit 敏感检测            |
| `AUTO_ALLOW`| 只读白名单命中，无 payload                       | bash 白名单阶段                |
| `REWRITTEN` | 改写后的命令全文，payload 是新命令               | bash 改写阶段                  |
| `NOTES`     | 命令替代偏好提示                                 | bash 改写阶段                  |
| `REDIRECT`  | 重定向建议                                       | bash 改写阶段                  |
| `HINT`      | 路径联动提示，可多条                              | edit `path_hints`              |

核**不发** `RM_HINT`：`rm` 的提示语是 `BLOCK` 的 payload（命中词恰为 `rm` 时走专用文案）。`RM_HINT` 只出现在各适配器解析行协议的兼容分支里，是历史协议残留。

| 环境变量              | 语义                                                                                                       |
| --------------------- | ---------------------------------------------------------------------------------------------------------- |
| `GATE_CWD`            | anchors 层级定位起点与 edit 的项目根判定基准，默认 `$PWD`；由适配器从宿主传入的 cwd 设置                  |
| `GATE_NO_WRITE_TOOLS` | `1` = 无写工具会话（DSH `gate.js` 按当前 agent 作用域检测后置位），只收窄输出，永不制造放行，见 §设计决策与不变量 |

依赖 `bash`、`jq`、`awk`、`sed`、`grep`、`realpath`（无 `realpath` 时两种路径模式都退化为 `readlink -f`）。刻意用 `set -uo pipefail` 而不带 `-e`：单个检查工具异常（如 `jq` 输出非预期）不应中断后续检查。

**人工总开关**：`/run/agent-gate.off` 存在即 `bash` 与 `edit` 全部**零输出**静默放行。`/run` 是 root 拥有的 tmpfs，创建与删除都要提权，而提权命令对 agent 恒冻，agent 自己打不开这个开关；重启自动清空，天然临时。开关只认固定路径，不接受环境变量改道；操作方式与约定见 `dotfiles/immutable/agents/AGENTS.md`。

## 判定流水线

两个入口共用同一阶段约定：命中并 emit → `return 0` 终止主流程；未命中 → `return 1` 继续下一阶段。顺序与早退语义不可变。

`bash` 链（`gate_bash`）：

| # | 阶段                      | 命中即                                              |
| - | ------------------------- | --------------------------------------------------- |
| 0 | 人工总开关                | 存在即零输出返回                                    |
| 1 | `check_frozen_commands`   | 冻结命令命中发 `BLOCK`；另有 `guix system` 宽匹配   |
| 2 | `check_interactive_commands` | 交互式命令 / 裸 REPL 发 `BLOCK`                 |
| 3 | `check_git_rules`         | 无 `-m` 的 commit、`add -p`、`rebase -i` 发 `BLOCK` |
| 4 | `check_readonly_whitelist`| 白名单命中发 `AUTO_ALLOW`                           |
| 5 | `apply_rewrites_and_hints`| 发 `REWRITTEN` / `NOTES` / `REDIRECT`，无拦截语义   |

`edit` 链（`gate_edit`）：

| # | 阶段                       | 命中即                                                        |
| - | -------------------------- | ------------------------------------------------------------- |
| 0 | 人工总开关                 | 存在即零输出返回                                              |
| 1 | `check_meta_frozen`        | 全局 `anchors.json` 或 `_meta_frozen` 项目规则源发 `BLOCK`     |
| 2 | `check_frozen_paths`       | 逻辑/物理任一路径命中冻结条目发 `BLOCK`                       |
| 3 | `check_frozen_globs`       | 目标在项目内且命中 glob 发 `BLOCK`                            |
| 4 | `check_deployed_locations` | 直改 `~/.config/` 或 `~/.local/` 发 `BLOCK`                   |
| 5 | `check_sensitive_and_hints`| stdin 命中敏感模式发 `SENSITIVE`；`path_hints` 发 `HINT`       |

`edit` 的项目根基准由 `GATE_CWD` 经 `find_git_root` 求得（`anchors-lib.sh` 提供），据此算出两个布尔量：逻辑路径落在 `PROJ` 内为 `INSIDE`（物理路径则为 `INSP`），后续多项检查按它们启停。`find_git_root` 只认 `.git` **目录**，找不到时返回入参本身——于是非仓库 cwd 下 `PROJ` 就是 cwd 自己，其下的一切都算「项目内」，`frozen_globs` 与 `path_hints` 照常生效，但要求 `INSIDE=0` 的 `~/.config` 直改保护不会触发。

## 设计决策与不变量

以下每条不变量在实现处都有一行注释指回本节，是历史绕过教训的清单——改动前先读。

**1. 冻结命令按命令位置的词序列匹配。** `_cmd_segments` 先按命令边界（`;` `&` `|` `(` `)` 反引号、` -- `、换行）切片并剥掉引号与反斜杠，再由 `_match_frozen_in_segments` 匹配片段的首词序列（词间允许插入任意完整词）。参数、字符串、heredoc 正文里的冻结词因此不再命中——误报主源是 commit message 与文档字符串。剥引号是代价也是堵点：`git commit -m "a; sudo x"` 里引号内的 `;` 同样成为边界，这是可接受的保守方向（字符串宁可误拦不可漏拦）。

**2. 两项归一化堵完整路径与 env 前缀绕过。** 片段首词取 basename 后再判，`/run/current-system/profile/bin/sudo` 与 `~/bin/sudo` 同判；`FOO=/x sudo …` 的 env 赋值前缀循环剥离后再判首词。

**3. 再执行通道的段内子串兜底。** 片段首词属于 `sh`/`bash`/`dash`/`ash`/`env`/`nohup`/`xargs`/`ssh`/`parallel`/`find`/`exec` 时，除首词锚定外再跑一遍词边界子串匹配，堵引号包裹的间接执行：`sh -c 'sudo x'`、`xargs sudo`、`find . -exec sudo {} \;` 均命中。

**4. heredoc 正文按消费者分流。** 消费者是解释器（`sh`/`bash`/`zsh`/`dash`/`ash`/`fish`/`python*`/`node*`/`deno`/`guile*`/`perl`/`ruby`/`tclsh`）时正文会被执行，保留进片段流参与匹配；数据消费者（`cat` 等）的正文是纯数据，剔除。`cat <<E | bash` 视为交解释器执行，正文保留。

**5. `guix system` 走子串级宽匹配。** 词序列之外还有一条防线：豁免片段剔除后命令文本含 `guix` 且匹配 `system (reconfigure|init)` 即拦，专为 `guix time-machine -- … -- system reconfigure` 这类包装形态（`--` 把 `system reconfigure` 切成独立片段，词序列够不到 `guix`）。副作用是 `echo guix system reconfigure` 也会被拦，属可接受的保守方向。

**6. 明确放弃的极端 case，不要「修复」。** `$(printf %s su)do` 这类运行时才存在的命令替换拼接，以及解释器代码内部的动态拼接（`os.system("sudo …")`），追进去就等于全文子串匹配、误报无界，属对抗性构造而非 agent 自然行为。大小写 `SUDO` 不命中（冻结词按 anchors 原文匹配）。冻结词不在命令位置时不拦，如 `watch sudo x`。`zsh`/`fish` 不在再执行通道名单内，`zsh -c 'sudo x'` 不拦——扩充名单须先评估通道误报面。

**7. 预演豁免是片段级的。** 只剔除「首词是 `blue` 且片段含 `--dry-run`」或「首词是 `just` 且片段含非空 `dry=`」的片段，其余片段照常检查：`blue --dry-run rebuild; sudo x` 的 sudo 片段不被连带豁免；`sudo … --dry-run` 不豁免（首词不是 blue/just）；`just dry= rebuild`（空值）不豁免。

**8. 白名单在全部硬拦截之后，且只对单条命令生效。** `check_readonly_whitelist` 位于链尾，不构成绕过；命令文本含 `;`、`&`、`|`、反引号或 `$(` 时整个白名单跳过（搭车形态回落默认确认流），因此多行命令 `ls` + 换行 + `cat x` 只要首词在白名单里仍会拿到 `AUTO_ALLOW`——是否拦截取决于前三级冻结检查。白名单按首词 basename 匹配，`git` 仅在命令里不含写操作子命令时放行，`guix` 仅放行 `describe`/`show`/`search`/`hash`/`lint`/`size`/`graph`/`weather`。

**9. 词法类检查只匹配原始命令文本，不做归一化。** 交互式命令、裸 REPL、git 规则、只读白名单都对 `$CMD` 原文跑 ERE，命令边界前缀固定为 `(^|[;&|()$]|&&|\|\|)[[:space:]]*`。不归一化是为了避免 `echo "vim tips"` 这类字符串内容被误拦——`vim` 前是引号，不在边界字符集里。注意白名单的连接符门控用的是另一条正则 `[;&|`]|\$\(`，两者字符集不同（`$` 只在词法前缀里，反引号只在白名单门控里）。`git add -p`、`git rebase -i` 的 `-p`/`-i` 是词边界短选项匹配，`--patch`/`--interactive` 长选项不命中，属已知行为。

**10. 人工总开关只认固定路径。** `/run/agent-gate.off` 存在即静默放行且不输出任何内容——暂停态对 agent 不可见，与护栏不存在时表现一致。agent 可写的位置放同名文件一律无效，该文件只能人工 sudo 创建或删除。各适配器同样硬编此路径。

**11. `GATE_NO_WRITE_TOOLS=1` 只做输出降级。** 无写工具会话（DSH 的 simple-mode 一类 preset 只有持久 bash）里，`redirect_conventions` 的替代理由会引导模型去调不存在的 Edit 工具而死锁，故降级输出：`BLOCK` 不附 redirect ALT 而回落通用冻结理由、交互式命令去掉「请使用对应工具」尾巴、`NOTES` 与 `REDIRECT` 整条抑制；硬拦截、`AUTO_ALLOW`、`REWRITTEN` 一概不变。降级只收窄输出，不制造任何放行面。其他端不设该变量，行为零变化。

**12. edit 走逻辑与物理双路径，任一命中即拦。** `resolve_path` 的逻辑模式（`realpath -ms`，不解析 symlink）用于 meta-frozen 与部署位置检查——`~/.config` 下大量路径是 store 软链，物理解析会让这两类保护落空；物理模式（`realpath -mP`，解析 symlink）用于 `frozen_paths` 与 `frozen_globs`，防经 `/tmp` 等中转软链写入冻结目标。无 `realpath` 的系统上两种模式都退化为 `readlink -f`，双路径退化为同一路径。

**13. `frozen_paths` 的相对条目是前缀与后缀混合判定。** `~/` 开头的条目按逻辑与物理路径的前缀树匹配（尾斜杠先剥掉，否则双斜杠模式永不命中）；其余条目同时做四种判定：逻辑相对路径前缀、物理相对路径前缀、逻辑全路径子串、物理全路径子串。后两种子串判定不受 `INSIDE`/`INSP` 约束，因此像 `channel.lock` 这类短条目在任何位置都会被命中。

**14. `unless_inside` 是逐条目的条件豁免。** `frozen_paths` 条目支持 `{"path": ..., "unless_inside": "<dir>"}`，`_meta_frozen` 支持 `{"unless_inside": "<dir>"}`：`GATE_CWD` 物理解析后位于该目录内时该条目不拦（决策核仓库内的会话可维护自己的规则源）。逐条目判定意味着近层补一条无条件条目即可恢复拦截，且不违反「只加不减」；豁免只能由人工维护的规则源声明，cwd 之外的会话仍被同一条目拦住。`cwd_under` 对 base 与 cwd 都做物理解析，防 cwd 经软链指向目标目录误判。

**15. `_meta_frozen` 三态。** 只在目标 basename 为 `anchors.json` 时判：逻辑路径等于 `~/.config/agents/anchors.json` 的逻辑解即全局规则源，直接拦；文件存在且 `_meta_frozen == true` 即人工锁定的项目规则源，拦；`_meta_frozen` 是对象且声明了 `unless_inside` 而 cwd 不在范围内时拦。对象形式未声明 `unless_inside` 时不拦。

## 部署形态约束

`anchors-lib.sh` 的定位顺序是 `$HOME/.config/agents/anchors-lib.sh` 优先、`dirname $0` 同目录兜底。原因是 home-dotfiles 把每个文件复制成**独立** store 项，`gate-core.sh` 与 `anchors-lib.sh` 不落在同一个 store 目录，同目录查找在部署形态下必然落空；同目录兜底只在源码树或直链场景生效。

`anchors-lib.sh` 找不到或 `source` 失败时，`MERGED` 回退 `gate-core.sh` 内置的 DEFAULT——`frozen_commands` 只有 `["sudo"]`，其余字段全空、`builtin_rewrite: true`。同理，`load_merged_anchors` 返回失败也回退同一个 DEFAULT。hook 不因配置损坏整体失效是硬要求。

## 规则源：anchors 分层与 ratchet 合并

三层规则源，代码底层在 `anchors-lib.sh` 的 merge 程序里，各层按由远到近的顺序叠加：

1. **代码底层 DEFAULT**：`frozen_commands` 恒含 `sudo`，其余字段空，`builtin_rewrite: true`。没有任何 `anchors.json` 时返回的就是它。
2. **全局** `~/.config/agents/anchors.json`：跨工作区通用约束（冻结命令、交互式命令、敏感模式等），meta-frozen 人工维护。
3. **项目级** `<root>/.agents/anchors.json`：从起点向上逐层收集，**含 git 根后停止**（`_find_anchors_files_near_to_root` 最多上溯 64 层，到根目录也停）。

| 字段类型                              | 合并规则                                                                 |
| ------------------------------------- | ------------------------------------------------------------------------ |
| 数组（`frozen_commands` 等 7 个）     | `unique` 并集                                                             |
| `sensitive_patterns`                  | 按 `.pattern` 做 `unique_by` 并集，同 pattern 重复时**远层条目保留**     |
| 映射（`redirect_conventions`/`rewrite`/`path_hints`） | jq `*` 浅合并，近层覆盖远层                          |
| `builtin_rewrite`                     | 布尔值由显式给出该字段的层覆盖，未给出的层不影响                       |

**只加不减**：项目层无法移除全局或代码底层的条目，近层要削弱某条只能加 `unless_inside` 条件豁免。任一层损坏或 jq 合并失败 → 回退 DEFAULT 并向 `~/.config/omp/extensions/.load-errors.log` 追加一行（`log_gate_error`，时间戳 + 扩展标签 + 位置 + 原因，标签沿用历史值 `crush-gate`），防静默吞错。

| 函数                                 | 语义                                                                  |
| ------------------------------------ | --------------------------------------------------------------------- |
| `load_merged_anchors [start_dir]`    | 合并全部层，stdout 输出合并 JSON；默认起点 `$PWD`                     |
| `find_git_root <dir>`                | 向上找含 `.git` **目录**的目录，最多 64 层；找不到返回入参本身        |
| `glob_to_ere <glob>`                 | glob → 锚定 ERE，见 §glob 语义                                        |
| `log_gate_error <ext> <where> <msg>` | 追加一行错误日志                                                      |
| `expand_tilde <path>`                | `~/` 前缀按 `$HOME` 展开（`gate-core.sh` 自己做等价展开，此函数当前无调用方） |

**库契约**：本文件是被 `source` 的库，不设 `-e`/`-u`/`pipefail`、不 `exit`、不依赖调用方未声明的环境状态；函数名前缀 `_` 表示内部实现；`_ANCHORS_LIB_LOADED` 幂等哨兵允许重复 source。`load_merged_anchors` 收集项目层用**进程替换**而非管道——管道右侧在子 shell 执行，`mapfile` 的赋值会丢失。

## glob 语义

`glob_to_ere` 输出锚定 ERE（`^...$`），对齐 pi-gate 的 `globToRegex`：

| glob           | ERE                 |
| -------------- | ------------------- |
| `*.lockfile`   | `^[^/]*\.lockfile$` |
| `dist/**`      | `^dist/.*$`         |
| `a?b`          | `^a[^/]b$`          |
| `**/*.so`      | `^.*[^/]*\.so$`     |
| `deep/**/file` | `^deep/.*file$`     |
| `a.b`          | `^a\.b$`            |

`**` 额外吞掉紧随其后的 `/`，因此 `**/*.so` 也能匹配根目录下的 `x.so`。`gate-core.sh` 在 `frozen_globs` 匹配时调用它：含 `/` 的 glob 对 git-root 相对物理路径 `RELP` 匹配，不含 `/` 的对 basename 匹配，且**仅在目标物理路径位于项目内（`INSP=1`）时生效**。

## 排障

- 看合并结果：`bash -c 'source ~/.config/agents/anchors-lib.sh && load_merged_anchors <dir>'`；加载失败会向 `~/.config/omp/extensions/.load-errors.log` 追加日志。
- 单条判定：`GATE_CWD=<dir> bash ~/.config/agents/gate-core.sh bash '<cmd>'`，直接看行协议输出；写入判定把待检内容接在 stdin 上跑 `edit <file>`。
- 「命令在禁用列表里却没被拦」：先确认是不是 §设计决策与不变量第 6 条列出的明确放弃形态，再确认冻结词是否落在命令位置。
- 「命令被误拦」：冻结匹配走的是剥引号后的片段流，引号内的 `;`、反斜杠都会变成边界；用上面的单条判定命令对比改前改后输出。
- 敏感模式明明存在却不命中：字符类里的 `\s` 被 GNU grep 当字面 `\` 与 `s` 处理，`[^"'\s]{8,}` 因此额外排除了值中的字母 `s`——写模式时用 `[^"'[:space:]]` 之类。
- 判定整体放行：`stat /run/agent-gate.off`，存在即全放行且 agent 侧无任何提示。
