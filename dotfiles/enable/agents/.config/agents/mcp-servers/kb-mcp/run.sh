#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# kb-mcp 启动脚本
#
# 设计:
#   - 用 uv 跑临时依赖(免手动 venv):uv 自动建隔离环境 + 装 mcp[cli]。
#   - 工作目录切到脚本所在目录,保证 `python3 -m server` 路径稳定。
#   - `exec` 让 MCP 进程接管 PID,信号传递干净。
#   - PATH 中没有 uv 时回退到 ~/.guix-home/profile/bin/uv(项目惯例位置)。

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

if ! command -v uv >/dev/null 2>&1; then
	UV="${HOME}/.guix-home/profile/bin/uv"
	if [[ -x "${UV}" ]]; then
		export PATH="${HOME}/.guix-home/profile/bin:${PATH}"
	else
		echo "kb-mcp: uv not found in PATH and ${UV} missing" >&2
		exit 1
	fi
fi

# --no-project:避免 uv 看到 pyproject.toml 后尝试 hatch build wheel。
exec uv run --no-project --with "mcp[cli]>=1.0" python3 -m server
