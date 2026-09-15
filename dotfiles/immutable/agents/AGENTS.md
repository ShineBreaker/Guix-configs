# Agent 资产配置（Crush + 跨 Agent 共享基础设施）

本目录通过 Guix Home（stow 布局）部署到 `~/.config/`：

- `crush/`：Crush Agent 的配置、hooks 与脚本。
- `agents/`：跨 Agent 共享基础设施（Context 注入体系、Anchors 工具调用拦截体系）。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
agents/
├── .config/
│   ├── agents/
│   └── crush/
└── .gitignore
```

<!-- /structor -->

## 三套共享系统：分工与生效时机

各 Agent 运行时（ZCode / OMP / Crush / Hermes / Pi）共享三套正交系统。为避免规则重复维护，遵循以下归位判据：

| 系统        | 介入时机       | 负责范围                                | 内容源                                          | 改后生效方式              |
| ----------- | -------------- | --------------------------------------- | ----------------------------------------------- | ------------------------- |
| **Context** | 会话启动时注入 | 通用与领域工作原则（靠 Agent 自律）     | `.config/agents/context/` + `context-select.sh` | Immutable：须 `blue home` |
| **Anchors** | 工具调用时拦截 | 冻结命令/路径、改写、提示（机器硬拦截） | `anchors.json`（两级）+ `gate-core.sh`          | Immutable：须 `blue home` |
| **Skills**  | 会话中按需加载 | 具体操作手册与工作流（查阅执行）        | Mutable `agents/skills/`（askill 管理）         | Stow 直链：改源即时生效   |

> **分工判据示例**：「禁止执行 rebuild」——机器拦截条件放入 Anchors（`frozen_commands`），背景与操作说明放入对应 Skill 或仓库 `AGENTS.md`，无需冗余复制到 Context。

## Anchors — 运行时工具调用拦截

Anchors 由 `anchors.json`（规则集）、`anchors-lib.sh`（分层加载与 Ratchet 合并库）和 `gate-core.sh`（决策核心）构成。各端适配器（Pi-Gate TS、Crush bash hooks、ZCode bash hooks、Hermes gate 插件）仅负责协议转换，决策逻辑在 `gate-core.sh` 集中判定。

### 规则分层

1. **全局配置**（`~/.config/agents/anchors.json`）：跨工作区通用约束，如 `sudo`、交互式命令限制、敏感信息模式等。
2. **项目级配置**（`<root>/.agents/anchors.json`）：仓库专属规则，如 `frozen_commands`、`frozen_paths`、`redirect_conventions`、`path_hints` 等。
3. **内核硬编规则**（`gate-core.sh`）：`rm` 破坏性防护、Git 写操作防护、`~/.config`/`~/.local` 部署目录只读保护。

**修改指引**：修改通用约束改全局 `anchors.json`；修改项目规则改项目级 `anchors.json`；修改判定语义改 `gate-core.sh`。

### 人工总开关（临时手动暂停护栏）

开关文件固定为 `/run/agent-gate.off`：存在即各端全部放行（仅附提示），删除即恢复拦截。`/run` 为 root 拥有的 tmpfs，创建与删除须提权，而提权命令对 agent 恒冻，因此 agent 自己打不开这个开关；重启自动清空，天然临时。

- 暂停：`sudo touch /run/agent-gate.off`；恢复：`sudo rm -f /run/agent-gate.off`；查看状态：`stat /run/agent-gate.off`（存在即暂停中）。
- 暂停与恢复均由人工在终端执行：agent 不得代劳，不得主动要求用户关闭护栏，也不得创建、删除或改道该开关文件（开关只认固定路径）。
- 新会话的 SessionStart 摘要会标明当前是暂停态还是拦截态，避免 agent 误判。
- 暂停期间的放行操作仍须在回复中如实说明。

## Context — 会话上下文注入

Context 内容分为三层（位于 `.config/agents/context/`），由 `context-select.sh` 决策注入：

- `00-core.md`：跨领域通用原则，各端恒定注入。
- `INDEX.md`：领域路由表（XML 格式），指引 Agent 何时读取哪个领域文件。
- `domains/<name>.md`：领域专属原则，按门控条件按需注入（如 `coding` 仅在 Git 仓库内注入）。

### 日常维护操作

- **修改通用原则**：编辑 `00-core.md`（注意字符限制：`core` + `INDEX` 合计需 ≤5500 字符，超限须精简）。
- **新增领域文件**：在 `domains/<name>.md` 创建文件 → 在 `context-select.sh` 映射表中添加门控规则 → 在 `INDEX.md` 添加 `<domain>` 路由条目。
- **一致性自检**：运行 `context-select.sh --check`，自动检测文件引用完整性及 INDEX 与 domains/ 目录的一致性。
- **本地调试**：设置环境变量 `CONTEXT_DIR` 与 `CONTEXT_SELECT_BIN` 指向仓库源码目录，可在 `blue home` 部署前完成全链路验证。

## Skills — 声明式技能管理（askill）

`askill` CLI 脚本由 `dotfiles/mutable/agents/skills/` 包部署（`.local/bin/askill`），第三方 Skill 的版本锁 `skills-lock.json` 也直链自该包：

- **常用命令**：`askill add <repo> -s <name>` / `update` / `install` / `remove` / `list`。
- **工作区路径**：位于 `~/.config/agents/skills/`，版本冻结由 Git 提交保证。
- **自建技能**：直接在 `~/.config/agents/skills/` 下维护，不经 `askill` 锁管理。
