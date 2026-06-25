#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
# SPDX-License-Identifier: MIT

# 引导脚本：在一台只有 guix 的干净机器上（如官方 Guix ISO），
# 用锁定的频道与 manifest 准备一个带 `blue` 的 shell。
# 职责到此为止 —— 不分区、不跑 blue init，避免破坏性操作。
#
# 用法：./tools/bootstrap.sh
# 前置：已 guix system install 或用官方 ISO 启动；已 git clone 本仓库。

set -euo pipefail

# 定位仓库根（脚本在 tools/ 下，取其父目录），不依赖调用位置。
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHANNEL_LOCK="$REPO_ROOT/source/channel.lock"
MANIFEST="$REPO_ROOT/source/manifest.scm"

# 防御性检查：依赖文件缺失时给出可操作的报错，而非 guix 的晦涩信息。
for f in "$CHANNEL_LOCK" "$MANIFEST"; do
	if [[ ! -f "$f" ]]; then
		echo "错误: 缺少 $f —— 仓库是否完整？" >&2
		exit 1
	fi
done

echo ">> 用锁定频道准备引导 shell（首次较慢，会克隆并构建频道）..."
echo ">> channel.lock: $(grep -m1 commit "$CHANNEL_LOCK" || echo '未知')"
echo

# 进入临时 profile shell：blue 可用，频道版本与 channel.lock 完全一致。
# guix shell 默认是临时环境，退出即失效 —— 不污染 ISO 的全局 profile。
exec guix time-machine -C "$CHANNEL_LOCK" -- shell -m "$MANIFEST"
