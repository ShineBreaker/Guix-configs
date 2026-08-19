# skills 包 — 第三方 agent skills 的声明式管理

以 `skills-lock.json` 为唯一声明，管理安装到 `~/.config/agents/skills/` 的第三方
skills。**skill 内容不进 git**：新机 clone + `blue stow skills` 后跑
`askill install` 即从上游恢复（模型对齐 `source/channel.lock`）。

## 用法

入口命令 `askill`（本包 `.local/bin/askill`，stow 部署到 `~/.local/bin/`）：

```bash
askill add mattpocock/skills -s tdd,grill-me   # 纳管：写锁 + 装最新
askill update                                   # 全量更新（git diff 审查后提交）
askill install                                  # 从锁恢复（新机）
askill remove tdd                               # 卸载
askill list                                     # 列出已纳管
```

## 机制

- 引擎是 [`npx skills`](https://github.com/vercel-labs/skills)（vercel）的
  project scope + `universal` agent + `--copy`，cwd 为包内
  `.config/agents/skills/`。
- `.config/agents/skills/.agents/skills/` 是 npx 的落盘暂存区（gitignore、
  stow-ignore），`askill` 按锁清单逐条同步到 `~/.config/agents/skills/`——
  **锁外目录（agenote、emacs 等包的自建 skill）绝不经 askill 触碰**。
- 锁真身即 `.config/agents/skills/skills-lock.json`（部署后
  `~/.config/agents/skills/skills-lock.json` 直接可查）。
- ref 跟踪上游最新（无 commit pin）；版本冻结由 git 提交锁文件承担，
  `computedHash` 提供内容基线。

## 与旧模型的历史

2026-08 前，第三方 skills 以 vendored 拷贝存于本包 `.config/agents/skills/`
下、经 stow 软链部署（commit `53d58dca` 等）。2026-08-19 起迁移为 lock 驱动，
旧拷贝已从 git 移除（git 历史仍可回溯），存量 53 个全部登记入锁。
