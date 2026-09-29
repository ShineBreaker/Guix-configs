<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# askill — 声明式管理第三方 agent skills（lock 驱动）

- 源码：`dotfiles/mutable/agents/skills/.local/bin/askill`
- 部署：`~/.local/bin/askill`（mutable，改源即时生效）
- 调用方：手动运行

## 用法

```bash
askill add <owner/repo> [-s <skill>[,<skill>...]] [-l 只列出不安装]
askill update [skill]     # 重拉上游刷新暂存区并同步部署位
askill install            # 按锁全量安装（新机器/暂存丢失后）
askill remove <skill>     # 从锁与部署位移除
askill sync               # 暂存区 → 部署位再同步
askill list               # 锁内清单
```

## 依赖

`npx`（引擎 `skills@1.5.23`，vercel-labs）、`jq`。

## 工作原理

模型对齐 `source/channel.lock` 哲学：仓库只声明（`skills-lock.json` + 本脚本），skill 内容按需从上游安装到 `~/.config/agents/skills/`，由锁的 `computedHash` 提供完整性基线。

布局（immutable 脚本 + mutable 锁直链，运行不依赖仓库路径）：

- `~/.config/agents/skills/` — 工作区 = 部署位置（真实 skill 目录，自建 skill 共存）
- `~/.config/agents/skills/skills-lock.json` — 锁真身在 `dotfiles/mutable/agents/skills/`（Stow 单文件直链，改锁即改仓库源，git diff 直接可见）
- `~/.config/agents/skills/.agents/skills/` — npx project-scope 落盘暂存区

引擎：`npx skills`，project scope + universal agent + `--copy`。**版本冻结**：ref 跟踪上游最新（无 commit pin），锁语义由 git 提交 `skills-lock.json` 承担。`DISABLE_TELEMETRY=1`；`SKILLS_CLONE_TIMEOUT_MS` 默认 600000 可覆盖。

`sync_from_staging` 逐条只处理锁内名字：**部署位的自建 skill（lock 外）绝不触碰**；经 `.<name>.incoming` 临时目录 + `cp -aL`（展开软链，update 重装走 symlink 模式时也摊平成真实文件）+ `rm -rf`（无斜杠，对旧 stow 软链只删链本身）+ `mv` 原子换入。

## 设计决策与不变量

- **`npx skills` 的 `-s` 不支持逗号多值**（报 No matching skills found）：脚本把逗号列表展开为重复 `-s` 参数。
- **`rm -rf "${WORK:?}/$name"` 不带尾斜杠**：目标是文件/软链/目录三者之一，带斜杠会对软链目标递归删除。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `找不到 skills-lock.json` | 尚无锁 | `askill add <owner/repo>` 生成 |
| npx clone 超时 | 网络慢/大仓库 | `SKILLS_CLONE_TIMEOUT_MS=1200000 askill add ...` |
| 自建 skill 被覆盖 | 名字与锁内 skill 冲突 | 改名（脚本只同步锁内名字，冲突名会被换入覆盖） |

## 变更记录

无破坏性改动（本次重构只压缩注释）。
