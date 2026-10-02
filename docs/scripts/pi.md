<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# pi — Pi 编码 Agent 的启动与更新入口（pi / pi-acp / pi-update）

源码 `dotfiles/mutable/agents/pi/.local/bin/{pi,pi-acp,pi-update}` · 部署 `~/.local/bin/pi`、`~/.local/bin/pi-acp`、`~/.local/bin/pi-update`（mutable，改源即时生效） · 调用方：终端手动调用；ACP 宿主（Zed 等）按命令名寻址 `pi-acp`；`pi` 首跑 bootstrap 时以 `--extensions-only` 调 `pi-update`

三个入口共用一份 pnpm 安装树与同一组 `PI_*` 约定：`pi` 与 `pi-acp` 固定环境变量并选运行时，`pi-update` 升级核心与扩展并把派生产物回源。依赖 `pnpm`（安装与升级）、`node`（版本探测、配置解析）、`bun`（首选运行时，缺失退 node）。

## 布局

| 路径                                                 | 说明                                                                                                                                                |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `$AGENTS_ROOT/pi`（默认 `~/.local/share/agents/pi`） | 安装根：核心包 pnpm 项目。`package.json`、`pnpm-lock.yaml` 是部署侧产物，由 `pi-update` 回源到 `dotfiles/mutable/agents/pi/.local/share/agents/pi/` |
| `~/.local/share/pi`                                  | 数据根，只留 `sessions/` 等运行时数据，由 `PI_LOCAL_ROOT` 管                                                                                        |
| `~/.config/pi/`                                      | 配置根：`settings.json`（扩展清单真源）、`extensions/`（自建扩展软链）、`npm/`（扩展 pnpm 项目）                                                    |
| `$PI_DATA_DIR/node_modules/.bin/pi-acp`              | `pi-acp` 的 CLI 解析路径仍按数据根推导（`pi-acp:23`），与 `pi` 的安装根不同                                                                         |

数据侧产物（`sessions/`、`atelier-registry.db`）不入源、不入 git。

## pi 与 pi-acp

```bash
pi [args...]   # bun 跑 Bun 入口；缺 bun 打印告警后退 node 入口
pi-acp         # ACP 模式（exec pi 后由宿主 stdio 驱动）
```

- **必须跑 Bun 入口**：入口固定为 `<安装根>/node_modules/@earendil-works/pi-coding-agent/dist/bun/cli.js`，不是 npm 包的 node 入口——扩展生态假定 Bun 运行时（atelier 直接 `import { Database } from "bun:sqlite"`，node 解析不了），该文件正是上游 `build:binary` 编译独立二进制所用的入口。缺 bun 或缺该文件时打印告警退 node，依赖 Bun 内置模块的扩展加载失败（`pi -ne` 可临时跳过扩展）。
- **bun 探测顺序固定**：`PATH` → `~/.local/state/nix/profile/bin/bun` → `/run/current-system/profile/bin/bun`。GUI 与编辑器派生进程的 PATH 不含 nix profile，后两条是兜底。
- **`PI_*` 显式赋值而非继承**：`PI_HOME`、`PI_CODING_AGENT_DIR`、`PI_CONFIG_DIR`（`.config/pi`）、`PI_CODING_AGENT_SESSION_DIR`（`$PI_DATA_DIR/sessions`）、`PI_OFFLINE`（默认 `1`）；`pi-acp` 另设 `PI_ACP_PI_COMMAND`（默认 `~/.local/bin/pi`）。这组变量 pi 与 omp 同名同义，残留的全局导出会把 pi 指到 omp 的配置目录。`DEVIN_CLI` 只做兜底默认、外部 export 优先，`pi-devin-local` 对它只做 `existsSync`，指错无害。
- **首跑 bootstrap**：CLI 缺失时 `cd $PI_PROJ_DIR && pnpm install`，随后调同目录的 `pi-update --extensions-only`。定位 pi-update 必须 `readlink -f $0`——stow 软链下 `$0` 可能是 symlink。
- **`pi-acp` 文件名不可改**：ACP 宿主按命令名寻址 agent，头注释须写明约束来源（准入规则见 `dotfiles/mutable/AGENTS.md`）。

## pi-update

```bash
pi-update                    # 更新核心 + 同步扩展 + native rebuild + Bun 入口校验
pi-update --extensions-only  # 只装扩展（pi 首跑调用路径），跳过核心更新与 native rebuild
```

流程：核心未装则先 `CI=true pnpm install --no-frozen-lockfile` → 非 `--extensions-only` 时 `pnpm update --latest` 升核心 → 按 `settings.json` 同步扩展清单 → `pnpm update --latest` 升扩展 → 非 `--extensions-only` 时 rebuild native → `sync_core_to_source` 回源 → 打印版本与 Bun 入口校验，有失败包则退出码 1。

- **扩展清单的单一真相源是 `settings.json` 的 `packages`**：取其中 `npm:` 前缀条目与 `~/.config/pi/npm/package.json` 求差集后 `pnpm add` / `pnpm remove`；后者是派生产物，手改无效。`@earendil-works/*` 与 `PROTECTED_PKGS`（`pi-subagents`）在 settings 未列出时也不自动移除。
- **`pnpm update --latest` 必须带 `--latest`**：不带只在 semver range 内更新。
- **`nodeLinker: hoisted` 是硬要求**：jiti 从 symlink 路径解析模块时找不到扩展的传递依赖（如 `@ff-labs/pi-fff` → `@ff-labs/fff-node`）。pnpm 10+ 的项目级配置在 `pnpm-workspace.yaml`，`package.json` 的 `pnpm` 字段已废弃、脚本每次运行顺手删。
- **`minimumReleaseAge: 0` 关闭 pnpm 12 的 24h 供应链冷却**：pi 与插件是日更 preview 版本，冷却期内发布的版本被**静默**排除出解析，表现就是「更新跑完版本不动」。核心目录与扩展目录两个 `pnpm-workspace.yaml` 都写这一项。
- **`ERR_PNPM_IGNORED_BUILDS` 自动批准后重试一次**：从 pnpm 输出的 `Ignored build scripts:` 行解析包名写入 `allowBuilds: true`，再重跑一次 `pnpm update --latest`；仍失败才走 lockfile 兜底（删 `pnpm-lock.yaml` 后 `CI=true pnpm install --no-frozen-lockfile`）。
- **`sync_core_to_source` 回源**：`package.json` 与 `pnpm-lock.yaml` 是部署侧产物（`pnpm update --latest` 就地覆写，还会把 stow 软链原子写成实体文件），收尾把两者同步回仓库源——`package.json` 拷内容并重建软链，lockfile 只回拷内容（pnpm 拒写软链 lockfile，仓库副本经 `.stow-local-ignore` 防误链），`cmp` 有差才动。位置在 FAILED 汇总之前（native rebuild 失败也照常回源），`--extensions-only` 也跑（覆盖 wrapper 首装的 `pnpm install`）。通用配方见 `dotfiles/mutable/AGENTS.md`「新增 pnpm 系 agent 的完整配方」。
- **native 与保护名单**：`NATIVE_PKGS`（`better-sqlite3`）逐一 `pnpm rebuild` 并检查 `.node` 产物，通配同时覆盖 hoisted 与 `.pnpm/` isolated 布局；prebuilt 平台包（如 koffi）无需 rebuild。

## 实现与约束

- **`FAILED` 数组顶层声明**：`--extensions-only` 跳过 native rebuild 时，`set -u` 下 `${#FAILED[@]}` 仍安全，不可挪进函数。
- **`pnpm_workspace_policy` 合并而非重写**：`pnpm-workspace.yaml` 由脚本与 pnpm 共管（pnpm 自己写入 `minimumReleaseAgeExclude` 等键），只改写指定标量键与 `allowBuilds` 段，未知顶层键原样保留。
- **三参数一律显式传全**：形如 `<pnpm-workspace.yaml> <pnpm 输出或空串> <scalars JSON>`，不能用 `${3:-{}}` 这类默认值——花括号会被 bash 提前闭合。
- **结尾校验 Bun 入口**：检查 `dist/bun/cli.js` 存在与否，防止上游改 dist 布局后静默退化到 node。

## 排障

| 现象                                              | 原因                                       | 处理                                                          |
| ------------------------------------------------- | ------------------------------------------ | ------------------------------------------------------------- |
| 扩展加载失败（`Cannot find module 'bun:sqlite'`） | 实际走了 node 入口                         | 装 bun，或确认 `dist/bun/cli.js` 存在                         |
| pi 读到 omp 的配置                                | 调用方环境残留 `PI_*` 导出                 | 检查上游进程的导出（本脚本已显式覆盖）                        |
| 更新跑完但版本没变                                | pnpm 12 的 24h 冷却静默排除新版本          | 确认 `pnpm-workspace.yaml` 有 `minimumReleaseAge: 0`          |
| 报 `ERR_PNPM_IGNORED_BUILDS`                      | 依赖 build scripts 未审批，native 产物缺失 | 脚本自动批准并重试；手工等价物是 `pnpm approve-builds`        |
| `pnpm update` 反复失败                            | lockfile 损坏或 store 冲突                 | 脚本自动删 lockfile 重装；仍败则手工删安装树的 `node_modules` |
| `pi-acp` 报 CLI 缺失                              | 它按数据根解析，与安装根不一致             | 核对 `$PI_DATA_DIR/node_modules/.bin/pi-acp` 是否存在         |
| `pi --help` 挂起                                  | pi 没有纯帮助路径，会进入交互              | 属预期；`tools.yaml` 的 `help_cmd` 白名单不得为它登记         |

## 变更

- 安装树从 `~/.local/share/pi` 迁至 `$AGENTS_ROOT/pi`，数据侧不动：`pi` 与 `pi-update` 的路径改由 `AGENTS_ROOT` 推导，`PI_LOCAL_ROOT` 只管数据根；`pi-acp` 的 CLI 路径仍按数据根解析（见「布局」）。
