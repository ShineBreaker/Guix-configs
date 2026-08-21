#!/usr/bin/env bash
# worktree-setup.sh — 标准 worktree 创建脚本
#
# 用法：bash worktree-setup.sh <task-id> [short-desc] [base-branch]
# 示例：bash worktree-setup.sh 20260720-fix-merge "fix-merge-conflict" main
#
# 硬约束：
#   - 不污染 source root（worktree 在 ../worktrees/）
#   - branch 名格式：task/<task-id>-<short-desc>
#   - trash-cli 清理（用户硬偏好）

set -euo pipefail

TASK_ID="${1:?用法: $0 <task-id> [short-desc] [base-branch]}"
SHORT_DESC="${2:-work}"
BASE_BRANCH="${3:-main}"

# 1. 确认在 git repo 内
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "❌ 不在 git repo 内" >&2
    exit 1
fi

# 2. 路径：<repo-parent>/worktrees/<task-id>
REPO_ROOT="$(git rev-parse --show-toplevel)"
WT_DIR="${REPO_ROOT%/*}/worktrees/${TASK_ID}"
BRANCH="task/${TASK_ID}-${SHORT_DESC}"

# 3. 已存在则报错（避免覆盖）
if git worktree list | grep -q "$WT_DIR"; then
    echo "❌ worktree 已存在: $WT_DIR" >&2
    exit 1
fi

# 4. 拉 base branch 最新（不强制）
git fetch origin "$BASE_BRANCH" 2>/dev/null || true

# 5. 创建 worktree + 新 branch
git worktree add -b "$BRANCH" "$WT_DIR" "origin/$BASE_BRANCH" 2>/dev/null || \
git worktree add -b "$BRANCH" "$WT_DIR" "$BASE_BRANCH"

# 6. 验证
echo "✅ worktree 创建完成:"
echo "   路径: $WT_DIR"
echo "   branch: $BRANCH"
echo "   base: $BASE_BRANCH"
echo ""
echo "   # 进入 worktree:"
echo "   cd $WT_DIR"
echo ""
echo "   # 子 agent 在此处工作"
echo "   # 完成后用 worktree-cleanup.sh 清理"