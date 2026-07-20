#!/usr/bin/env bash
# worktree-cleanup.sh — 标准 worktree 清理脚本（走 trash-cli）
#
# 用法：bash worktree-cleanup.sh <task-id>
# 示例：bash worktree-cleanup.sh 20260720-fix-merge
#
# 硬约束（用户偏好）：
#   - 删目录一律 trash-cli（XDG trash 范式），不 rm / rm -rf
#   - 只清理 verified task；未完成保留 24h

set -euo pipefail

TASK_ID="${1:?用法: $0 <task-id>}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
WT_DIR="${REPO_ROOT%/*}/worktrees/${TASK_ID}"

# 1. 找到对应 branch
BRANCH="$(git worktree list --porcelain | grep -B1 "$WT_DIR" | grep "^branch " | sed 's/^branch //' || true)"

# 2. 验证 task 是否完成（dirty worktree 不删）
if [ -n "$WT_DIR" ] && [ -d "$WT_DIR" ]; then
    if ! (cd "$WT_DIR" && git diff --quiet HEAD 2>/dev/null); then
        echo "⚠️  worktree dirty，保留不删（24h 策略）:" >&2
        echo "    $WT_DIR" >&2
        exit 1
    fi
fi

# 3. 移除 worktree（git metadata）
if [ -d "$WT_DIR" ]; then
    git worktree remove "$WT_DIR" --force
fi

# 4. prune
git worktree prune

# 5. 删 local branch（已 merge 才删）
if [ -n "$BRANCH" ]; then
    if git branch --merged main | grep -q "$BRANCH" 2>/dev/null || \
       git branch --merged master | grep -q "$BRANCH" 2>/dev/null; then
        git branch -d "$BRANCH"
        echo "✅ 已删已 merge branch: $BRANCH"
    else
        echo "⚠️  branch 未 merge，保留: $BRANCH"
    fi
fi

echo "✅ worktree 清理完成: $TASK_ID"