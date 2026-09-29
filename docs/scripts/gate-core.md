<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# gate-core.sh — 五端共享的 gate 决策核（单一真相源）

- 源码：`dotfiles/immutable/agents/.config/agents/gate-core.sh`
- 部署：`~/.config/agents/gate-core.sh`（immutable，改后须 `blue home`）
- 调用方：各端 hook/扩展协议适配器——zcode `dotfiles/mutable/agents/zcode/.zcode/hooks/{bash,edit}-gate.sh`、crush `dotfiles/immutable/agents/.config/crush/hooks/{bash,edit}-gate.sh`、pi/omp `dotfiles/mutable/agents/extensions/pi-gate/index.ts`、hermes `dotfiles/mutable/agents/hermes/.local/share/hermes/plugins/gate/__init__.py`、DSH `dotfiles/mutable/agents/dsh/.local/share/dsh/profiles/agent-extensions/gate.js`
- 规则源：`anchors.json` 两级 ratchet 合并（由同目录 `anchors-lib.sh` 的 `load_merged_anchors` 加载；全局 `~/.config/agents/anchors.json` + 项目 `.agents/anchors.json`，见 [anchors-lib.md](anchors-lib.md)）

全部判定语义集中于此；五端适配器只做协议转换。**修改匹配逻辑前先通读 §设计决策与不变量**——每条不变量对应实现处都有一行注释指回本文件。

## 接口

### CLI 与输出协议

```bash
gate-core.sh bash <cmd>    # Bash 工具命令判定
gate-core.sh edit <file>   # 写入判定；待检内容从 stdin 读（可为空）
```

- stdout 行协议：每行 `TYPE<TAB>payload`；类型集固定为 `BLOCK` `SENSITIVE` `AUTO_ALLOW` `REWRITTEN` `NOTES` `RM_HINT` `REDIRECT` `HINT`。
  - `BLOCK` 硬拦截（payload 为理由）；`SENSITIVE` 敏感信息命中（crush 协议映射 exit 49）；`AUTO_ALLOW` 只读白名单命中（适配器可输出 auto-approve；pi 忽略）；`REWRITTEN` 改写后的命令（zcode 不支持改写，转提示）；`NOTES`/`RM_HINT`/`REDIRECT`/`HINT` 非阻塞提示。
- 决策退出码恒 0（进程级失败=异常，由适配器各自的 fail-closed 策略兜底）。未知子命令打 usage 到 stderr，exit 64。
- `bash` 模式把多个参数合并为一条命令（`"$*"`）；`edit` 只取第一个参数为路径。
- payload 内换行会被 `emit` 压成空格，保证一行一裁决。

### 环境变量

| 变量                  | 语义                                                                                     |
| --------------------- | ---------------------------------------------------------------------------------------- |
| `GATE_CWD`            | anchors 层级定位起点与 edit 的项目根判定基准（默认 `$PWD`）                                |
| `GATE_NO_WRITE_TOOLS` | `1` = 无写工具会话（由 DSH gate.js 按当前 agent 作用域检测后置位），只做输出降级，见不变量 |

### 人工总开关

`/run/agent-gate.off` 存在即 bash/edit 全部静默放行（不输出任何内容——暂停态对 agent 不可见，与护栏不存在时表现一致）。`/run` 为 root 拥有的 tmpfs，创建/删除须 sudo，而 sudo 对 agent 恒冻——agent 自己打不开这个开关；重启自动清空，天然临时。操作方式与约定见 `dotfiles/immutable/agents/AGENTS.md`。

## 依赖

`bash`、`jq`（读 anchors）、`awk`、`sed`、`grep`、`realpath`（无 realpath 时退化为 `readlink -f`）。故意 `set -uo pipefail` 不带 `-e`：单个检查工具异常（如 jq 输出非预期）不应中断后续检查。

## 工作原理

1. 启动：定位 `anchors-lib.sh`（部署位置优先，见 §部署形态约束），`load_merged_anchors "${GATE_CWD:-$PWD}"` 得合并规则 `MERGED`；加载失败回退内置 DEFAULT（仅 `sudo` 冻结）。
2. `bash` 判定流水线（顺序与早退语义不可变——每阶段命中并 emit → return 0 终止，未命中 → return 1 继续）：
   1. 人工总开关（存在即静默返回）
   2. `check_frozen_commands`：冻结命令（命令位置词序列匹配）+ `guix system` 宽匹配
   3. `check_interactive_commands`：交互式命令 + 裸 REPL
   4. `check_git_rules`：`git commit` 必须有 `-m`、禁 `git add -p`、禁 `git rebase -i`
   5. `check_readonly_whitelist`：只读白名单发 `AUTO_ALLOW`（位于全部硬拦截之后，不构成绕过）
   6. `apply_rewrites_and_hints`：命令改写 + `NOTES`/`REDIRECT` 非阻塞提示（无拦截语义，恒 return 0）
3. `edit` 判定流水线（同一阶段约定）：
   1. 人工总开关
   2. `check_meta_frozen`：全局 anchors.json 与 `_meta_frozen` 项目 anchors 禁改
   3. `check_frozen_paths`：冻结路径（逻辑/物理双查）
   4. `check_frozen_globs`：冻结 glob（含 `/` 的对 RELP 匹配，不含 `/` 的对 basename）
   5. `check_deployed_locations`：`~/.config/`、`~/.local/` 直改禁止（项目内豁免）
   6. `check_sensitive_and_hints`：stdin 敏感信息模式 + `path_hints` 软提示

## 设计决策与不变量

以下每条对应实现处有一行注释指回本节。**这是历史绕过教训的清单，改动前先读。**

### 1. 命令位置词序列匹配（冻结命令的核心判定）

冻结命令按「命令位置词序列」匹配：片段的第一个词，或 `;` `&` `|` `(` `)` `` ` ``、` -- `、换行之后的词。参数/字符串/heredoc 正文里的冻结词不再命中（误报主源：commit message、文档字符串）。配套归一化：

- 词序列匹配前剥引号，堵 `reb''uild` 类拆分（`_cmd_segments` 的 sed 管线剥 `'` `"` `\` 并压缩空白）。注意副作用：`git commit -m "a; sudo x"` 里引号内的 `;` 也会成为边界——这是可接受的保守方向（字符串宁可误拦不可漏拦；实测语料覆盖）。
- 片段首词 basename 归一化，堵 `/run/current-system/profile/bin/sudo` 类完整路径绕过（`/usr/bin/sudo vim`、`~/bin/sudo` 同判）。
- `FOO=/x sudo …` env 赋值前缀循环剥离后再判首词。
- 再执行通道（`sh`/`bash`/`dash`/`ash`/`env`/`nohup`/`xargs`/`ssh`/`parallel`/`find`/`exec`）的段内子串兜底堵引号包裹的间接执行：`sh -c 'sudo x'`、`xargs sudo`、`find . -exec sudo {} \;` 均命中。**已知缺口：`zsh`/`fish` 不在通道名单内，`zsh -c 'sudo x'` 不拦**——名单扩充须评估通道误报面，当前维持。
- `$(` 与 `` ` `` 视为命令边界，命令替换体内的冻结词照常命中。
- 解释器 heredoc（`bash <<EOF`、`sh -s <<X`、`python3 - <<PY`、`cat <<E | bash` 等，消费者取 `<<` 前最后一个非标志词判定）的正文会被执行，保留进片段流参与匹配；数据型消费者（`cat` 等）正文仍是纯数据，剔除。

### 2. 明确放弃的极端 case（不要「修复」）

- `$(printf %s su)do` 这类命令替换输出拼接成冻结词的形态：运行时才存在，静态可见即回全文子串=误报之源；系对抗性构造，非 agent 自然行为。
- 解释器语言代码内部动态拼接冻结词（`os.system("sudo …")` 类）同理不追。
- 大小写：`SUDO` 不命中（冻结词按 anchors 原文小写匹配）。
- 冻结词不在命令位置时：片段内非通道命令的中间词不拦（如 `watch sudo x`）。

### 3. 人工总开关只认固定路径

`/run/agent-gate.off`：存在即静默放行，不输出任何内容（暂停态对 agent 不可见，与护栏不存在时表现一致）。只认该路径，不认环境变量改道——agent 可写的位置放同名文件一律无效；该文件只能人工 sudo 创建/删除。各适配器同样硬编此路径。

### 4. 预演豁免是片段级的

仅剔除「blue 前缀且带 `--dry-run`」或「just 前缀且带非空 `dry=` 参数」的片段，其余片段照常检查：

- `blue --dry-run rebuild; sudo x` 的 sudo 片段不被连带豁免。
- `sudo ... --dry-run` 这类把 `--dry-run` 当免死金牌的不豁免（首词不是 blue/just）。
- `just dry= rebuild`（空值）不豁免——要求 `dry=` 后紧跟非空白内容。

### 5. `GATE_NO_WRITE_TOOLS=1` 只做输出降级

无写工具会话标记（由 DSH gate.js 在 pre-execute 检测当前 agent 作用域无 write/edit 工具时置位，simple-mode 一类 preset 只有持久 bash）。此时 `redirect_conventions` 的替代提示（引导「改用 Edit 工具」）不可执行，故降级输出：BLOCK 不附 ALT（回落通用冻结理由）、interactive 去「请使用对应工具」尾巴、`NOTES`/`REDIRECT` 软提示整条抑制；硬拦截、`AUTO_ALLOW`、`REWRITTEN` 一概不变——降级只收窄输出，不制造任何放行面。其他端不设该变量，行为零变化。

### 6. edit 走双路径（逻辑 + 物理）

`resolve_path` 的两种模式缺一不可：

- 逻辑路径（`realpath -ms`，不解析 symlink）做 meta-frozen / 部署位置检查——`~/.config` 下大量路径是 store 软链，物理解析会让这两类保护落空。
- 物理路径（`realpath -mP`，解析 symlink）做 frozen_paths / frozen_globs——防经 `/tmp` 等中转软链写入冻结目标。

任一路径命中即拦。`frozen_paths` 相对条目是子串/前缀混合判定（git-root 相对前缀 OR 任意路径后缀，如 `channel.lock` 按 basename 等值）。

### 7. 词法类检查只对原始命令精确匹配

交互式命令、`git` 规则、rm 提示、只读白名单对原始命令文本做精确匹配，不做归一化——避免 `echo "vim tips"` 这类字符串内容被误拦（`vim` 前是 `"`，不在命令边界字符集 `(^|[;&|()$]|&&|\|\|)` 内）。`git add -p`、`git rebase -i` 的 `-p`/`-i` 是「词边界短选项」匹配，`--patch`/`--interactive` 长选项不命中（已知行为）。白名单只对无连接符（`;` `&` `|` `` ` `` `$(`）的单条命令发 AUTO_ALLOW，搭车形态回落默认确认流。

### 8. `unless_inside` 条件豁免

`frozen_paths` 条目与 `_meta_frozen` 支持对象形式 `{"path": ..., "unless_inside": "<dir>"}` / `{"unless_inside": "<dir>"}`：cwd（`GATE_CWD`）位于 dir 内时该条目不拦（决策核仓库内的会话可维护自己的规则源）。逐条目判定——近层加无条件条目即可恢复拦截（ratchet 只加不减不变）；豁免只能由人工维护的规则源声明，且 cwd 之外的会话仍被同一条目拦住。`cwd_under` 做物理解析，防 cwd 经软链指向目标目录误判。

### 9. `guix system` 宽匹配

冻结命令词序列之外还有一条子串级防线：命令文本（豁免片段剔除后）含 `guix` 且含 `system reconfigure|init` 即拦——专为 `guix time-machine -- … -- system reconfigure` 这类包装形态（` -- ` 把 `system reconfigure` 切成独立片段，词序列匹配够不到 `guix`）。副作用：`echo guix system reconfigure` 也会被拦，属可接受的保守方向。

### 10. 部署形态约束（lib 定位）

`anchors-lib.sh` 定位顺序：`$HOME/.config/agents/anchors-lib.sh` 优先，`dirname $0` 同目录兜底——home-dotfiles 把每个文件复制成**独立** store 项，gate-core.sh 与 anchors-lib.sh 不在同一 store 目录，同目录查找在部署形态下必然落空；源码树/直链场景才用同目录。anchors 加载/合并失败一律回退内置 DEFAULT（仅 `sudo` 冻结）——hook 不因配置损坏整体失效。

## 故障排查

- 判定全靠 `$MERGED`：先用 `context-select.sh --check` 式的自检思路确认规则源——`bash -c 'source ~/.config/agents/anchors-lib.sh && load_merged_anchors <dir>'` 可直接看合并结果；加载失败会写 `~/.config/omp/extensions/.load-errors.log`。
- 单条命令的判定可直接跑：`GATE_CWD=<dir> bash ~/.config/agents/gate-core.sh bash '<cmd>'`，看行协议输出。
- 暂停排查：确认 `/run/agent-gate.off` 是否存在（存在即全放行，agent 侧无任何提示）。

## 变更记录

- 2026-10：重构——长文件头与全部设计理由迁入本文档 §设计决策与不变量（原文未删改），代码注释压缩为不变量单行指引；`set -uo pipefail`、CLI、行协议、匹配语义、退出行为全部不变（311 例语料矩阵验证，输出逐字节一致）。行为变化为零。
