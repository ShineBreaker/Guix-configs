# Pi Agent Local Setup

这是一个本地 Pi Agent 配置工程，目标是在 Pi v0.74.1 上复刻 `oh-my-openagent` 的核心工作流：角色化 subagent、按需 skills、工作流 prompt、上下文注入、模型路由、TODO 驱动续跑、模型 fallback、注释检查、会话恢复，以及 pi-lens / pi-hashline-edit 集成。

## 当前状态

- Pi 版本：`@earendil-works/pi-coding-agent@0.74.1`
- 配置目录：`agent/`
- 全局入口：`~/.pi/agent -> ~/.local/share/pi/agent`
- 启动脚本：`./run-pi.sh`
- 已安装包：`pi-lens@3.8.44`、`pi-hashline-edit@0.6.1`
- 默认模型：`opencode-go/deepseek-v4-flash`

## 目录结构

```text
.
├── PLAN.md
├── README.md
├── package.json
├── run-pi.sh
├── enter-fhs.sh
├── scripts/
│   └── read-crush-key.sh
└── agent/
    ├── settings.json
    ├── auth.json
    ├── models.json
    ├── AGENTS.md
    ├── agents/
    ├── extensions/
    ├── prompts/
    └── skills/
```

## Agent 角色

- `commander`：主编排，先做 IntentGate 分类，再决定短路或完整链路。
- `scout`：代码库搜索和外部文档检索。
- `advisor`：只读需求澄清和结构化规划。
- `artisan`：按明确计划执行代码修改。
- `inspector`：架构审查、缺口分析、计划门控。

## 扩展

- `subagent`：Pi 官方示例扩展的完整本地副本，支持 single / parallel / chain。
- `context-injector`：注入 `~/.agents/context/` 和项目上下文。
- `model-router`：按用户 prompt 做 IntentGate 风格模型路由。
- `todo-enforcer`：提供 `todo` 工具，扫描 `TODO.md`，在任务未完成时发出状态并可触发 follow-up。
- `model-fallback`：监听 transient provider response，按 `settings.json` fallback 链切换模型。
- `comment-checker`：检查 write/edit 结果中的低质量注释模式。
- `session-recovery`：遇到上下文/长度错误时触发 compaction，其他错误写入恢复标记。
- `ralph-loop`：通过 `/ralph` 和 `/cancel-ralph` 控制 TODO 驱动的续跑循环。

## Skills 和 Prompts

本地 skills：

- `start-work`
- `refactor`
- `review`
- `git-workflow`

本地 prompt templates：

- `/implement`
- `/scout-and-plan`
- `/implement-and-review`

## 使用方式

```bash
./run-pi.sh --version
./run-pi.sh
./run-pi.sh --offline --list-models deepseek
```

`run-pi.sh` 会把本地 `node_modules/.bin` 加入 `PATH`，并设置 `PI_CODING_AGENT_DIR` 指向本工程的 `agent/`。脚本支持复制、重命名或 symlink 到 `~/.local/bin`：它会优先使用 `PI_LOCAL_ROOT`，其次解析 symlink 目标目录，最后查找 `${XDG_DATA_HOME:-~/.local/share}/pi`。

如果后续把脚本复制到其他目录且本工程不在默认 XDG 位置，设置：

```bash
export PI_LOCAL_ROOT="$HOME/.local/share/pi"
```

## 验证命令

```bash
bun --check agent/extensions/**/*.ts
./run-pi.sh --version
./run-pi.sh list
./run-pi.sh --offline --list-models deepseek
```

资源加载检查：

```bash
bun -e 'import { DefaultResourceLoader, SettingsManager } from "@earendil-works/pi-coding-agent"; const cwd=process.cwd(); const agentDir=`${cwd}/agent`; const loader=new DefaultResourceLoader({cwd, agentDir, settingsManager: SettingsManager.create(cwd, agentDir)}); await loader.reload(); console.log(loader.getExtensions().errors, loader.getSkills().diagnostics, loader.getPrompts().diagnostics);'
```

期望结果：扩展错误、skill 诊断、prompt 诊断均为空。

## 说明

`enter-fhs.sh` 目前只是占位脚本。当前 Bun 和 Pi 能在现有环境直接运行，所以没有启用 FHS 包装。后续只有遇到原生依赖或动态链接问题时才需要补齐 FHS manifest。
