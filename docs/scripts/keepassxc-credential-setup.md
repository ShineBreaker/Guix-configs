<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# keepassxc-credential-setup — git-credential-keepassxc 配置管理

- 源码：`dotfiles/immutable/utilities/.local/bin/keepassxc-credential-setup`
- 部署：`~/.local/bin/keepassxc-credential-setup`（immutable，改后需 `blue home`）
- 调用方：手动运行；git 凭据 helper 实际由 `libexec/git-core/git` 触发

## 用法

```bash
keepassxc-credential-setup status    # 检查配置健康状态
keepassxc-credential-setup init      # 初始化完整配置（databases + callers）
keepassxc-credential-setup update    # 更新过期的 callers 路径
keepassxc-credential-setup callers   # 仅重新注册 callers（不影响 databases）
```

## 依赖

`jq`（配置 JSON 读写）、`keepassxc-cli`/`git-credential-keepassxc`（init/register 阶段）、`fish`、`git`（caller 路径解析）。

## 工作原理

配置文件：`~/.config/git-credential-keepassxc`（JSON，`databases` + `callers` 两段）。

`callers` 登记的是「谁被允许向 KeePassXC 要凭据」：`fish`（交互调用）与 git 的 `libexec/git-core/git`（凭据 helper 的实际调用者）。**包升级后 store hash 变化会让已登记路径过期**——`status`/`update` 负责发现它们。

- `expected_callers`：当前系统预期路径的单一事实来源——`readlink -f` 解 fish 与 git，git 优先取 `<prefix>/libexec/git-core/git`（helper 的真实调用者），不存在回落 git 本体。
- `status` 体检 callers：报告「登记了但文件已消失」与「系统当前路径未登记」两类过期项。
- `update`/`callers` 只重写 callers 段，`init` 连带 databases 初始化。

## 设计决策与不变量

- **expected_callers 是单一事实来源**：新增调用方（如新的 git 前端）只改这一个函数，`status`/`update` 自动跟随。
- 非交互提示与确认集中在各命令；`update` 只动 callers 段，不碰用户已配的 databases。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| git 拉取时 KeePassXC 不弹授权 | callers 路径过期（git 升级换 store hash） | `keepassxc-credential-setup status` 确认后 `update` |
| status 报「未登记」fish | fish 路径经 readlink 后与登记不符 | `update` 刷新 |

## 变更记录

无破坏性改动（本次重构只压缩注释）。
