# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# completions for denv — fish Tab 补全
# 覆盖子命令、flags、--lang 值（含别名）、--lang= 等号形式

# 子命令（未输入子命令时）
complete -c denv -f -n "not __fish_seen_subcommand_from init load remove status doctor" -a init -d "初始化项目结构 + direnv 环境"
complete -c denv -f -n "not __fish_seen_subcommand_from init load remove status doctor" -a load -d "仅创建 direnv 文件（无参回放 .denv）"
complete -c denv -f -n "not __fish_seen_subcommand_from init load remove status doctor" -a remove -d "删除 denv 管理的文件"
complete -c denv -f -n "not __fish_seen_subcommand_from init load remove status doctor" -a status -d "查看当前 denv 状态"
complete -c denv -f -n "not __fish_seen_subcommand_from init load remove status doctor" -a doctor -d "诊断并可选修复"

# 全局 --help
complete -c denv -f -s h -l help -d "显示帮助"

# init / load 共有 flags
complete -c denv -f -n "__fish_seen_subcommand_from init load" -s l -l lang -d "语言" -r -a "python node rust java c cpp csharp py js ts rs cs dotnet cc"
complete -c denv -f -n "__fish_seen_subcommand_from init load" -s L -l LLM -d "启用 LLM 脚手架 (AGENTS.md + .agents/skills)"
complete -c denv -f -n "__fish_seen_subcommand_from init load" -l full -d "配合 -L，使用完整 AGENTS.md 模板"
complete -c denv -f -n "__fish_seen_subcommand_from init load" -l no-guix -d "不注入 guix (manifest.scm / use guix)"
complete -c denv -f -n "__fish_seen_subcommand_from init load" -s f -l force -d "强制覆盖，跳过确认"

# 等号形式 --lang= 的值补全（fish 会在 = 后触发）
complete -c denv -f -n "__fish_seen_subcommand_from init load" -l lang -d "语言 (等号形式)" -r -a "python= node= rust= java= c= cpp= csharp="

# remove 专用
complete -c denv -f -n "__fish_seen_subcommand_from remove" -l all -d "连同 AGENTS.md / .agents/skills / .denv 一起删除"
complete -c denv -f -n "__fish_seen_subcommand_from remove" -s f -l force -d "跳过确认"

# doctor 专用
complete -c denv -f -n "__fish_seen_subcommand_from doctor" -l fix -d "自动修复可修复项"
