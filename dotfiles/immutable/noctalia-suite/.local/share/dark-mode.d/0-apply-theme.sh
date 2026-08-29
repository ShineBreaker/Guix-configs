#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# darkman hook 入口（dark）：共享实现见 ../theme-common.sh。
# 不能用 symlink（immutable 经 Guix Home 复制进 store，链接行为不可靠），
# 用 exec 转发。darkman 约定本路径文件必须存在且可执行。
exec "$(dirname "$0")/../theme-common.sh" dark
