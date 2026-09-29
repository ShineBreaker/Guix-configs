<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# hermes-update — `hermes update` 子命令实体

- 源码：`dotfiles/mutable/agents/hermes/.local/libexec/hermes-update`
- 部署：`~/.local/libexec/hermes-update`（mutable，改源即时生效；经 `hermes update` 分发或按绝对路径直调）
- 调用方：`hermes update`、wrapper 首跑 bootstrap、agent 手动

## 用法

```bash
hermes update              # 已装 → 委托官方 update；未装 → 首次安装
hermes update --check      # 官方参数透传（--check/--branch/--backup/--no-backup/--yes 等）
hermes update --branch X   # 跟别的分支
```

## 依赖

`uv`（Guix 系统 uv，依赖检查硬性要求）、`git`、herd（服务恢复）。

## 工作原理

设计：**放弃 pin-tag，跟 main**。已安装 checkout 的更新整套委托给官方 `hermes update`（fetch → stash → pull + syntax guard/rollback → 依赖重装 → config 迁移 → skills sync → desktop build），本脚本只补官方做不了的、与 Guix 布局强相关的四件事：

1. **首次安装**：官方 update 在 checkout 不存在时报 "Not a git repository" 退出；本脚本 `git clone --branch main` + `uv` 建 venv + 写 bootstrap 标记。
2. **更新前停旧 gateway**：官方不管；旧进程持失效模块路径会让 MCP 全挂。
3. **uv 隔离**：防官方在 `$HERMES_HOME/bin` 装独立 managed uv 偏离 Guix 系统 uv——官方 `ensure_uv()` 只查 `$HERMES_HOME/bin/uv` 是否存在，预置一个指向系统 uv 的 symlink 后其 `resolve_uv()` 的 `p.is_file()` follow symlink 返回 True 即用系统 uv（`update_managed_uv` 的 `uv self update` 对 store 只读路径失败但只是 debug 级、非致命）。
4. **更新后恢复 herd 常驻服务**：停服务 → 清官方野实例 → `herd enable + start`（`hermes-backend` → `hermes-gateway` 顺序，gateway 依赖 backend）。

其他行为：

- **布局约定**（desktop 壳 `main.cjs` 硬编码）：`ACTIVE_HERMES_ROOT=$HERMES_HOME/hermes-agent`（checkout 直接落顶层、不嵌套），`isHermesSourceRoot()` 要求源码根直接含 `hermes_cli/main.py`，`isBootstrapComplete()` 要求 `.hermes-bootstrap-complete` 是合法 JSON（`schemaVersion=1` + `pinnedCommit`，取 HEAD 前 7 位）。首次安装由本脚本写标记，官方 update 不碰。
- **不用 exec 委托**：官方 update 完成后还要 herd restart 收尾，委托是普通调用，保留退出码；非零退出时若 HEAD 已移动（官方更新其实成功但收尾步骤失败）仍执行服务恢复。
- managed Node provisioning：desktop build 需要的 node 不进 PATH 污染，单独放 `$HERMES_HOME` 下。
- hicolor 图标生成见 lib 的 `hermes_install_icon_1024`。

## 设计决策与不变量

- **uv symlink 预置必须先于一切官方调用**：官方 clone/venv 阶段就可能查 uv。
- herd 顺序固定 backend → gateway；反向停服时同样先停 gateway。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 更新后 MCP 全挂 | 旧 gateway 进程持失效模块路径 | `herd restart hermes-gateway`（或再跑 `hermes update` 触发收尾） |
| `$HERMES_HOME/bin/uv` 变成真二进制 | 预置 symlink 被官方替换 | 重跑本脚本恢复 symlink |

## 变更记录

无破坏性改动（本次重构只压缩注释）。
