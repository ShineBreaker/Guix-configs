# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

complete -c hermes-install -x -a --setup -d "首次安装：跑容器内 setup-hermes.sh"
complete -c hermes-install -x -a --service-only -d "跳过安装，只把 gateway 交给 shepherd"
