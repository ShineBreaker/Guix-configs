# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function __fish_askill_skills
    set -l lock $HOME/.config/agents/skills/skills-lock.json
    if test -f "$lock"
        jq -r '.skills | keys[]' "$lock" 2>/dev/null
    end
end

complete -c askill -f

complete -c askill -n "not __fish_seen_subcommand_from add update install remove sync list" -a add -d "安装上游 skill（写锁 + 落盘）"
complete -c askill -n "not __fish_seen_subcommand_from add update install remove sync list" -a update -d "按锁检查并更新全部"
complete -c askill -n "not __fish_seen_subcommand_from add update install remove sync list" -a install -d "从 skills-lock.json 恢复"
complete -c askill -n "not __fish_seen_subcommand_from add update install remove sync list" -a remove -d "卸载"
complete -c askill -n "not __fish_seen_subcommand_from add update install remove sync list" -a sync -d "仅同步暂存区 → 部署位置"
complete -c askill -n "not __fish_seen_subcommand_from add update install remove sync list" -a list -d "列出已纳管 skills"

complete -c askill -n "__fish_seen_subcommand_from add" -s s -d "仅安装指定 skill（逗号分隔）" -r
complete -c askill -n "__fish_seen_subcommand_from add" -s l -d "只列出不安装" -f
complete -c askill -n "__fish_seen_subcommand_from add" -l help -d "显示帮助" -f

complete -c askill -n "__fish_seen_subcommand_from remove" -xa "(__fish_askill_skills)"
