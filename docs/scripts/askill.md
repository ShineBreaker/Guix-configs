<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# askill — 声明式管理第三方 agent skills（锁驱动）

源码 `dotfiles/mutable/agents/skills/.local/bin/askill` · 部署 `~/.local/bin/askill`（mutable，改源即时生效） · 调用方：手动运行

模型对齐 `source/channel.lock` 哲学：仓库只声明 `skills-lock.json` 与本脚本，skill 内容按需从上游装到部署位。引擎是 `npx -y skills@1.5.23`（project scope + universal agent + `--copy`），另需 `jq` 读锁；`DISABLE_TELEMETRY=1`，`SKILLS_CLONE_TIMEOUT_MS` 默认 `600000` 可覆盖。布局三处：锁真身在仓库（`dotfiles/mutable/agents/skills/.agents/skills/skills-lock.json`，Stow 单文件直链到部署位）、部署位与工作区 `~/.agents/skills/`（真实 skill 目录，自建 skill 共存）、暂存区 `~/.agents/skills/.agents/skills/`。运行不依赖仓库路径，改源即时生效。

## 用法

```bash
askill add <owner/repo> [-s <skill>[,<skill>...]] [--as <部署名>] [-l 只列出不安装]
askill update    # 按锁检查上游并刷新暂存区，再同步部署位
askill install   # 按锁全量安装（新机 clone + stow 后跑这个）
askill remove <skill>...   # 从锁与部署位移除
askill sync      # 只把暂存区同步到部署位（按锁清单）
askill list      # 列出锁内 skills
```

无参数或未知子命令打印用法。`add`/`update`/`remove` 完成后提示 `git diff` 审查再提交——锁是 mutable 直链，改锁即改仓库源。

## 重命名（同名上游共存）

`npx skills` 的锁 key 就是 skill 名，同名上游必然互相覆盖（后装的挤掉先装的）。askill 用 `upstreamName` 字段补上这层：锁的 key 是**部署名**，`upstreamName` 记**上游真名**（缺省即上游名）。

```bash
askill add heydamir/unslop -s unslop --as unslop-ui
```

装出的是 `~/.agents/skills/unslop-ui/`，frontmatter 的 `name:` 同步改成 `unslop-ui`——宿主（DSH 等）按 frontmatter 认名，目录名只决定落点。两版同名上游可共存：

| 部署名      | 上游名   | 来源              | 用途     |
| ----------- | -------- | ----------------- | -------- |
| `unslop-text` | `unslop` | `cursor/plugins`   | 文字去 AI 味 |
| `unslop-ui`   | `unslop` | `heydamir/unslop` | UI 去 AI 味   |

## 实现与约束

- **`sync_from_staging` 只处理锁内名字**：逐条读锁里的名字，暂存区有该名字才换入部署位（`.<name>.incoming` 临时目录 + `cp -aL` 摊平软链 + `mv` 原子换入），**部署位的自建 skill 绝不触碰**；锁文件缺失即报错退出。
- **版本冻结靠 git 提交承担锁语义**：上游 ref 没有 commit pin，`install` 恢复的是上游当前最新，与锁内 `computedHash` 的偏差由随后一次 `update` 的检测体现——`computedHash` 是完整性基线，不是校验门。
- **`npx skills` 的 `-s` 不支持逗号多值**（会报 `No matching skills found`）：脚本把逗号列表展开成重复 `-s`。
- **删除路径不带尾斜杠**：`rm -rf "${WORK:?}/$name"` 的目标可能是文件、软链或目录三者之一，带斜杠会对软链目标递归删除；`remove` 另先校验名字，含 `/`、以 `.` 开头或空串一律拒绝。
- **写锁不能 `mv` 换文件**：部署位的锁是 Stow 软链指向仓库源，`mv` 会斩断软链，让仓库源与部署位分家（改完 `git diff` 看不到、仓库源还是旧内容）。`write_lock` 先落 `mktemp` 再写内容穿透软链；直接 `cat >"$LOCK"` 也不行——上游 `jq` 正从同一文件读，截断先于读取发生，锁内容会被清空。
- **`update`/`install` 临时换名**：npx 按锁里的名字去上游取同名 skill，部署名与上游名不同时会失败。脚本在这两个命令前把重命名条目的 key 临时换回上游名，跑完再换回部署名——重命名能力由此完全复用 npx 的更新逻辑，不必 fork 它。
- **暂存区与 agent 链接同步改名**：`add --as` 后暂存区目录与 frontmatter 一并改名（暂存区是 npx 建的 agent 链接的指向处）；`sync_agent_links` 修 `.claude/skills/` 等目录里指向旧名的断链。

## 排障

| 现象                       | 原因                                           | 处理                                             |
| -------------------------- | ---------------------------------------------- | ------------------------------------------------ |
| 找不到 `skills-lock.json`  | 尚未生成锁（`update`/`install`/`sync` 都会报） | `askill add <owner/repo>` 生成                   |
| npx clone 超时             | 网络慢或仓库大                                 | `SKILLS_CLONE_TIMEOUT_MS=1200000 askill add ...` |
| 自建 skill 被覆盖          | 名字与锁内 skill 冲突                          | 改名；脚本只同步锁内名字，但同名仍会被换入覆盖   |
| 暂存区有内容但部署位没更新 | `sync_from_staging` 跳过（锁内无该名字）       | 用 `askill add`/`update` 重新落盘，或核对锁      |
| 同名上游只剩一个           | 未加 `--as`，锁 key 撞名                       | `askill add <repo> -s <skill> --as <部署名>`     |
| `update` 报 `Failed to update <部署名>` | 锁里存的是部署名，上游无同名 skill      | 确认 `upstreamName` 字段存在                     |
