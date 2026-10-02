#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
# SPDX-License-Identifier: MIT

# bootstrap.sh — 在干净 Guix 环境里开一个带 blue 的临时 shell（不分区、不动盘）
# 文档：docs/scripts/blue-helpers.md §bootstrap.sh

set -euo pipefail

die() {
  echo "bootstrap: 错误: $*" >&2
  exit 1
}

# 脚本在 tools/ 下，取其父目录为仓库根，不依赖调用位置
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHANNEL_LOCK="$REPO_ROOT/source/channel.lock"
MANIFEST="$REPO_ROOT/source/manifest.scm"

command -v guix >/dev/null 2>&1 || die "找不到 guix——本脚本面向已装好 Guix 的环境（官方 ISO 或已 guix system install 的系统）"
for f in "$CHANNEL_LOCK" "$MANIFEST"; do
  [[ -f "$f" ]] || die "缺少 $f——仓库是否完整？"
done

echo ">> 用锁定频道准备引导 shell（首次较慢，会克隆并构建频道）..."
echo ">> channel.lock: $(grep -m1 commit "$CHANNEL_LOCK" || echo '未知')"
echo

# 临时 profile shell：频道与 channel.lock 一致，退出即失效，不污染 ISO 全局 profile
exec guix time-machine -C "$CHANNEL_LOCK" -- shell -m "$MANIFEST"
