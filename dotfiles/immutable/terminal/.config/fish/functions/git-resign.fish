# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function git-resign -d "重签名 <base-ref>..HEAD 的所有提交"
    if test (count $argv) -ne 1
        echo "用法: git-resign <base-ref>" >&2
        echo "  等价于: git rebase --exec 'git commit --amend --no-edit -S' <base-ref>" >&2
        echo "示例:" >&2
        echo "  git-resign HEAD~3      # 重签最近 3 个提交" >&2
        echo "  git-resign 43d43e4~1   # 重签 43d43e4 起（含）之后的所有提交" >&2
        return 1
    end

    set -l base $argv[1]
    git rebase --exec 'git commit --amend --no-edit -S' $base
    set -l result $status

    if test $result -eq 0
        echo "重签名完成，可用以下命令核验（%G? 显示 G 即签名有效）："
        echo "  git log --format='%h %G? %s' $base..HEAD"
    end
    return $result
end
