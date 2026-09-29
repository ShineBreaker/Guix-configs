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
4. **`ERR_PNPM_IGNORED_BUILDS` 非致命**：包已正常安装只是 build scripts 未审批——过滤该行与其 approve-builds 提示后继续。
5. **lockfile 兜底**：其他错误（store 冲突、lockfile 损坏）→ 删 `pnpm-lock.yaml` 后 `CI=true pnpm install --no-frozen-lockfile` 重装。
6. **native rebuild**：`NATIVE_PKGS=(better-sqlite3)` 逐一 `pnpm rebuild`（prebuilt 平台包如 koffi 无需 rebuild），失败记入 `FAILED` 数组统一报告。
7. **保护名单**：`PROTECTED_PKGS=(pi-subagents)` 在 settings.json 未列出时保留不自动移除。
8. **Bun 入口校验**：结尾校验 `dist/bun/cli.js` 存在，防上游改布局后静默退化到 node。

## 设计决策与不变量

- **`FAILED` 数组顶层声明**：`--extensions-only` 跳过 native rebuild 时，`set -u` 下引用 `${#FAILED[@]}` 仍安全——不可把声明挪进函数。
- **过滤管道 `|| true`**：`echo "$out" | grep -v ... | grep -v ...` 在 `pipefail` 下全过滤时返回 1，需兜底。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 扩展找不到传递依赖 | `nodeLinker` 不是 hoisted | 检查 `pnpm-workspace.yaml`（脚本每次运行会自愈） |
| 结尾报 "Bun 入口： 缺失" | 上游改了包布局 | 检查 `dist/bun/`；必要时退回 node 入口（pi wrapper 会自动告警回退） |
| `pnpm update` 反复失败 | lockfile 损坏/store 冲突 | 脚本自动删 lockfile 重装；仍败则手工删 `$PI_DATA_DIR/node_modules` |

## 变更记录

无破坏性改动（本次重构只压缩注释 + 补过滤管道 `|| true` 的 pipefail 兜底，行为等价）。
