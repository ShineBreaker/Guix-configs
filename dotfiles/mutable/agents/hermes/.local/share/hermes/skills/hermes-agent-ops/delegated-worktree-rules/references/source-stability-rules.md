# source-stability-rules — source checkout 稳定的 6 条硬规则

来源：punkjazz.ai §02 "Two execution routes" + user 硬偏好（commit 边界 / trash-cli）。

## R1: 子 agent 绝不切 source root branch

**禁**：

```bash
cd <source-root>
git checkout main          # 切走
git checkout other-branch  # 切走
git checkout -- .          # 撤销改动（不可恢复）
```

**原**：source root 是主 agent 的 working copy。子 agent 切走 → 主 agent 之后操作看不见实际状态。

## R2: 子 agent 不 git clean / stash

**禁**：

```bash
git clean -fd     # 删未跟踪文件，worktree work 可能丢
git stash         # 改动暂存，可能被主 agent 误 pop
git stash pop     # 同样问题
```

## R3: 主 agent 必检 source root 干净

子 agent 完成 → 主 agent 必跑：

```bash
cd <source-root>
git status
git diff --stat   # 改动大小合理吗？
```

**期望**：clean 或只显示子 agent 显式声明的改动。如果有未声明改动 → 子 agent 写错路径了，回滚。

## R4: 子 agent 必留 commit hash 给主 agent

子 agent 完成 → handoff 必含：

```markdown
## Branch
`<branch-name>` (例如 task/20260720-fix-merge-fix)

## Last Commit
`<commit-hash>` (例如 a1b2c3d)
```

主 agent **必校验**：

```bash
git -C <worktree-path> log -1 --format=%H   # 拿到真实 commit hash
git log -1 <branch>                          # 校验 branch 真存在且 tip 是这个 hash
```

## R5: dirty / interrupted worktree 保留 24h

子 agent 中途断 → 不清理 → 等主 agent / 用户回看。24h 后清理走 `worktree-cleanup.sh`。

清理**必走 trash-cli**：

```bash
trash-put <worktree-path>     # 走 XDG trash，可恢复
```

不**用** `rm -rf`（用户硬偏好）。

## R6: source root 不创建 `.worktrees/`

git worktree 默认在 `<repo>/.worktrees/<name>`。这**会污染 source root**（`git status` 看到 `.worktrees/` 是 untracked）。

**正确做法**：

```bash
git worktree add ../worktrees/<task-id> -b task/<id>
```

worktree 在 **source root parent** 的 `worktrees/` 下，不在 source root 内。

例外：用户明确说"在 repo 内就行" → 才用 `.worktrees/`。

## 必检清单（每条对应一个 adversarial review 的 attack vector）

| 规则 | 对应 attack vector |
|------|--------------------|
| R1 | A8 (不可逆副作用) |
| R2 | A3 (activity record 丢) |
| R3 | A1 (报告无 artifact) |
| R4 | A3 / A1 |
| R5 | A3 |
| R6 | A8 / A5 (子任务被吞) |

跑 `adversarial-review-trigger` skill 时逐条 check。