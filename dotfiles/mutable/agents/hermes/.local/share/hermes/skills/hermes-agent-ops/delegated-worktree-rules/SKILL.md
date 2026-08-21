---
name: delegated-worktree-rules
description: "规定 hermes 何时**必须**用 `hermes --worktree` / `delegate_task(workdir=<worktree>)` 隔离执行，而不是直接改 source tree。来源 punkjazz.ai §02 'Two execution routes'——每个 delegated task 必须有独立 branch + worktree + activity record，source checkout 稳定。触发词：'并行任务 / 多 writer / worktree 隔离 / 怕冲突 / 长任务改源码 / 委派子 agent 改代码'，或当任务满足触发条件清单（见正文）。"
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [worktree, isolation, delegate, parallel, git, source-stability]
    related_skills: [worker-handoff, task-contract, code-reviewer]
---

# delegated-worktree-rules — 何时必须用 worktree

## 核心命题

**hermes 原生有 `hermes --worktree / -w`**（"Isolated git worktree mode (parallel agents)"），**不要重新发明**。本 skill 只规定**何时必用**+**怎么用得正确**。

来源方法论：punkjazz.ai §02 "Two execution routes"：

> Each delegated task receives its own branch, isolated working copy, Git index, and activity record before the coding agent starts. **The source checkout stays stable, and one task cannot switch, close, or clean another task's work.** A clean verified task may remove its temporary workspace later, while anything dirty, offline, interrupted, or uncertain remains available for recovery.

## 何时**必须**用 worktree（trigger 清单）

满足以下**任一**条件：

- **T1**: 多任务并行 → 同一 source tree 上 ≥ 2 个 writer
- **T2**: 长任务（>30 min）改源码 → 中断风险 + 残留 worktree 价值
- **T3**: 主 agent 自己要继续监控 / 干预 → 子 agent 不能撞主 agent 的 working copy
- **T4**: 任务**不可逆**部分（删除 / 改名 / 大改）→ 失败可恢复
- **T5**: 多个 subagent / worktree 一起跑实验 → 比对结果
- **T6**: hermes `--worktree` 标志可用（hermes 原生）

何时**不**用：

- 只读 / 查询任务
- 单文件小改（typo / README）
- 沙箱 / ephemeral 环境（distrobox / docker）已经在隔离里

## 三种用法（按场景选）

### 用法 A: hermes 子进程并行（multi-process）

```bash
# A1: 主 agent 启动前先开 worktree
terminal(command="hermes --worktree -q '<task>'", background=true)

# A2: 多个 hermes 进程并行（hermes-agent skill §Multi-Agent Coordination）
terminal(command="tmux new-session -d -s backend -x 120 -y 40 'hermes -w'", timeout=10)
terminal(command="tmux new-session -d -s frontend -x 120 -y 40 'hermes -w'", timeout=10)
```

**适用**：长任务、用户想监控、并行 2-N 个独立 feature。

### 用法 B: delegate_task 子 agent（in-process）

```python
delegate_task(
    goal="<任务>",
    context="...",
    toolsets=['coding', 'terminal'],
    workdir="/path/to/worktree/<task-id>",  # 必须给 worktree path
)
```

**适用**：短子任务、context 复用主 agent 的 skills / memory。

### 用法 C: 直接 cd 到 worktree（同一进程内）

```bash
terminal(command="git worktree add ../worktrees/<task-id> -b task/<id>", timeout=30)
terminal(command="cd ../worktrees/<id> && <agent-cmd>", timeout=180)
```

**适用**：agent loop 在单进程但要隔离文件系统视图。

## 硬规则（必须遵守）

### R1: source checkout 绝不被 switch / clean

子 agent **禁止**：
- `git checkout main` 在 source root（会留下 dirty）
- `git clean -fd` 在 source root（worktree work 全丢）
- `git stash` 后不恢复
- 在 source root 写文件而不 commit

主 agent **必检**：
- 子 agent 完成 → 主 agent `git status` 看是否泄漏到 source root
- 用 `git diff --stat <source-root>` 限制 source root 改动范围

### R2: 每个 task 独立 branch + 独立 dir

```bash
git worktree add ../worktrees/<task-id> -b task/<task-id>-<short-desc>
```

- branch 名：`task/<task-id>-<short-desc>`（task-id 用时间戳或 uuid）
- 路径：`<source-root-parent>/worktrees/<task-id>`（推荐） 或 `.worktrees/<task-id>`（git 默认）
- **不要**用 source root 内的 `.worktrees/`（污染 source root）

### R3: dirty / offline / interrupted 必须可恢复

子 agent **必留**：
- branch 不 force-delete
- worktree dir 不 rm（用 `trash-cli` 走 XDG trash，符合用户硬偏好）
- commit 不 force-push

主 agent **必检**：
- 子 agent 中途断 → worktree 还在 → 可 `git worktree list` 找到
- 子 agent 完成后 → `git log --oneline task/<id>` 看 commit history

### R4: cleanup 走 trash-cli（用户硬偏好）

```bash
# 验证完成、commit 已 merge / cherry-pick 后
trash-put ../worktrees/<task-id>           # 删除 worktree
git worktree prune                          # prune git metadata
git branch -d task/<task-id>                # delete local branch
```

**绝不**：`rm -rf`（用户明确反对）。

### R5: 完不成的 task 保留 worktree ≥ 24 小时

- 子 agent 失败 / blocked → worktree 保留 24h，给主 agent / 用户回看
- 24h 后清理走 trash-cli
- 跨会话恢复：用 `git worktree list` + `git log <branch>` 还原

## 与 `worker-handoff` 的接口

`worker-handoff` 派发子 agent 时：
- **应在** context 里说："在 worktree `<path>` 中工作，branch 为 `<branch>`"
- 子 agent 完成 → handoff 应**包含** worktree path + branch name + last commit hash
- 主 agent 收 handoff → 用这 3 项**核对**：worktree 真存在？branch 真存在？commit hash 真存在？

## 与 `task-contract` 的接口

`task-contract` 的 false-success conditions 应包含：
- "worktree 路径泄漏到 source root" → false success
- "子 agent 的 branch 没保留 / 被 force-pushed" → false success
- "dirty worktree 被强清" → false success

## 不造轮子的承诺

- **不写** `delegate_task` 的 wrapper 脚本（hermes 原生足够）
- **不写** `git worktree` 的 wrapper（git 原生命令足够）
- **不重复** `worker-handoff` 的隔离规则（只引用 + 补充 worktree 维度）

## References

- `templates/worktree-setup.sh` — worktree 创建的标准脚本（粘到 `terminal()` 里跑）
- `references/source-stability-rules.md` — source checkout 稳定的 6 条硬规则（含 git status 检查清单）