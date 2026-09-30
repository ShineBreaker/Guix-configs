<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# pi-update — Pi 核心 + 扩展更新

- 源码：`dotfiles/mutable/agents/pi/.local/bin/pi-update`
- 部署：`~/.local/bin/pi-update`（mutable，改源即时生效；在 `.bin-entries-allow` 中声明为包内第二入口）
- 调用方：手动运行；`pi` 首跑 bootstrap 时以 `--extensions-only` 调用

## 用法

```bash
pi-update                    # 更新核心 + 同步扩展 + native rebuild + Bun 入口校验
pi-update --extensions-only  # 只装扩展（pi 首跑调用路径），跳过核心更新与 native rebuild
```

## 依赖

`pnpm`（10+）、`node`（版本探测）、`jq`/内嵌 node 脚本（settings 解析）。

## 工作原理

设计原则：

1. **`settings.json` 的 packages 数组是扩展清单单一真相源**——`package.json` 是派生产物，不手维护；每次运行由脚本按清单重写。
2. **`pnpm update --latest` 跨 minor/major 升级**（不带 `--latest` 只在 semver range 内更新）。
3. **`nodeLinker: hoisted`**（`pnpm-workspace.yaml`）：jiti 从 symlink 路径解析模块时找不到扩展的传递依赖（如 `@ff-labs/pi-fff` → `@ff-labs/fff-node`），hoisted 布局是硬要求；pnpm 10+ 的配置从 `package.json` 的 `pnpm` 字段迁到 `pnpm-workspace.yaml`，脚本顺带删除废弃的 `package.json.pnpm` 段。
4. **`minimumReleaseAge: 0` 关闭供应链冷却**：pnpm 12 默认 `minimumReleaseAge=1440`（24h），发布不满一天的版本会被**静默**排除出解析——`pnpm update --latest` 因此表现为「跑完了、版本没动」。pi/插件是日更 preview 版本，两个目录的 `pnpm-workspace.yaml` 都写 `minimumReleaseAge: 0`（与 dsh `_cli/pnpm-workspace.yaml` 同一既有决策）。
5. **`ERR_PNPM_IGNORED_BUILDS` 自动批准后重试**：包装上了但 build scripts 没跑（esbuild 等 native 产物缺失）。从报告的 `Ignored build scripts:` 行解析包名，写入 `allowBuilds: true` 后重试一次 `pnpm update --latest`；仍失败才走 lockfile 兜底。
6. **lockfile 兜底**：其他错误（store 冲突、lockfile 损坏）→ 删 `pnpm-lock.yaml` 后 `CI=true pnpm install --no-frozen-lockfile` 重装。
7. **native rebuild**：`NATIVE_PKGS=(better-sqlite3)` 逐一 `pnpm rebuild`（prebuilt 平台包如 koffi 无需 rebuild），失败记入 `FAILED` 数组统一报告。
8. **保护名单**：`PROTECTED_PKGS=(pi-subagents)` 在 settings.json 未列出时保留不自动移除。
9. **Bun 入口校验**：结尾校验 `dist/bun/cli.js` 存在，防上游改布局后静默退化到 node。

## 设计决策与不变量

- **`FAILED` 数组顶层声明**：`--extensions-only` 跳过 native rebuild 时，`set -u` 下引用 `${#FAILED[@]}` 仍安全——不可把声明挪进函数。
- **`pnpm_workspace_policy` 合并而非重写**：`pnpm-workspace.yaml` 是脚本与 pnpm 共管的文件（pnpm 会自行写入 `minimumReleaseAgeExclude` 等键）。合并策略：未知顶层键原样保留，只改写指定的标量键与 `allowBuilds` 段；占位值 `set this to true or false` 仅在审批分支被换成 `true`。
- **bash `${3:-{}}` 陷阱**：花括号默认值会被 bash 提前闭合，`pnpm_workspace_policy` 的三个参数一律显式传全，不用默认值展开。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 扩展找不到传递依赖 | `nodeLinker` 不是 hoisted | 检查 `pnpm-workspace.yaml`（脚本每次运行会自愈） |
| **更新跑完但版本没变** | pnpm 12 供应链冷却（`minimumReleaseAge=1440`）把 <24h 的新版本静默排除出解析 | 确认 `pnpm-workspace.yaml` 有 `minimumReleaseAge: 0`（`pnpm config list` 可验证）；核对 `~/.cache/pnpm/lockfile-verified.jsonl` 里记录的 policy |
| 报 `ERR_PNPM_IGNORED_BUILDS` | 依赖的 build scripts 未审批，native 产物不会构建 | 脚本自动解析包名写 `allowBuilds: true` 并重试；手工等价操作是 `pnpm approve-builds` |
| 结尾报 "Bun 入口： 缺失" | 上游改了包布局 | 检查 `dist/bun/`；必要时退回 node 入口（pi wrapper 会自动告警回退） |
| `pnpm update` 反复失败 | lockfile 损坏/store 冲突 | 脚本自动删 lockfile 重装；仍败则手工删 `$PI_DATA_DIR/node_modules` |

## 变更记录

- 2026-09-30：修复「更新不生效」。根因是 pnpm 12 供应链策略的 24h 冷却把当日发布的
  pi 新版本静默排除出解析（`update --latest` 跑完但版本不动），叠加核心目录
  `allowBuilds` 占位符导致 `ERR_PNPM_IGNORED_BUILDS` 被旧逻辑当成非致命噪声。
  改动：新增 `pnpm_workspace_policy`（合并写 `minimumReleaseAge: 0` + 按报告自动
  批准 build scripts），`ERR_PNPM_IGNORED_BUILDS` 从「忽略」改为「批准后重试」。
- 无破坏性改动（早前重构只压缩注释 + 补过滤管道 `|| true` 的 pipefail 兜底，
  行为等价；该过滤逻辑随本次改动移除）。
