#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# darkman hook 入口（light）：exec 转发 ~/.local/libexec/theme-common.sh。
# 不能用 symlink（immutable 各文件独立 store 项，包内相对层级与链接
# 行为不可靠），须引用部署位置绝对路径——部署约束见
# docs/scripts/darkman-mode-hooks.md。darkman 约定本路径存在且可执行。
exec "${HOME}/.local/libexec/theme-common.sh" light
