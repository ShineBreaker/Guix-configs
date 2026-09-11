# agents/pi — Pi 编码 Agent 配置与部署

本包映射到 `$HOME`，经 GNU Stow 逐文件软链（`--no-folding`）。与 `omp` 不同，Pi **不由 nix 提供**：核心与扩展由 pnpm 自管理安装到 `~/.local/share/pi`，本包只托管入口 wrapper 与配置。

## 布局

| 路径                              | 说明                                                                       |
| --------------------------------- | -------------------------------------------------------------------------- |
| `.local/bin/pi`                   | 启动 wrapper：注入目录类环境变量，然后用 bun 跑 pi 的 Bun 入口             |
| `.local/bin/pi-acp`               | ACP 适配器（Zed 等），`PI_ACP_PI_COMMAND` 指回 `~/.local/bin/pi`           |
| `.local/bin/pi-update`            | 更新入口：settings.json → 扩展清单同步，`pnpm update --latest` 升核心与扩展 |
| `.local/share/pi/package.json`    | 核心依赖清单（`pi-update` 的派生产物，手改无效）                            |
| `.config/pi/`                     | agent dir：`settings.json`（含 `packages` 扩展清单）、`extensions/`、`npm/` |

运行时产物（`~/.local/share/pi/node_modules`、`pnpm-lock.yaml`、`atelier-registry.db`）生成在部署侧，不入源、不入 git。

## 关键约束

### 1. 必须用 Bun 运行时启动

扩展生态假定 Bun 运行时：`atelier` 直接 `import { Database } from "bun:sqlite"`。npm 包的默认 node 入口是 `dist/bundle/cli.js`，其中 `bun:` 内置模块无法解析，表现为启动即报 `Failed to load extension ... Cannot find module 'bun:sqlite'`。

wrapper 因此执行 `bun .../pi-coding-agent/dist/bun/cli.js`（上游 `build:binary` 编译独立二进制所用的 Bun 入口，等价于 nix 时代的 Pi Bun 二进制）。缺 bun 或缺该入口时 wrapper 会打印告警并退回 node；`pi-update` 结尾也会校验该入口存在，避免上游改布局后静默退化。

### 2. 目录类环境变量按 CLI 注入，不在 config.org 全局声明

`PI_CODING_AGENT_DIR` / `PI_CODING_AGENT_SESSION_DIR` 被 pi 与 omp **同名同义**读取，全局一套会让两者撞车（omp 首次启动还会把 pi 的 `settings.json` 改名 `.bak`）。现在 omp 由 nix wrapper 注入（见 `source/nix/configuration/programs/llm-agents.nix`），pi 由本包 wrapper 注入。wrapper 用显式赋值而非继承，以清掉残留的全局导出。

### 3. PATH 顺序：nix 侧不得再提供 pi

`~/.local/state/nix/profile/bin` 排在 `~/.local/bin` 之前。若 nix 侧重新加入 pi 包，会盖住自管理版本，且又退回 node 运行时。

### 4. 与 omp 共享自建扩展

自建扩展源在 `dotfiles/mutable/agents/extensions/<name>/`（无 `.stow-package` 标记，不单独部署）。两侧各放一个软链指向它：

```
.config/pi/extensions/<name>/index.ts   → ../../../../../extensions/<name>/index.ts
.config/omp/extensions/<name>/index.ts  → ../../../../../extensions/<name>/index.ts
```

第三方包（`atelier`、`pi-ui`）是各自的 git 子模块，只挂在 pi 侧。

## 验证

```bash
pi --version                      # 版本
pi -p "reply with exactly OK"     # 非交互跑通（应无扩展加载错误）
pi-update                         # 更新核心与扩展，结尾应打印 "Bun 入口: OK"
```

交互启动可看欢迎页的 `ext N ext` 计数是否为 6（atelier / pi-ui + 四个共享扩展）。
