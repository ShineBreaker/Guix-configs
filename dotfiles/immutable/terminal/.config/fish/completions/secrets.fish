# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function __fish_secrets_names
    set -l root (string join "/" -- (git rev-parse --show-toplevel 2>/dev/null) dotfiles/mutable/tools/secrets/.local/share/secrets-encrypted)
    if test -d $root
        for f in $root/*.age
            test -f "$f"; or continue
            basename $f .age
        end
        return
    end
    set -l fallback $HOME/Projects/Config/Guix-configs/dotfiles/mutable/tools/secrets/.local/share/secrets-encrypted
    if test -d "$fallback"
        for f in $fallback/*.age
            test -f "$f"; or continue
            basename $f .age
        end
    end
end

# 带条目名参数的子命令（解密类/编辑类）
set -l name_cmds decrypt show clip get env set edit add rename remove
set -l all_cmds "init list ls add encrypt decrypt show clip get env set edit rename remove clean recipients re-encrypt menu"

for c in secrets tools/secrets
    complete -c $c -f
    complete -c $c -n "not __fish_seen_subcommand_from $all_cmds" -l dry-run -d "只打印计划，不落盘（须置于子命令之前）"

    complete -c $c -n "__fish_use_subcommand" -f -a init -d "生成 age 密钥对"
    complete -c $c -n "__fish_use_subcommand" -f -a list -d "列出密文 + 密钥/明文状态"
    complete -c $c -n "__fish_use_subcommand" -f -a ls -d "list 别名"
    complete -c $c -n "__fish_use_subcommand" -f -a add -d "交互式新建条目"
    complete -c $c -n "__fish_use_subcommand" -f -a encrypt -d "加密 stdin → <name>.age"
    complete -c $c -n "__fish_use_subcommand" -f -a decrypt -d "解密 → tmpfs 明文"
    complete -c $c -n "__fish_use_subcommand" -f -a show -d "解密后 cat 明文"
    complete -c $c -n "__fish_use_subcommand" -f -a clip -d "复制到剪贴板，到时自动清空"
    complete -c $c -n "__fish_use_subcommand" -f -a get -d "提取 KEY= 单字段值"
    complete -c $c -n "__fish_use_subcommand" -f -a env -d "输出 export 行供 eval"
    complete -c $c -n "__fish_use_subcommand" -f -a set -d "改/加 KEY=\"value\" 行"
    complete -c $c -n "__fish_use_subcommand" -f -a edit -d "解密 → \$EDITOR → 回写密文"
    complete -c $c -n "__fish_use_subcommand" -f -a rename -d "重命名密文"
    complete -c $c -n "__fish_use_subcommand" -f -a remove -d "删除密文 + 明文副本"
    complete -c $c -n "__fish_use_subcommand" -f -a clean -d "清空 tmpfs 明文"
    complete -c $c -n "__fish_use_subcommand" -f -a recipients -d "列出所有公钥"
    complete -c $c -n "__fish_use_subcommand" -f -a re-encrypt -d "用当前公钥重加密全部密文"
    complete -c $c -n "__fish_use_subcommand" -f -a menu -d "fzf 交互菜单"

    complete -c $c -n "__fish_seen_subcommand_from $name_cmds" -xa "(__fish_secrets_names)"
    complete -c $c -n "__fish_seen_subcommand_from decrypt" -l stdout -d "直接打印到 stdout"
    complete -c $c -n "__fish_seen_subcommand_from re-encrypt" -l with -d "指定旧私钥路径" -r -F
    complete -c $c -s h -l help -d "显示帮助"
end
