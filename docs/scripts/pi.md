<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# pi — Pi coding agent 启动 wrapper（含 pi-acp）

- 源码：`dotfiles/mutable/agents/pi/.local/bin/pi`、`pi-acp`
- 部署：`~/.local/bin/pi`、`~/.local/bin/pi-acp`（mutable，改源即时生效）
- 调用方：终端直接调用；ACP 宿主按命令名解析 `pi-acp`（经 `PI_ACP_PI_COMMAND` 指回 `~/.local/bin/pi`）

## 用法

```bash
pi [args...]     # bun 优先执行，缺 bun 退 node
pi-acp           # ACP 模式（exec pi 后由宿主 stdio 驱动）
```

## 依赖

`bun`（首选运行时；`PATH` → `~/.local/state/nix/profile/bin/bun` → `/run/current-system/profile/bin/bun` 顺序探测）、`node`（fallback）、`pnpm`（首装）。

## 工作原理

- **环境变量显式赋值**：`PI_HOME`/`PI_CODING_AGENT_DIR`/`PI_CONFIG_DIR`/`PI_CODING_AGENT_SESSION_DIR` 这组变量 pi 与 omp **同名同义地读**——残留的全局导出会把 pi 指到 omp 的配置目录，故脚本显式赋值而非继承。`PI_OFFLINE` 默认 1。`DEVIN_CLI` 兜底指向 nix profile 的 devin（pi-devin-local 插件按 KNOWN_BINS 硬编码找 devin，GUI 派生进程 PATH 也可能缺；插件对 `DEVIN_CLI` 只做 `existsSync`，指错时静默回退无副作用；外部 export 优先）。
- **Bun 入口**：npm 包的 node 入口（`dist/bundle/cli.js`）解析不了 `bun:` 内置模块，而扩展生态假定 Bun 运行时（atelier 直接 `import "bun:sqlite"`）。`dist/bun/cli.js` 是上游 `build:binary` 编译独立二进制用的 Bun 入口，用它跑等价于 nix 时代的 Bun 版 pi。缺 bun 或缺入口时打印告警退回 node，依赖 Bun 内置的扩展会加载失败。
- **首跑 bootstrap**：`BIN` 缺失时 `cd $PI_DATA_DIR && pnpm install`，再调同目录 `pi-update --extensions-only` 同步扩展清单（用 `readlink -f $0` 解 stow 软链找 pi-update）。

## 设计决策与不变量

- **bun 探测顺序固定**：PATH 优先（交互环境），nix profile 与 system profile 兜底（GUI/编辑器派生进程 PATH 不全）。
- `pi-acp` 保持一行 exec——**文件名不可改**（ACP 宿主按命令名寻址）；头部的约束来源说明须保留（`dotfiles/mutable/AGENTS.md` 的 *-acp 头注释规则）。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| atelier 等扩展加载失败（`bun:sqlite`） | 实际用了 node 入口 | 装 bun 或检查 Bun 入口文件是否存在 |
| pi 读到 omp 的配置 | 外部 export 的 `PI_*` 变量残留 | 本脚本已显式覆盖；检查上游调用方环境 |
| `pi --help` 挂起 | pi 无纯帮助路径 | 属预期，`tools.yaml` 的 `help_cmd` 不得为它登记 flag |

## 变更记录

无破坏性改动（本次重构只压缩注释）。
