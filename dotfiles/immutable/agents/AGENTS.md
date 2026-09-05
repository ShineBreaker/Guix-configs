# Agent 资产配置（Crush + 共享基础设施）

经 Guix Home（stow layout）部署到 `~/.config/`：`crush/` → Crush 配置 + hooks + bin；`agents/` → 共享基础设施（context 注入体系、anchors 拦截体系）。

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

## 三套共享系统：各管什么、改哪、怎么生效

四端（zcode / omp / crush / hermes）共享三套正交系统，处理三类不同时机的问题，同一条规则不要在多处重复维护：

| 系统 | 时机 | 管什么 | 内容源 | 改后生效 |
| --- | --- | --- | --- | --- |
| context | 会话启动注入 | 工作原则（跨域 + 领域） | `.config/agents/context/` + `context-select.sh` | immutable：blue home |
| anchors | 工具调用时拦截 | 冻结命令/路径、改写、提示 | `anchors.json` 两级 + `gate-core.sh` | immutable：blue home |
| skills | 按需加载 | 操作手册 / 工作流 | mutable `agents/skills/` 包（askill 管理） | Stow 直链：改源即生效 |

分工判据：**约束进 context**（启动即在场，靠 agent 自律）、**拦截进 anchors**（运行时硬挡，机器可判定的触发条件）、**手册进 skills**（用时才看）。写一条新规则前先按此归位——例如「禁止 rebuild」的拦截条件放 anchors（frozen_commands），背景解释放对应 skill 或仓库 AGENTS.md，不复制进 context。

## anchors — 运行时拦截

`anchors.json`（规则）+ `anchors-lib.sh`（协议无关的加载/合并库：分层 ratchet 合并，数组并集、映射近层覆盖远层）+ `gate-core.sh`（决策核：冻结命令归一化匹配、`--dry-run` 豁免仅限 blue 前缀、frozen_paths/globs、部署位置保护、敏感信息判定，以 stdout 行协议输出 `BLOCK`/`SENSITIVE`/`AUTO_ALLOW`/`REWRITTEN`/提示）。四方适配器（pi-gate TS、crush 两 bash hook、zcode 两 bash hook、hermes gate py 插件）**只做协议转换**——规则与判定语义双单一真相源，修一处四方同步生效。

**分层职责**：

- 全局 `~/.config/agents/anchors.json`（meta-frozen）：跨 workspace 通用约束——`sudo`、`interactive_commands`、`sensitive_patterns`
- 项目级 `<root>/.agents/anchors.json`（agent 可写，ratchet 加码）：仓库专属——`frozen_commands`/`frozen_paths`/`redirect_conventions`/`path_hints`/`human_only_actions` 等
- gate-core.sh 硬编（恒定生效）：rm 破坏性防护、git 写操作限制、`~/.config`/`~/.local` 部署位置保护、只读命令白名单

改通用约束→全局 anchors.json；改仓库规则→项目级；改判定语义→gate-core.sh。

## context — 会话上下文注入

内容三层（`.config/agents/context/`）+ 决策核 `context-select.sh`（同目录）：

- `00-core.md`：跨领域通用原则，四端恒注入
- `INDEX.md`：领域路由表（XML `<domain name file>`，只写「什么时候用哪个域文件」），恒注入
- `domains/<name>.md`：领域专用原则，按门控注入（现仅 `coding`，git 仓库内注入）

决策核持有唯一的注入映射表（`文件|门控`，门控可叠加：`always` / `git` / `platform:p1,p2`），四端适配器只做协议转换：zcode SessionStart hook、omp before_agent_start 扩展（每轮热更新）、hermes 插件（`--list-all` 注册全集 + render 按 session cwd 门控）、crush context_paths 静态恒注入集（域内容靠 INDEX 指引手动拉取）。

**日常操作**：

- 改通用原则 → 编辑 `00-core.md`（注意 hermes 系统提示词硬限：core + INDEX 合计 ≤5500 字符，超了先给内容减肥）
- 新增领域 → 三步联动：`domains/<name>.md` 建文件 + `context-select.sh` 映射表加一行 + `INDEX.md` 加 `<domain>` 条目；跑 `--check` 验证三向一致
- 部署前调试 → `CONTEXT_DIR` 指仓库源树 context 目录、`CONTEXT_SELECT_BIN` 指源树 selector（三端适配器同一约定），blue home 前即可全链路验证
- 断链自检 → `context-select.sh --check`：引用文件存在性、加域忘登记、INDEX 与 domains/ 目录不一致、crush context_paths 断链都会被抓出

## Skills — askill 声明式管理

askill 脚本本体由 `dotfiles/mutable/agents/skills/` 包部署（`.local/bin/askill`）；第三方 skills 锁真身也在该包（Stow 单文件直链 skills-lock.json，npx 写锁即写仓库源）：

- `askill add <repo> -s <name>` / `update` / `install` / `remove` / `list`
- 工作区 = 部署位 `~/.config/agents/skills/`（npx cwd；版本冻结由 git 提交承担）
- `~/.config/agents/skills/.agents/skills/` 是 npx 暂存区；锁外目录（自建 skill）不经 askill
- 已知坑：`heygen-com/hyperframes` 仓库过大，git clone 必被 TLS 掐断且 LFS 内容被剥离；用 `gh api repos/heygen-com/hyperframes/tarball/main` 解出 `skills/` 拷入暂存区再 `askill sync`
