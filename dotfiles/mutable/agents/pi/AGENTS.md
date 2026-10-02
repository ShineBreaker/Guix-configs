# agents/pi — Pi 编码 Agent 配置与部署

本包映射到 `$HOME`，经 GNU Stow 逐文件软链（`--no-folding`），改源即时生效。与 `omp` 不同，Pi **不由 nix 提供**：核心与扩展由 pnpm 自管理。本包只托管三个入口 wrapper 与配置层。

本篇讲**包内布局与约束**。三个入口的命令、旗标与环境变量细节见 [docs/scripts/pi.md](../../../../docs/scripts/pi.md)：启动侧见 §pi 与 pi-acp，更新侧见 §pi-update。

## 布局

| 路径                                           | 归属                     | 说明                                                                                           |
| ---------------------------------------------- | ------------------------ | ---------------------------------------------------------------------------------------------- |
| `.local/bin/pi`                                | 包内入口                 | 注入目录类环境变量后用 bun 跑 Bun 入口（缺 bun 退 node）                                       |
| `.local/bin/pi-acp`                            | 包内入口                 | ACP 适配器（Zed 等按命令名寻址），`PI_ACP_PI_COMMAND` 指回 `~/.local/bin/pi`；自动豁免准入规则 |
| `.local/bin/pi-update`                         | 包内入口                 | 更新核心与扩展；`.bin-entries-allow` 声明的例外入口（见下）                                    |
| `.local/share/agents/pi/package.json`          | 部署侧产物的**回源副本** | `pi-update` 的派生产物，**手改无效**                                                           |
| `.local/share/agents/pi/pnpm-lock.yaml`        | 部署侧产物的**回源副本** | lockfile 回源记录（stow ignore 不链出，`pi-update` 每次更新后同步）                            |
| `.config/pi/`                                  | 包内配置层               | `settings.json`（扩展清单真源）、`keybindings.json`、`models.json`、`extensions/`、`npm/`      |
| `~/.local/share/agents/pi/node_modules/`       | 纯部署侧                 | 不入源、不入 git                                                                               |
| `~/.local/share/agents/pi/pnpm-workspace.yaml` | 纯部署侧                 | 由 `pi-update` 与 pnpm 共管，不入源                                                            |
| `~/.local/share/pi/`                           | 纯部署侧                 | 只留 `sessions/`、`atelier-registry.db` 等运行时数据                                           |

三处根分工固定：**配置根 `~/.config/pi`（`PI_HOME`）/ 安装根 `$AGENTS_ROOT/pi`（pnpm 项目）/ 数据根 `~/.local/share/pi`（`PI_LOCAL_ROOT`）**。注意 `pi-acp` 的 CLI 解析路径仍按数据根推导，与 `pi` 的安装根不同——两份 wrapper 里的推导路径不一样不是笔误。

## 关键约束

### 1. 必须用 Bun 运行时启动

扩展生态假定 Bun 运行时：`atelier` 直接 `import { Database } from "bun:sqlite"`，而 npm 包的默认 node 入口 `dist/bundle/cli.js` 解析不了 `bun:` 内置模块，表现为启动即报 `Failed to load extension ... Cannot find module 'bun:sqlite'`。wrapper 因此走 `dist/bun/cli.js`（上游 `build:binary` 编译独立二进制所用的同一个入口）。缺 bun 或缺该入口时只打印告警退 node，**降级是静默的能力损失**：依赖 Bun 内置模块的扩展全部加载失败。`pi-update` 结尾会校验该入口存在，防止上游改 dist 布局后无声退化。

### 2. 目录类环境变量按 CLI 注入，不在 `config.org` 全局声明

`PI_CODING_AGENT_DIR` / `PI_CODING_AGENT_SESSION_DIR` 被 pi 与 omp **同名同义**读取，全局一套会让两者撞车（omp 首次启动还会把 pi 的 `settings.json` 改名 `.bak`）。omp 侧由 nix wrapper 注入（见 `source/nix/configuration/programs/llm-agents.nix`），pi 侧由本包 wrapper 注入。wrapper 用**显式赋值**而非继承，以清掉残留的全局导出。

### 3. PATH 顺序：nix 侧不得再提供 pi

`~/.local/state/nix/profile/bin` 排在 `~/.local/bin` 之前。若 nix 侧重新加入 pi 包，会盖住自管理版本，且又退回 node 运行时。

### 4. 与 omp 共享自建扩展

自建扩展源在 `dotfiles/mutable/agents/extensions/<name>/`（无 `.stow-package` 标记，不单独部署）。两侧各放一个软链指向它：

```
.config/pi/extensions/<name>/index.ts   → ../../../../../extensions/<name>/index.ts
.config/omp/extensions/<name>/index.ts  → ../../../../../extensions/<name>/index.ts
```

第三方包（`atelier`、`pi-ui`）是各自的 git 子模块，只挂在 pi 侧。

### 5. `pi-update` 是包内第二入口（准入规则例外）

上游原生有 `pi update`，语义与本包的 pnpm 布局实现不同、**不可遮蔽**，故保留独立入口并在包根 `.bin-entries-allow` 声明理由。改这个文件时理由不可删（`toolbox check` 阻断级执法，见 `dotfiles/mutable/AGENTS.md` 的「`.local/bin` 入口准入规则」）。

### 6. 核心包版本必须回源，不允许只活在部署侧

`package.json` 与 `pnpm-lock.yaml` 是 `pi-update` 的派生产物：`pnpm update --latest` 就地覆写部署侧文件，还会把 stow 软链原子写成真实文件。`sync_core_to_source` 在每次 `pi-update` 收尾（含 `--extensions-only`）同步回仓库源并重建软链。**若在部署侧裸跑 pnpm（不走 `pi-update`），之后必须补跑一次 `pi-update --extensions-only` 回源**，否则仓库副本停在旧版本，下次全新部署直接装回旧版（曾停在 0.85.1 而部署侧已 0.99.1）。

## 验证

```bash
pi --version                      # 版本
pi -p "reply with exactly OK"     # 非交互跑通（应无扩展加载错误）
pi-update                         # 更新核心与扩展，结尾应打印 "Bun 入口: OK"
```

交互启动可看欢迎页的 `ext N ext` 计数是否为 6（atelier / pi-ui + 四个共享扩展）。
