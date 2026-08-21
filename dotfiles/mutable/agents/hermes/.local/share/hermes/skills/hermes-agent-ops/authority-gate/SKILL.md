---
name: authority-gate
description: "规定哪些 action 是 **protected**（必走用户授权，agent 不能自决）+ 与 hermes 原生 `approvals.mode` 配合。来源 punkjazz.ai §03 'Protected work'——'Publishing, protected configuration, credentials, spending, and difficult-to-reverse actions require approval from outside the agent process.' 触发词：'protected action / 不可逆 / 授权 / 安全动作 / 危险动作 / rm -rf / force push / 改全局 config / 删文件 / 改凭据 / 跨账号 / 付费'，或当 agent 准备执行清单中的 action 时。"
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [authority-gate, protected-action, approval, safety, irreversible]
    related_skills: [task-contract, worker-handoff, adversarial-review-trigger]
---

# authority-gate — protected action 授权门

## 核心命题

**agent 不能自己批准自己执行不可逆动作。** 来源 punkjazz.ai §03：

> Publishing, protected configuration, credentials, spending, and difficult-to-reverse actions require approval from outside the agent process. This keeps routine execution quiet while preserving a clear boundary around the decisions that still belong to a person.

**关键洞察**：不是"agent 做事要 prompt 用户"（噪音），而是**只有 protected action 才走 gate**。routine 走快路径。

## 与 hermes 原生机制的接口

hermes 已有 `approvals.mode`（manual / smart / off）+ `~/.hermes/shell-hooks-allowlist.json` —— **本 skill 不重复造**，而是：
- **列出哪些 action 必走 gate**（清单）
- **建议配置**（`approvals.mode: smart`）
- **提供会话级 override 机制**（execute 前主动 `clarify()`）

## Protected Action 清单（5 类）

### P1: 不可逆文件系统动作

| Pattern | 例子 | 必走 gate？ |
|---------|------|-------------|
| `rm -rf <path>` | `rm -rf ~/some/dir` | **必走** |
| `trash <path>` 删除大目录 | `trash ~/Projects/X`（>100MB） | 必走 |
| `git push --force` 到 main/master | | **必走** |
| `git reset --hard` | | **必走** |
| `git clean -fd` | | **必走** |
| `mv` 覆盖文件 | `mv new old` | 建议走 |

**用户硬偏好**（来自 MEMORY.md）：删文件一律 `trash-cli`，不 `rm`。**这条已经执行中**，本 skill 在此强化。

### P2: 凭据 / 付费 / 网络边界

| Pattern | 必走 gate？ |
|---------|-------------|
| 任何 `curl POST` 含 API key / 写 token | **必走** |
| 调用付费 API（即使已有 key） | 必走 |
| 任何把数据 `send` / `publish` 到外部 | 必走 |
| `pip install` / `guix install` 全局包 | 必走（除非用户明确预批） |
| 任何 `sudo` 命令 | **必走**（默认禁） |
| 修改 `~/.hermes/.env` / `~/.hermes/auth.json` | **必走** |
| 修改 `~/.guix-home/profile/` 任意 manifest | 必走 |

### P3: 跨会话状态破坏

| Pattern | 必走 gate？ |
|---------|-------------|
| 修改 `~/.hermes/config.yaml` | **必走**（除非用户明确让改） |
| `hermes cron create` 永久 cron job | **必走** |
| `hermes skills uninstall` 任意 skill | **必走** |
| 删除 `~/.local/share/hermes/skills/<name>/`（trash） | 必走 |
| 修改 `~/.bashrc` / `~/.zshrc` | **必走** |
| `git remote add` / `git remote set-url` | 必走 |

### P4: 发布 / 公开 / 跨人动作

| Pattern | 必走 gate？ |
|---------|-------------|
| `git push` 到 **任何** remote（首次 push） | **必走** |
| 发布到 blog / 文档站 / web（hermes-gateway 推送） | **必走** |
| 任何 `twine upload` / `npm publish` | **必走** |
| 任何 `git tag` 在 release 分支 | 必走 |

### P5: 不可预测 / 不可逆的批量操作

| Pattern | 必走 gate？ |
|---------|-------------|
| `find . -delete` | **必走** |
| `rsync --delete` | **必走** |
| `apt remove` / `guix remove` 任意包 | 必走 |
| 数据库 `DROP TABLE` / `DELETE FROM` 无 WHERE | **必走** |
| `kubectl delete` 任意资源 | **必走** |

## 何时**不**走 gate

- 读 / 搜索 / grep / find（无 -delete）
- 创建新文件（不覆盖）
- git commit 到本地分支（不 push）
- 单个文件改动（小改 typo / README）
- 用户**显式说** "你直接做" / "approved" / "go ahead" —— 当次可免 gate
- `--yolo` 模式（用户明确 opt-out，但仍是用户授权）

## 工作流程（4 步）

### Step 1: 检测 protected action

每次准备执行 terminal 命令前，**自检**：

```
这个命令是否命中 P1-P5 任何一类？
  → 否：直接执行
  → 是：进 Step 2
```

### Step 2: 评估"是否会要求用户拍板"

判断维度：

- **用户上下文**：用户当前在做什么？该命令合理吗？
- **当前任务契约**：task-contract 是否已声明这个 action？
- **history**：用户是否之前预批过类似 action？

如果**不能确定**：进 Step 3。
如果**显然安全**（任务契约已写明 + 用户在看着）：直接执行，记录"无需 gate"原因。

### Step 3: 用 clarify() 询问

```python
clarify(
    question="<具体 protected action 描述> 涉及不可逆操作,需要你确认。",
    choices=[
        "批准执行",
        "先 dry-run 看看",
        "改用 trash (XDG) / 备份",
        "不做",
    ]
)
```

**重要**：
- **不在 question 里嵌选项**（用户硬偏好：clarify 的选项必须放 choices[]）
- 解释**为什么**这是 protected（不是无脑 prompt）
- 提供**安全替代**（trash vs rm，dry-run vs apply，备份后操作）

### Step 4: 执行 + 留痕

- 用户批准 → 执行 → 把 "approved by user at <time>" 写到 commit message / handoff
- 用户拒绝 → 任务回到 plan 阶段
- 跳过 gate 但事后反思 → 写 correction funnel 进 KB

## 推荐 hermes 全局配置

```bash
# 推荐：smart 模式（agent 用小 LLM 自动判断是否需要 prompt 用户）
hermes config set approvals.mode smart

# 关键 hooks 强制走 hermes shell-hooks-allowlist.json
# 本 skill 的 P 清单可作为生成该 allowlist 的模板
```

**注意**：本 skill **不直接改**用户的 hermes 全局配置 —— 那是用户的偏好决定权（你/用户拍板）。只**建议**配置，不强制设置。

## 与其它 skill 的接口

- **`task-contract`**：契约里应**预先声明**会执行的 protected action，让用户**开始前**就批准。
- **`worker-handoff`**：子 agent 收 context 时应知道 P 清单；执行 protected action 前**必暂停报告**，由主 agent 走 gate。
- **`adversarial-review-trigger`**：attack vector A1 "approval boundary that could not prove human presence" —— 直接对应本 skill。

## 与 fuzzy match 的边界（防"擦边动作漏掉"）

P 清单**不是穷举**。agent 应自问：

- "这个命令**难撤销**吗？" → 难 → 走 gate
- "这个命令**影响跨会话状态**吗？" → 是 → 走 gate
- "用户**不在场时**执行合理吗？" → 否（cron / async） → 走 gate

## References

- `references/protected-actions-deep-dive.md` — 每一类 P 的具体 case study + 真实事故模式
- `scripts/detect-protected-action.py` — 给定命令字符串，判断是否命中 P 清单（rule-based）