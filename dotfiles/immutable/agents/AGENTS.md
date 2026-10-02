# Agent 共享基础设施

本目录部署到 `~/.config/agents/`，是 Pi / ZCode / Hermes / DSH 四端 Agent 运行时共用两套正交系统的源码：会话启动时注入的 **Context** 与工具调用时机器硬拦截的 **Anchors**。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
agents/
├── .config/
│   └── agents/
└── .gitignore
```

<!-- /structor -->

## 关键约定

### 三套系统的归位判据

Context、Anchors、Skills 正交，同一条规则只应维护在一处：

| 系统        | 介入时机       | 负责范围                                | 内容源                                                      | 改后生效                |
| ----------- | -------------- | --------------------------------------- | ----------------------------------------------------------- | ----------------------- |
| **Context** | 会话启动时注入 | 通用与领域工作原则（靠 agent 自律）     | `.config/agents/context/` + `context-select.sh`             | `blue home`             |
| **Anchors** | 工具调用时拦截 | 冻结命令/路径、改写、提示（机器硬拦截） | `anchors.json`（两级）+ `gate-core.sh`                      | `blue home`             |
| **Skills**  | 会话中按需加载 | 操作手册与工作流（查阅执行）            | mutable 包 `dotfiles/mutable/agents/skills/`（askill 管理） | Stow 直链，改源即时生效 |

判据示例：「禁止执行 rebuild」——机器拦截条件进 Anchors 的 `frozen_commands`，背景与操作说明进对应 Skill 或仓库 `AGENTS.md`，两者都不复制进 Context。

### Anchors — 运行时工具调用拦截

`anchors.json`（规则集）、`anchors-lib.sh`（分层加载与 Ratchet 合并）、`gate-core.sh`（决策核心）构成拦截内核；四端适配器（pi-gate TS、zcode bash hooks、hermes gate 插件、DSH `gate.js`）只做协议转换，决策一律集中在 `gate-core.sh`，不得在适配器里复刻判定。

规则分三层，改哪层就动哪个文件：全局 `~/.config/agents/anchors.json` 放跨工作区通用约束（sudo、交互式命令限制、敏感信息模式）；项目级 `<root>/.agents/anchors.json` 放仓库专属规则（`frozen_commands`、`frozen_paths`、`redirect_conventions`、`path_hints`）；内核硬编规则在 `gate-core.sh`（`rm` 破坏性防护、Git 写操作防护、`~/.config`/`~/.local` 部署目录只读保护）。

**改内核的约束**：`gate-core.sh` 与 `anchors-lib.sh` 是四端共用的安全边界，CLI、环境变量、`/run/agent-gate.off` 路径与 stdout 行协议一律不变。改判定逻辑前先建用例语料覆盖 `docs/scripts/gate-core.md` 的每一条不变量（命中与未命中都要有），新旧版本在临时 `HOME` 下逐条对比输出一致才算完成，方法见 `docs/scripts/CONVENTIONS.md` §7。

**人工总开关**：`/run/agent-gate.off` 存在即四端全部放行（静默，不向 agent 发任何暂停提示，与护栏不存在时表现一致），删除即恢复拦截。`/run` 是 root 拥有的 tmpfs，创建与删除都需提权，而提权命令对 agent 恒冻，所以 agent 自己打不开这个开关；重启自动清空，天然临时。暂停 `sudo touch /run/agent-gate.off`，恢复 `sudo rm -f /run/agent-gate.off`，查状态 `stat /run/agent-gate.off`。开关只认固定路径且必须由人工在终端执行：agent 不得代劳、不得主动要求用户关闭护栏、不得创建、删除或改道该文件。

**无写工具会话降级**：DSH 的 `simple-mode` 一类 preset 工具面只有持久 bash、没有 write/edit 工具，而 `redirect_conventions` 的拦截理由引导「改用 Edit 工具」，会让模型反复调用不存在的工具而死锁。`gate-core.sh` 识别环境变量 `GATE_NO_WRITE_TOOLS=1`（由 DSH 的 `gate.js` 按当前 agent 作用域检测写工具可见性后设置）：BLOCK 不附 redirect ALT（回落通用冻结理由）、interactive 去掉「请使用对应工具」尾巴、NOTES/REDIRECT 软提示抑制；硬拦截、AUTO_ALLOW、REWRITTEN 一概不变——降级只收窄输出，不制造放行面。Pi/ZCode/Hermes 不设该变量，行为零变化。

参考文档：判定语义、行协议、全部安全不变量与 anchors 分层合并语义见 `docs/scripts/gate-core.md`；注入决策见 `docs/scripts/context-select.md`；zcode hook 协议见 `docs/scripts/zcode-hooks.md`。

### Context — 会话上下文注入

`context-select.sh` 决策注入 `.config/agents/context/` 下三层：`00-core.md` 为跨领域通用原则（各端恒定注入）、`INDEX.md` 为领域路由表（指引 agent 何时读哪个领域文件）、`domains/<name>.md` 为领域专属原则（按门控条件按需注入，如 `coding` 仅在 Git 仓库内注入）。

维护操作：改通用原则编辑 `00-core.md`（`core` 与 `INDEX` 合计须 ≤5500 字符，超限即精简）；新增领域文件则依次在 `domains/<name>.md` 建文件、在 `context-select.sh` 映射表加门控规则、在 `INDEX.md` 加 `<domain>` 路由条目；一致性自检跑 `context-select.sh --check`（检测文件引用完整性与 INDEX 和 `domains/` 的一致性）；本地调试设 `CONTEXT_DIR` 与 `CONTEXT_SELECT_BIN` 指向仓库源码，可在 `blue home` 部署前跑通全链路。

### Skills — 声明式技能管理（askill）

`askill` CLI（`~/.local/bin/askill`）与第三方 Skill 的版本锁 `skills-lock.json` 都由 mutable 包 `dotfiles/mutable/agents/skills/` 直链部署，改源即时生效；工作区 `~/.config/agents/skills/` 的版本冻结由 Git 提交保证。常用命令 `askill add <repo> -s <name>` / `update` / `install` / `remove` / `list`；自建技能直接在 `~/.config/agents/skills/` 下维护，不经 `askill` 锁管理。

## 修改与生效

- **Context 与 Anchors 的源在本目录（immutable）**：改后必须 `blue home` 重建（部署进 Store 只读副本），四端才会用上新版本。适配器本身（pi-gate TS、zcode hooks、hermes 插件、DSH 扩展）在 mutable 包里，改源即时生效，但它们运行时加载的是 `~/.config/agents/` 下的已部署版本。
