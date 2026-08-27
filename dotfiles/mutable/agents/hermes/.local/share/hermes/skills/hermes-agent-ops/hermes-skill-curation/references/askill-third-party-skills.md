# askill — 第三方 agent skills 声明式安装（~/.config/agents/skills/ 锁内条目）

> `hermes-skill-curation` §1.7 边界的补充参考：`~/.config/agents/skills/` 里**锁内**的 skill（`skills-lock.json` 有条目的）不归 curation 协议管，增删统一走 `askill` CLI。本文件是 askill 工作流与踩坑记录。自建 skill（锁外目录）不受任何 askill 命令影响，两者共存于同一部署目录。

## 布局（2026-08 实测）

```
~/.config/agents/skills/                  部署位置 = 工作区（真实 skill 目录）
├── skills-lock.json                      锁真身，Stow 单文件直链到
│                                         dotfiles/mutable/agents/skills/.config/agents/skills/skills-lock.json
│                                         → npx 写锁即写仓库源，git diff 直接可见
└── .agents/skills/<name>/                npx project-scope 落盘暂存区（askill add 后由脚本同步到上级）
```

## CLI 速查

```bash
askill list                        # 列出已纳管（含 source + skillPath）
askill add <owner/repo> [-s a,b]   # 安装上游 skill（写锁 + 落盘 + 同步部署位）
askill remove <skill>...           # 卸载（删锁条目 + 部署目录）
askill update / install / sync     # 更新全部 / 新机从锁恢复 / 仅同步暂存区→部署位
```

## 标准安装工作流

1. **先确认上游路径结构**（可选但推荐）：GitHub API 拿 repo tree，过滤 `SKILL.md`，确认目标 skill 的确切 `skillPath` 和目录名——上游仓库的 skill 可能藏在任意深度（如 `.agents/skills/skill-doctor/SKILL.md`、`plugins/show-me/skills/show-me/SKILL.md`）。
2. `askill add <owner/repo> -s <skill-name>`（一次一个 repo；同一 repo 多个 skill 用逗号）。引擎会 clone 整个 repo、列出可发现的 skills、装选中的到暂存区。
3. askill 自动把暂存区同步到部署位置（逐条、只动锁内名字）。
4. **提交锁冻结版本**：`git diff dotfiles/mutable/agents/skills/.config/agents/skills/skills-lock.json` 确认只含本次新增条目 → `git add -- <该文件>` → Conventional Commits 提交（如 `chore(skills): add a, b, c`）。ref 无 commit pin，锁语义由 git 提交承担。
5. 验证：`askill list` 出现新条目 + `ls ~/.config/agents/skills/<name>/SKILL.md` 存在。

## 已知坑

### npx 引擎依赖 git —— agent 会话 PATH 缺 git 时直接失败

`npx skills` clone 用 `spawn git`，不走绝对路径。Hermes 终端会话 PATH 默认**不含** git（2026-08-26 实测：`which git` 为空），首次 `askill add` 报 `Failed to clone ... spawn git ENOENT`。

修法：把 store 里的完整版 git 加进 PATH 再跑：

```bash
export PATH=/gnu/store/<hash>-git-<ver>/bin:$PATH
# 找 hash: ls -d /gnu/store/*-git-*/bin，选带 libexec/git-core/git-remote-https 的完整版（非 git-minimal）
askill add ...
```

判别完整版 vs `git-minimal`：minimal 没有 `libexec/git-core/git-remote-https`，clone https 会失败。这是环境状态问题不是 askill 缺陷——若用户已修好 PATH 则无需此步。

### 上游 YAML frontmatter 损坏会被静默跳过

npx 解析 SKILL.md frontmatter 失败（如 cursor/plugins 里的 check-agent-compatibility）只打一行 warning 然后 skip。如果 `-s` 指定的 skill 恰好是被跳过的那个，add 会报"找不到"——先去上游确认 frontmatter 本身合法。

### add 是全量同步

每次 `add` 都会把暂存区里**所有**锁内 skill 重刷一遍部署位（输出一长串"已同步"），属正常行为，不是误操作。

### 内容不进 git

只有 `skills-lock.json` 进 git（mutable Stow 直链）；skill 内容本体按需从上游安装，靠锁内 `computedHash` 做完整性基线。新机恢复 = `blue stow agents/skills` + `askill install`。
