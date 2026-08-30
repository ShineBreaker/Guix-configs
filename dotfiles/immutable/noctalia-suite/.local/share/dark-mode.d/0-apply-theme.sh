#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# darkman hook 入口（dark）：共享实现在 ~/.local/libexec/theme-common.sh
# （内部脚本统一住 libexec，不混入 share 数据层）。
# 不能用 symlink（immutable 经 Guix Home 复制进 store，链接行为不可靠），
# 用 exec 转发；引用部署位置绝对路径（immutable 每文件独立 store 项，
# 包内相对层级在部署形态不成立）。darkman 约定本路径文件必须存在且可执行。
exec "${HOME}/.local/libexec/theme-common.sh" dark
