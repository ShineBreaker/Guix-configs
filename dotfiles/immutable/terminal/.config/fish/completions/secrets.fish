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

complete -c secrets -f
complete -c tools/secrets -f

complete -c secrets -n "not __fish_seen_subcommand_from init list ls recipients encrypt decrypt show edit re-encrypt" -l dry-run -d "只打印计划，不落盘（须置于子命令之前）"
complete -c tools/secrets -n "not __fish_seen_subcommand_from init list ls recipients encrypt decrypt show edit re-encrypt" -l dry-run -d "只打印计划，不落盘（须置于子命令之前）"

complete -c secrets -n "__fish_use_subcommand" -f -a init -d "生成 age 密钥对"
complete -c secrets -n "__fish_use_subcommand" -f -a list -d "列出密文 + 密钥状态"
complete -c secrets -n "__fish_use_subcommand" -f -a ls -d "list 别名"
complete -c secrets -n "__fish_use_subcommand" -f -a recipients -d "列出所有公钥"
complete -c secrets -n "__fish_use_subcommand" -f -a encrypt -d "加密 stdin → <name>.age"
complete -c secrets -n "__fish_use_subcommand" -f -a decrypt -d "解密 → secrets-decrypted/<name>"
complete -c secrets -n "__fish_use_subcommand" -f -a show -d "解密后 cat 明文"
complete -c secrets -n "__fish_use_subcommand" -f -a edit -d "解密 → \$EDITOR → 回写密文"
complete -c secrets -n "__fish_use_subcommand" -f -a re-encrypt -d "用当前公钥重加密全部密文"

complete -c tools/secrets -n "__fish_use_subcommand" -f -a init -d "生成 age 密钥对"
complete -c tools/secrets -n "__fish_use_subcommand" -f -a list -d "列出密文 + 密钥状态"
complete -c tools/secrets -n "__fish_use_subcommand" -f -a ls -d "list 别名"
complete -c tools/secrets -n "__fish_use_subcommand" -f -a recipients -d "列出所有公钥"
complete -c tools/secrets -n "__fish_use_subcommand" -f -a encrypt -d "加密 stdin → <name>.age"
complete -c tools/secrets -n "__fish_use_subcommand" -f -a decrypt -d "解密 → secrets-decrypted/<name>"
complete -c tools/secrets -n "__fish_use_subcommand" -f -a show -d "解密后 cat 明文"
complete -c tools/secrets -n "__fish_use_subcommand" -f -a edit -d "解密 → \$EDITOR → 回写密文"
complete -c tools/secrets -n "__fish_use_subcommand" -f -a re-encrypt -d "用当前公钥重加密全部密文"

complete -c secrets -n "__fish_seen_subcommand_from encrypt" -xa "(__fish_secrets_names)"
complete -c secrets -n "__fish_seen_subcommand_from decrypt show edit" -xa "(__fish_secrets_names)"
complete -c tools/secrets -n "__fish_seen_subcommand_from encrypt" -xa "(__fish_secrets_names)"
complete -c tools/secrets -n "__fish_seen_subcommand_from decrypt show edit" -xa "(__fish_secrets_names)"

complete -c secrets -n "__fish_seen_subcommand_from decrypt" -l stdout -d "直接打印到 stdout"
complete -c tools/secrets -n "__fish_seen_subcommand_from decrypt" -l stdout -d "直接打印到 stdout"

complete -c secrets -n "__fish_seen_subcommand_from re-encrypt" -l with -d "指定旧私钥路径" -r -F
complete -c tools/secrets -n "__fish_seen_subcommand_from re-encrypt" -l with -d "指定旧私钥路径" -r -F

complete -c secrets -s h -l help -d "显示帮助"
complete -c tools/secrets -s h -l help -d "显示帮助"
