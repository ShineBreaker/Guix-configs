<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# hermes — Pi 式 editable-checkout 启动 wrapper（含 hermes-acp、hermes-lib.sh）

- 源码：`dotfiles/mutable/agents/hermes/.local/bin/hermes`、`hermes-acp`、`.local/libexec/hermes-lib.sh`
- 部署：`~/.local/bin/hermes`、`~/.local/bin/hermes-acp`、`~/.local/libexec/hermes-lib.sh`（mutable，改源即时生效）
- 调用方：终端直接调用；ACP 宿主（Zed/JetBrains/Buzz）按命令名解析 `hermes-acp`

## 用法

```bash
hermes            # venv CLI 透传；未安装时先 bootstrap
hermes update     # 拦截分发 → libexec/hermes-update（Guix 增强版）
hermes desktop    # 拦截分发 → libexec/hermes-desktop（FHS 容器）
hermes acp        # ACP 模式（hermes-acp 入口内部就是 exec hermes acp）
```

原生行为经 venv 直调：`${HERMES_CLI_BIN} update|desktop`。

## 依赖

运行时：`$HERMES_HOME/hermes-agent/venv/bin/hermes`（hermes-update 生成，不进仓库）。bootstrap：`uv`、`git`。

## 工作原理

- runtime 在 `$HERMES_HOME/hermes-agent`；首跑 lazy bootstrap（调 `hermes-update` 首装）。启动前 `unset PYTHONPATH PYTHONHOME` 防 Guix Python 污染环境变量漏进 venv。
- **拦截即覆写**：上游原生也有 `hermes update|desktop`，首参分发遮蔽为 Guix 增强版；libexec 内部本就直调 venv，无递归。
- `hermes-acp`：一行 exec `hermes acp`。历史上由 `hermes update` 写入 `~/.local/bin/`（硬编码绝对路径），现已收编进仓库随 stow 部署；若上游 update 流程将来重写此文件，restow 后须核对软链未被真身覆盖。**ACP 宿主按命令名寻址，文件名不可改**。

### hermes-lib.sh（共享库）

单一真理源覆盖三类逻辑，约定**只做赋值与函数定义、不设 shell 选项、全部副作用幂等**：

1. **布局常量**（desktop 壳 `main.cjs` 硬编码）：`HERMES_HOME`（读系统设置，fallback 到 XDG data）、`HERMES_RUNTIME=$HERMES_HOME/hermes-agent`、`HERMES_VENV`、`HERMES_CLI_BIN`、`HERMES_DESKTOP_RELEASE_DIR`、`HERMES_MANIFEST` 等。`HERMES_HOME` 统一 `export`——desktop 的 PRESERVE 正则要把透传进容器（壳靠它推导 `ACTIVE_HERMES_ROOT`，抓不到会 fallback 到默认 `~/.hermes` 而找不到安装）。
2. **XDG data home / hicolor 图标路径**解析 + 1024 px 图标安装（`hermes_install_icon_1024`，覆盖写天然幂等）。
3. **FHS 容器边界配置**：宿主 GUI 环境解析（GTK 主题/输入法/Ozone）、`--preserve` 正则、`--share/--expose` 旗标构建。语义对齐 `appimage-run_lib/gui-env.scm` + `container.scm` 的 bash 手译副本，但**独立维护、不跨包引用**——部署域不同，各自演进漂移是刻意的。

## 设计决策与不变量

- **session init → GUI 解析 → share 旗标顺序不可换**：`hermes_session_env_init` 提供 `WAYLAND_DISPLAY` 默认值与 `RT_DIR`，Ozone 探测与 socket expose 都依赖它（详见 hermes-desktop.md）。
- venv 缺失时 wrapper 打印引导而不静默联网安装（desktop 场景 stdin 可能是 `/dev/null`）。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 容器内找不到安装（回退 `~/.hermes`） | `HERMES_HOME` 未 export 透传 | 确认 lib 的 export 生效；不要手动覆盖 |
| ACP 宿主报 agent 找不到 | `hermes-acp` 软链被上游 update 真身覆盖 | `cd dotfiles/mutable && stow -R agents/hermes` 或核对软链 |

## 变更记录

无破坏性改动（本次重构只压缩注释；hermes-desktop 一处 pipefail 修复见其文档变更记录）。
